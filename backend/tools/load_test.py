"""Basit yük testi: çalışan bir backend'e eşzamanlı okuma istekleri gönderir.

Ayrı bir test kullanıcısı açar, ona --transactions kadar işlem ekler, sonra uygulamanın
en sık çağırdığı okuma uçlarına --workers iş parçacığıyla --seconds boyunca istek atar.
Uç bazında istek/saniye, gecikme yüzdelikleri (p50, p95, p99) ve hata oranı yazılır.

Sonuçlar makineye ve veritabanına bağlıdır; raporda ölçüm koşullarıyla birlikte verilmeli.
Gerçek kullanıcı verisinin olduğu bir veritabanında çalıştırmayın: test kullanıcısı ve
işlemleri kalıcı olarak eklenir.

Çalıştırma (backend çalışırken, backend klasöründe):
    python -m tools.load_test --url http://localhost:8010 --workers 8 --seconds 20
"""
import argparse
import random
import statistics
import sys
import threading
import time
import uuid
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

import httpx

ENDPOINTS = [
    ("GET /transactions/summary", "/transactions/summary"),
    ("GET /transactions?limit=200", "/transactions?limit=200"),
    ("GET /analytics/forecast", "/analytics/forecast"),
    ("GET /budgets", "/budgets"),
]
CATEGORIES = ["Yemek", "Ulaşım", "Faturalar", "Eğlence", "Sağlık", "Eğitim", "Alışveriş"]


def percentile(values: list[float], p: float) -> float:
    ordered = sorted(values)
    k = max(0, min(len(ordered) - 1, round(p / 100 * (len(ordered) - 1))))
    return ordered[k]


def prepare_user(client: httpx.Client, transactions: int) -> dict:
    email = f"yuktesti-{uuid.uuid4().hex[:8]}@example.com"
    password = "Yuk" + uuid.uuid4().hex[:10] + "1"
    client.post("/auth/register", json={"email": email, "password": password}).raise_for_status()
    token = client.post(
        "/auth/login", data={"username": email, "password": password}
    ).raise_for_status().json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    rng = random.Random(42)
    today = date.today()
    for _ in range(transactions):
        client.post(
            "/transactions",
            json={
                "amount": round(rng.uniform(10, 500), 2),
                "type": "expense",
                "category": rng.choice(CATEGORIES),
                "note": "yük testi",
                "occurred_on": (today - timedelta(days=rng.randrange(365))).isoformat(),
            },
            headers=headers,
        ).raise_for_status()
    return headers


def run(url: str, workers: int, seconds: float, transactions: int) -> None:
    with httpx.Client(base_url=url, timeout=30) as setup:
        headers = prepare_user(setup, transactions)

    latencies = defaultdict(list)
    errors = defaultdict(int)
    lock = threading.Lock()
    deadline = time.perf_counter() + seconds

    def worker(index: int) -> None:
        with httpx.Client(base_url=url, headers=headers, timeout=30) as client:
            i = index
            while time.perf_counter() < deadline:
                name, path = ENDPOINTS[i % len(ENDPOINTS)]
                i += 1
                start = time.perf_counter()
                try:
                    ok = client.get(path).status_code == 200
                except httpx.HTTPError:
                    ok = False
                elapsed = (time.perf_counter() - start) * 1000
                with lock:
                    latencies[name].append(elapsed)
                    if not ok:
                        errors[name] += 1

    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(worker, range(workers)))

    total = sum(len(v) for v in latencies.values())
    print(f"URL: {url}  eşzamanlı istemci: {workers}  süre: {seconds:.0f} sn  "
          f"kullanıcının işlem sayısı: {transactions}")
    print(f"Toplam {total} istek, {total / seconds:.1f} istek/sn\n")
    print(f"{'Uç':28s} {'istek':>6s} {'ist/sn':>7s} {'p50 ms':>8s} {'p95 ms':>8s} {'p99 ms':>8s} {'hata':>6s}")
    for name, _ in ENDPOINTS:
        values = latencies[name]
        if not values:
            continue
        print(f"{name:28s} {len(values):6d} {len(values) / seconds:7.1f} "
              f"{statistics.median(values):8.1f} {percentile(values, 95):8.1f} "
              f"{percentile(values, 99):8.1f} {errors[name]:6d}")


def main() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    parser = argparse.ArgumentParser(description="Expenza backend yük testi")
    parser.add_argument("--url", default="http://localhost:8010")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--seconds", type=float, default=20)
    parser.add_argument("--transactions", type=int, default=1000)
    args = parser.parse_args()
    run(args.url, args.workers, args.seconds, args.transactions)


if __name__ == "__main__":
    main()
