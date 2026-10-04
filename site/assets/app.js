/* Expenza tanıtım sayfası.
 * - Mobil menü düğmesi
 * - Ana bölümdeki canlı önizleme kartı: notu kelime eşleştirmesiyle
 *   kategorize eder, bütçeyi ve son işlemleri günceller.
 */
(function () {
  'use strict';

  /* ---------- Mobil menü ---------- */

  function setupMenu() {
    var btn = document.getElementById('nav-toggle');
    var menu = document.getElementById('mobile-menu');
    if (!btn || !menu) return;
    function setOpen(open) {
      menu.hidden = !open;
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      btn.setAttribute('aria-label', open ? 'Menüyü kapat' : 'Menüyü aç');
    }
    btn.addEventListener('click', function () { setOpen(menu.hidden); });
    menu.addEventListener('click', function (e) { if (e.target.closest('a')) setOpen(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !menu.hidden) { setOpen(false); btn.focus(); } });
  }

  /* ---------- Veri ---------- */

  var CATS = ['Yemek', 'Ulaşım', 'Faturalar', 'Eğlence', 'Sağlık', 'Eğitim', 'Alışveriş', 'Diğer'];
  var KW = {
    'Yemek': ['migros', 'market', 'a101', 'bim', 'carrefour', 'kahve', 'starbucks', 'restoran', 'lokanta', 'doner', 'pizza', 'burger', 'yemek', 'getir', 'kafe', 'simit', 'firin', 'manav', 'kasap', 'kahvalti'],
    'Ulaşım': ['uber', 'taksi', 'metro', 'otobus', 'istanbulkart', 'benzin', 'akaryakit', 'shell', 'opet', 'marti', 'vapur', 'marmaray', 'otopark', 'ucak', 'thy', 'pegasus', 'dolmus'],
    'Faturalar': ['fatura', 'elektrik', 'dogalgaz', 'internet', 'turkcell', 'vodafone', 'telekom', 'superonline', 'kira', 'aidat', 'enerjisa', 'igdas', 'iski'],
    'Eğlence': ['netflix', 'spotify', 'sinema', 'konser', 'mac bileti', 'tiyatro', 'oyun', 'steam', 'playstation', 'disney', 'youtube', 'exxen', 'bowling'],
    'Sağlık': ['eczane', 'ilac', 'hastane', 'doktor', 'disci', 'dis hekimi', 'muayene', 'vitamin', 'tahlil', 'gozluk'],
    'Eğitim': ['kurs', 'kitap', 'udemy', 'okul', 'ders', 'dershane', 'kirtasiye', 'universite', 'sinav'],
    'Alışveriş': ['trendyol', 'hepsiburada', 'amazon', 'zara', 'lcw', 'koton', 'ayakkabi', 'mont', 'kiyafet', 'teknosa', 'mediamarkt', 'ikea', 'kozmetik', 'gratis', 'watsons'],
    'Diğer': []
  };
  var BUD = {
    'Yemek': [2140, 3200], 'Ulaşım': [860, 1500], 'Faturalar': [1980, 2500], 'Eğlence': [520, 800],
    'Sağlık': [120, 600], 'Eğitim': [350, 1000], 'Alışveriş': [1460, 2000], 'Diğer': [240, 700]
  };
  var AUTO = [
    { note: 'uber ile eve', amount: '185' },
    { note: 'migros market', amount: '642,30' },
    { note: 'maç bileti', amount: '850' },
    { note: 'arkadaşa hediye', amount: '450', fallback: 'Alışveriş' },
    { note: 'netflix aboneliği', amount: '229,99' },
    { note: 'eczane', amount: '218,90' }
  ];
  var LEDGER = [
    { n: 'Elektrik faturası', c: 'Faturalar', a: 486 },
    { n: 'Kahvaltı', c: 'Yemek', a: 240 },
    { n: 'İstanbulkart dolum', c: 'Ulaşım', a: 300 }
  ];

  /* ---------- Yardımcılar ---------- */

  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function norm(t) {
    return String(t || '').toLocaleLowerCase('tr')
      .replace(/ı/g, 'i').replace(/ş/g, 's').replace(/ğ/g, 'g')
      .replace(/ü/g, 'u').replace(/ö/g, 'o').replace(/ç/g, 'c');
  }
  function tl(n) { return '₺' + Math.round(n).toLocaleString('tr-TR'); }
  function tl2(n) { return '₺' + Number(n).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
  function parseAmt(a) {
    var p = parseFloat(String(a || '').replace(/\s/g, '').replace(/\./g, '').replace(',', '.'));
    return isFinite(p) && p > 0 ? p : 0;
  }
  function cap(t) { t = String(t || '').trim(); return t ? t.charAt(0).toLocaleUpperCase('tr') + t.slice(1) : t; }
  function classify(note) {
    var text = norm(note).trim();
    var best = null, bestLen = 0, hits = 0;
    CATS.forEach(function (c) {
      var found = 0;
      KW[c].forEach(function (k) { if (text.indexOf(k) !== -1 && k.length > found) found = k.length; });
      if (found) { hits++; if (found > bestLen) { bestLen = found; best = c; } }
    });
    var conf = best ? Math.min(97, 86 + bestLen) : 38;
    if (best && hits > 1) conf = 64;
    return { cat: best || 'Diğer', conf: conf, low: conf < 60, empty: text.length === 0 };
  }
  function when(cond, html) { return cond ? html : '<!---->'; }

  /* Yeni işaretlemeyi mevcut DOM'a düğüm düğüm uygular. Böylece değişmeyen
   * öğeler yerinde kalır, animasyonlar baştan başlamaz, odak kaybolmaz. */
  function morph(from, to) {
    if (from.nodeType !== 1) {
      if (from.nodeValue !== to.nodeValue) from.nodeValue = to.nodeValue;
      return;
    }
    var i, a;
    for (i = from.attributes.length - 1; i >= 0; i--) {
      a = from.attributes[i].name;
      if (!to.hasAttribute(a)) from.removeAttribute(a);
    }
    for (i = 0; i < to.attributes.length; i++) {
      a = to.attributes[i];
      if (from.getAttribute(a.name) !== a.value) from.setAttribute(a.name, a.value);
    }
    if (from.tagName === 'INPUT') {
      var v = to.getAttribute('value') || '';
      // Yazarken değer zaten aynıdır; yalnızca farklıysa yazmak imleci korur.
      if (from.value !== v) from.value = v;
      return;
    }
    var fc = from.childNodes, tc = to.childNodes;
    for (i = 0; i < tc.length; i++) {
      var f = fc[i], t = tc[i];
      if (!f) from.appendChild(t.cloneNode(true));
      else if (f.nodeName !== t.nodeName) from.replaceChild(t.cloneNode(true), f);
      else morph(f, t);
    }
    while (fc.length > tc.length) from.removeChild(from.lastChild);
  }

  /* ---------- Canlı önizleme ---------- */

  var FONT = "font-family: 'Jost', 'Futura', 'Century Gothic', system-ui, sans-serif";
  var MONO = "font-family: 'DM Mono', ui-monospace, monospace";
  var LABEL = 'font-size: 12px; font-weight: 500; letter-spacing: 0.16em; text-transform: uppercase; color: #5D5C57';
  var CHECK = '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true"><circle cx="9" cy="9" r="8" stroke="#1F2F57" stroke-width="1.4"></circle><path d="M5.5 9.2l2.3 2.3 4.7-4.9" stroke="#1F2F57" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"></path></svg>';
  var PAUSE = '<svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><rect x="2" y="1.5" width="2.6" height="9" rx="1" fill="currentColor"></rect><rect x="7.4" y="1.5" width="2.6" height="9" rx="1" fill="currentColor"></rect></svg>';
  var PLAY = '<svg width="12" height="12" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 1.8v8.4a.6.6 0 0 0 .9.5l6.6-4.2a.6.6 0 0 0 0-1L3.9 1.3a.6.6 0 0 0-.9.5z" fill="currentColor"></path></svg>';

  function Demo(root) {
    this.root = root;
    this.state = {};
    this.timers = [];
    this.tpl = document.createElement('template');
  }

  Demo.prototype.setState = function (patch, cb) {
    for (var k in patch) this.state[k] = patch[k];
    this.render();
    if (cb) cb.call(this);
  };
  Demo.prototype.later = function (ms, fn) { this.timers.push(setTimeout(fn.bind(this), ms)); };
  Demo.prototype.stopTimers = function () { this.timers.forEach(clearTimeout); this.timers = []; };
  Demo.prototype.stopAuto = function (extra) {
    this.stopTimers();
    var p = { auto: false, pressing: false, keepChooser: false, phase: 'result' };
    for (var k in extra || {}) p[k] = extra[k];
    this.setState(p);
  };
  Demo.prototype.currentExample = function () { return AUTO[(this.state.autoIdx || 0) % AUTO.length]; };

  Demo.prototype.start = function () {
    this.bind();
    this.render();
    var reduce = false;
    try { reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) {}
    if (reduce) return;
    this.setState({ auto: true, phase: 'typing', note: '', amount: '', autoIdx: 0 });
    this.later(1300, function () { this.play(0); });
  };

  Demo.prototype.play = function (i) {
    var self = this;
    var ex = AUTO[i % AUTO.length];
    var t = 350, k;
    this.stopTimers();
    this.setState({ auto: true, autoIdx: i, note: '', amount: '', phase: 'typing', accepted: false, pick: null, choosing: false, keepChooser: false, pressing: false, confShown: 0 });
    for (k = 1; k <= ex.note.length; k++) {
      (function (kk, at) { self.later(at, function () { this.setState({ note: ex.note.slice(0, kk) }); }); })(k, t);
      t += 55 + ((k * 37) % 4) * 14;
    }
    t += 220;
    this.later(t, function () { this.setState({ phase: 'typingAmount' }); });
    t += 80;
    for (k = 1; k <= ex.amount.length; k++) {
      (function (kk, at) { self.later(at, function () { this.setState({ amount: ex.amount.slice(0, kk) }); }); })(k, t);
      t += 85;
    }
    t += 300;
    this.later(t, function () { this.setState({ phase: 'thinking' }); });
    t += 850;
    var target = classify(ex.note).conf;
    this.later(t, function () { this.setState({ phase: 'result', confShown: 0 }); });
    for (k = 1; k <= 12; k++) {
      (function (kk, at) {
        self.later(at, function () { var p = kk / 12; this.setState({ confShown: Math.round(target * (1 - Math.pow(1 - p, 3))) }); });
      })(k, t + k * 40);
    }
    t += 1150;
    if (target < 60 && ex.fallback) {
      this.later(t, function () { this.setState({ pick: ex.fallback, keepChooser: true }); });
      t += 750;
      this.later(t, function () { this.setState({ keepChooser: false }); });
      t += 500;
    }
    this.later(t, function () { this.setState({ pressing: true }); });
    t += 220;
    this.later(t, function () { this.setState({ pressing: false }, this.commit); });
    t += 2400;
    this.later(t, function () { this.play(i + 1); });
  };

  Demo.prototype.commit = function () {
    var s = this.state;
    var note = s.note != null ? s.note : 'uber ile eve';
    var amount = s.amount != null ? s.amount : '185';
    var cat = s.pick || classify(note).cat;
    var led = (s.ledger || LEDGER).slice();
    led.unshift({ n: cap(note), c: cat, a: parseAmt(amount) });
    this.setState({ accepted: true, phase: 'result', ledger: led.slice(0, 3), ledgerN: (s.ledgerN || 0) + 1 });
  };

  /* Kullanıcı kartla etkileşime girince otomatik oynatma durur. */
  Demo.prototype.takeOver = function () {
    if (!this.state.auto) return;
    var ex = this.currentExample();
    this.stopAuto(this.state.accepted ? {} : { note: ex.note, amount: ex.amount });
  };

  Demo.prototype.bind = function () {
    var self = this;
    this.root.addEventListener('click', function (e) {
      var el = e.target.closest('[data-act]');
      if (!el || !self.root.contains(el)) return;
      var act = el.getAttribute('data-act');
      var arg = el.getAttribute('data-arg');
      if (act === 'toggle') {
        if (self.state.auto) self.takeOver();
        else self.play((self.state.autoIdx || 0) + 1);
      } else if (act === 'example') {
        var j = +arg, x = AUTO[j];
        self.stopAuto({ note: x.note, amount: x.amount, accepted: false, pick: null, choosing: false, autoIdx: j });
      } else if (act === 'pick') {
        self.stopAuto({ pick: arg, choosing: false });
      } else if (act === 'accept') {
        self.stopTimers();
        self.setState({ auto: false, pressing: false, keepChooser: false, phase: 'result' }, self.commit);
      } else if (act === 'change') {
        self.stopAuto({ choosing: true });
      }
    });
    this.root.addEventListener('input', function (e) {
      if (e.target.id === 'demo-note') self.stopAuto({ note: e.target.value, accepted: false, pick: null, choosing: false });
      else if (e.target.id === 'demo-amount') self.stopAuto({ amount: e.target.value, accepted: false });
    });
    this.root.addEventListener('focusin', function (e) {
      if (e.target.tagName === 'INPUT') self.takeOver();
    });
  };

  Demo.prototype.render = function () {
    var s = this.state;
    var auto = !!s.auto;
    var phase = s.phase || 'result';
    var note = s.note != null ? s.note : 'uber ile eve';
    var amount = s.amount != null ? s.amount : '185';
    var r = classify(note);
    var pick = s.pick || null;
    var cat = pick || r.cat;
    var accepted = !!s.accepted;
    var hasNote = !r.empty;
    var typing = auto && (phase === 'typing' || phase === 'typingAmount');
    var thinking = auto && phase === 'thinking';
    var showWaiting = typing || thinking || !hasNote;
    var showResult = !showWaiting;
    var showChooser = showResult && !accepted && (r.low || !!s.choosing) && (!pick || !!s.keepChooser);
    var showActions = showResult && !accepted && !showChooser;
    var conf = auto ? (s.confShown || 0) : r.conf;
    var stepIdx = typing ? 0 : thinking ? 1 : !hasNote ? 0 : accepted ? 3 : 2;
    var idx = (s.autoIdx || 0) % AUTO.length;
    var popAnim = auto ? ((s.autoIdx || 0) % 2 === 1 ? 'ex-pop-b' : 'ex-pop-a') : 'none';

    var amt = parseAmt(amount);
    var b = BUD[cat];
    var spent = b[0], limit = b[1];
    var total = spent + amt;
    var over = total > limit;
    var spentPct = Math.min(100, spent / limit * 100);
    var addPct = Math.max(0, Math.min(100 - spentPct, amt / limit * 100));
    var addColor = over ? '#A24B26' : '#1F2F57';
    var confColor = (pick || !r.low) ? '#1F2F57' : '#A24B26';

    var ln = s.ledgerN || 0;
    var ledgerAnim = ln === 0 ? 'none' : (ln % 2 ? 'ex-push-a' : 'ex-push-b');
    var firstAnim = ln === 0 ? 'none' : (ln % 2 ? 'ex-in-a' : 'ex-in-b');
    var ledger = s.ledger || LEDGER;

    var statusText;
    if (over) statusText = accepted ? ('Limit ' + tl(total - limit) + ' aşıldı') : ('Eklenince limiti ' + tl(total - limit) + ' aşacaksın');
    else statusText = accepted ? ('Kalan ' + tl(limit - total) + ' · ay sonuna 28 gün') : ('Eklenince kalan ' + tl(limit - total));

    var skel = thinking ? 'skel-fast' : 'skel';
    var waitText = thinking ? 'Kategori analiz ediliyor' : (auto ? 'Not yazılıyor' : 'Yazmaya başla; öneri burada görünecek.');
    var dot = 'width: 5px; height: 5px; border-radius: 999px; background: #1F2F57';
    var caretBox = 'position: absolute; inset: 0; display: flex; align-items: center; pointer-events: none; white-space: pre; overflow: hidden';

    var h = '' +
      '<div style="display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap">' +
        '<div style="display: flex; align-items: center; gap: 10px">' +
          when(auto, '<span class="ex-ping" style="width: 7px; height: 7px; border-radius: 999px; background: #1F2F57; color: #1F2F57"></span>') +
          '<span style="font-size: 12px; font-weight: 500; letter-spacing: 0.16em; text-transform: uppercase; color: #1F2F57">Canlı önizleme</span>' +
        '</div>' +
        '<button type="button" class="ex-chip" data-act="toggle" style="display: inline-flex; align-items: center; gap: 8px; height: 36px; padding: 0 14px; border-radius: 999px; border: 1px solid #D3C9B6; background: transparent; ' + FONT + '; font-size: 14px; font-weight: 500; color: #26282C; cursor: pointer">' +
          (auto ? PAUSE : PLAY) + '<span>' + (auto ? 'Duraklat' : 'Oynat') + '</span>' +
        '</button>' +
      '</div>' +

      '<ol aria-label="Önizleme adımları" style="list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 8px">' +
        ['Yaz', 'Analiz', 'Kategori', 'Bütçe'].map(function (l, i) {
          var bar = i === stepIdx ? '#1F2F57' : '#26282C';
          var color = i === stepIdx ? '#1F2F57' : (i < stepIdx ? '#26282C' : '#5D5C57');
          return '<li style="display: flex; flex-direction: column; gap: 8px; min-width: 0">' +
            '<div style="height: 3px; border-radius: 999px; background: #E3DBCB; overflow: hidden"><div class="bar-fill" style="height: 100%; width: ' + (i <= stepIdx ? 100 : 0) + '%; background: ' + bar + '"></div></div>' +
            '<span style="font-size: 11px; font-weight: 500; letter-spacing: 0.14em; text-transform: uppercase; color: ' + color + '; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">0' + (i + 1) + ' ' + l + '</span>' +
          '</li>';
        }).join('') +
      '</ol>' +

      '<div style="display: flex; flex-wrap: wrap; gap: 12px">' +
        '<div style="flex: 1 1 260px; display: flex; flex-direction: column; gap: 8px">' +
          '<label for="demo-note" style="font-size: 14px; font-weight: 500; color: #3A3C40">Not</label>' +
          '<div style="position: relative">' +
            '<input id="demo-note" class="ex-input" type="text" autocomplete="off" value="' + esc(note) + '" placeholder="örn. migros market" style="height: 54px; padding: 0 18px; border-radius: 14px; border: 1px solid #D3C9B6; background: #FBF9F4; ' + FONT + '; font-size: 18px; color: #26282C; width: 100%">' +
            when(auto && phase === 'typing', '<div aria-hidden="true" style="' + caretBox + '; padding: 0 19px; ' + FONT + '; font-size: 18px"><span style="visibility: hidden">' + esc(note) + '</span><span class="caret"></span></div>') +
          '</div>' +
        '</div>' +
        '<div style="flex: 1 1 140px; display: flex; flex-direction: column; gap: 8px">' +
          '<label for="demo-amount" style="font-size: 14px; font-weight: 500; color: #3A3C40">Tutar</label>' +
          '<div style="position: relative">' +
            '<span aria-hidden="true" style="position: absolute; left: 16px; top: 50%; transform: translateY(-50%); ' + MONO + '; font-size: 17px; color: #5D5C57">₺</span>' +
            '<input id="demo-amount" class="ex-input" type="text" inputmode="decimal" autocomplete="off" value="' + esc(amount) + '" style="height: 54px; padding: 0 16px 0 36px; border-radius: 14px; border: 1px solid #D3C9B6; background: #FBF9F4; ' + MONO + '; font-size: 17px; color: #26282C; width: 100%">' +
            when(auto && phase === 'typingAmount', '<div aria-hidden="true" style="' + caretBox + '; padding: 0 17px 0 37px; ' + MONO + '; font-size: 17px"><span style="visibility: hidden">' + esc(amount) + '</span><span class="caret"></span></div>') +
          '</div>' +
        '</div>' +
      '</div>' +

      '<div style="display: flex; flex-wrap: wrap; align-items: center; gap: 8px">' +
        '<span style="font-size: 14px; color: #5D5C57; margin-right: 4px">Örnekler</span>' +
        AUTO.map(function (x, j) {
          var on = auto && j === idx;
          return '<button type="button" class="ex-chip" data-act="example" data-arg="' + j + '" style="height: 36px; padding: 0 14px; border-radius: 999px; border: 1px solid ' + (on ? '#26282C' : '#D3C9B6') + '; background: ' + (on ? '#EDE6D9' : 'transparent') + '; ' + FONT + '; font-size: 15px; color: #26282C; cursor: pointer">' + esc(x.note) + '</button>';
        }).join('') +
      '</div>' +
      '<div style="height: 1px; background: #D3C9B6"></div>' +

      '<div style="min-height: 214px">' +
        when(showWaiting,
          '<div style="display: flex; flex-wrap: wrap; gap: 28px">' +
            '<div style="flex: 1 1 240px; display: flex; flex-direction: column; gap: 12px; min-width: 0">' +
              '<span style="' + LABEL + '">Önerilen kategori</span>' +
              '<div class="' + skel + '" style="width: 62%; height: 38px; border-radius: 10px; background: #E3DBCB"></div>' +
              '<div class="' + skel + '" style="width: 42%; max-width: 220px; height: 4px; border-radius: 999px; background: #E3DBCB"></div>' +
              '<div style="display: flex; align-items: center; gap: 10px; margin-top: 6px; font-size: 15px; color: #5D5C57">' +
                '<span>' + waitText + '</span>' +
                when(thinking, '<span aria-hidden="true" style="display: inline-flex; gap: 4px"><span class="lp-dot" style="' + dot + '"></span><span class="lp-dot" style="' + dot + '; animation-delay: 0.15s"></span><span class="lp-dot" style="' + dot + '; animation-delay: 0.3s"></span></span>') +
              '</div>' +
            '</div>' +
            '<div style="flex: 1 1 240px; display: flex; flex-direction: column; gap: 12px; min-width: 0">' +
              '<span style="' + LABEL + '">Bu ay · bütçe</span>' +
              '<div class="' + skel + '" style="width: 50%; height: 30px; border-radius: 10px; background: #E3DBCB"></div>' +
              '<div style="height: 10px; border-radius: 999px; background: #E3DBCB"></div>' +
            '</div>' +
          '</div>') +
        when(showResult,
          '<div style="display: flex; flex-wrap: wrap; gap: 28px">' +
            '<div style="flex: 1 1 240px; display: flex; flex-direction: column; gap: 12px; min-width: 0">' +
              '<span style="' + LABEL + '">Önerilen kategori</span>' +
              '<div style="display: flex; align-items: baseline; gap: 12px; flex-wrap: wrap; animation: ' + popAnim + ' 0.55s cubic-bezier(.2,.7,.2,1) both">' +
                '<span style="font-size: 40px; font-weight: 400; letter-spacing: -0.02em; line-height: 1">' + cat + '</span>' +
                '<span style="' + MONO + '; font-size: 13px; color: ' + confColor + '">' + (pick ? 'senin seçimin' : ('%' + conf + ' güven')) + '</span>' +
              '</div>' +
              '<div style="height: 4px; border-radius: 999px; background: #E3DBCB; overflow: hidden; max-width: 220px">' +
                '<div class="bar-fill" style="height: 100%; width: ' + (pick ? 100 : conf) + '%; background: ' + confColor + '"></div>' +
              '</div>' +
              when(showChooser,
                '<div style="display: flex; flex-direction: column; gap: 12px">' +
                  '<p style="font-size: 15px; line-height: 1.45; color: #3A3C40; margin-top: 4px">' + (r.low ? 'Bu notta emin olamadım. Kategoriyi sen seç:' : 'Doğru kategoriyi seç:') + '</p>' +
                  '<div style="display: flex; flex-wrap: wrap; gap: 6px">' +
                    CATS.map(function (c) {
                      var on = c === cat;
                      return '<button type="button" class="ex-chip" data-act="pick" data-arg="' + c + '" aria-pressed="' + on + '" style="height: 36px; padding: 0 12px; border-radius: 999px; border: 1px solid ' + (on ? '#1F2F57' : '#D3C9B6') + '; background: ' + (on ? '#1F2F57' : 'transparent') + '; color: ' + (on ? '#F7F3EC' : '#26282C') + '; ' + FONT + '; font-size: 14px; font-weight: 500; cursor: pointer">' + c + '</button>';
                    }).join('') +
                  '</div>' +
                '</div>') +
              when(showActions,
                '<div style="display: flex; flex-wrap: wrap; gap: 8px; margin-top: 4px">' +
                  '<button type="button" class="ex-btn ex-btn-primary" data-act="accept" style="height: 44px; padding: 0 20px; border-radius: 999px; border: 0; background: ' + (s.pressing ? '#16223F' : '#1F2F57') + '; transform: scale(' + (s.pressing ? '0.94' : '1') + '); transition: transform .15s ease, background-color .15s ease; color: #F7F3EC; ' + FONT + '; font-size: 15px; font-weight: 500; cursor: pointer">Kabul et</button>' +
                  '<button type="button" class="ex-btn ex-btn-secondary" data-act="change" style="height: 44px; padding: 0 18px; border-radius: 999px; border: 1px solid #D3C9B6; background: transparent; color: #26282C; ' + FONT + '; font-size: 15px; font-weight: 500; cursor: pointer">Değiştir</button>' +
                '</div>') +
              when(accepted && showResult,
                '<div role="status" style="display: flex; align-items: center; gap: 8px; height: 44px; font-size: 16px; font-weight: 500; color: #1F2F57; animation: ' + popAnim + ' 0.5s cubic-bezier(.2,.7,.2,1) both">' +
                  CHECK + '<span>Kaydedildi, bütçen güncellendi.</span>' +
                '</div>') +
            '</div>' +
            '<div style="flex: 1 1 240px; display: flex; flex-direction: column; gap: 12px; min-width: 0">' +
              '<span style="' + LABEL + '">Bu ay · ' + cat + ' bütçesi</span>' +
              '<div style="display: flex; align-items: baseline; gap: 6px; flex-wrap: wrap">' +
                '<span style="font-size: 32px; font-weight: 400; letter-spacing: -0.02em; font-variant-numeric: tabular-nums">' + tl(accepted ? total : spent) + '</span>' +
                '<span style="' + MONO + '; font-size: 14px; color: #5D5C57">/ ' + tl(limit) + '</span>' +
              '</div>' +
              '<div style="height: 10px; border-radius: 999px; background: #E3DBCB; overflow: hidden; display: flex">' +
                '<div class="bar-fill" style="height: 100%; width: ' + spentPct.toFixed(1) + '%; background: #26282C"></div>' +
                '<div class="bar-fill" style="height: 100%; width: ' + addPct.toFixed(1) + '%; background: ' + addColor + '; opacity: ' + (accepted ? '1' : '0.45') + '"></div>' +
              '</div>' +
              '<div style="display: flex; flex-wrap: wrap; gap: 6px 16px; font-size: 14px; color: #5D5C57">' +
                '<span style="display: inline-flex; align-items: center; gap: 6px"><span style="width: 8px; height: 8px; border-radius: 2px; background: #26282C"></span>Bu ay ' + tl(spent) + '</span>' +
                '<span style="display: inline-flex; align-items: center; gap: 6px"><span style="width: 8px; height: 8px; border-radius: 2px; background: ' + addColor + '"></span>Bu harcama ' + tl(amt) + '</span>' +
              '</div>' +
              '<p style="font-size: 16px; font-weight: 500; color: ' + (over ? '#A24B26' : '#26282C') + '; margin-top: 2px">' + statusText + '</p>' +
            '</div>' +
          '</div>') +
      '</div>' +

      '<div style="display: flex; flex-direction: column; gap: 8px; padding-top: 16px; border-top: 1px solid #D3C9B6">' +
        '<span style="' + LABEL + '">Son işlemler</span>' +
        '<div style="height: 126px; overflow: hidden">' +
          '<div style="display: flex; flex-direction: column; animation: ' + ledgerAnim + ' 0.55s cubic-bezier(.2,.7,.2,1) both">' +
            ledger.map(function (row, i) {
              return '<div style="height: 42px; flex: none; display: flex; align-items: center; gap: 10px; border-bottom: 1px solid #E3DBCB; animation: ' + (i === 0 ? firstAnim : 'none') + ' 0.6s ease both">' +
                '<span style="font-size: 16px; font-weight: 500; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap">' + esc(row.n) + '</span>' +
                '<span style="font-size: 11px; font-weight: 500; letter-spacing: 0.14em; text-transform: uppercase; color: #5D5C57; white-space: nowrap">' + row.c + '</span>' +
                '<span aria-hidden="true" style="flex: 1 1 12px; border-bottom: 1px dotted #A9A69E; transform: translateY(-3px)"></span>' +
                '<span style="' + MONO + '; font-size: 14px; white-space: nowrap">−' + tl2(row.a) + '</span>' +
              '</div>';
            }).join('') +
          '</div>' +
        '</div>' +
      '</div>' +

      '<p style="font-size: 13px; line-height: 1.5; color: #5D5C57">Önizleme basit bir kelime eşleştirmesiyle çalışır; içine tıklayıp kendin yazabilirsin. Uygulamada Türkçe harcama notlarıyla eğitilmiş model kullanılır.</p>';

    this.tpl.innerHTML = h;
    var target = document.createElement('div');
    target.appendChild(this.tpl.content);
    morph(this.root, cloneAttrs(this.root, target));
  };

  /* morph kökün özniteliklerini de eşitlediği için hedefe kökün kendi
   * özniteliklerini kopyalarız; sadece içerik değişir. */
  function cloneAttrs(src, dst) {
    for (var i = 0; i < src.attributes.length; i++) dst.setAttribute(src.attributes[i].name, src.attributes[i].value);
    return dst;
  }

  document.addEventListener('DOMContentLoaded', function () {
    setupMenu();
    var root = document.getElementById('demo');
    if (root) new Demo(root).start();
  });
})();
