// Kategori listesi backend'den gelir; görünüm bilinmeyen kategoriler için varsayılana düşer.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:expenza_mobile/categories.dart';

void main() {
  final local = List<String>.of(kCategories);
  tearDown(() => categoriesNotifier.value = local);

  test('yerel liste backend ile aynı sekiz kategori ve Toplam içermez', () {
    expect(local, hasLength(8));
    expect(local, isNot(contains(kTotalBudget)));
    expect(local.last, 'Diğer');
  });

  test('liste backend\'den yüklenir', () async {
    await http.runWithClient(loadCategories, () => MockClient((req) async {
          expect(req.url.path, '/categories');
          return http.Response.bytes(
              utf8.encode(jsonEncode(['Yemek', 'Evcil hayvan'])), 200);
        }));
    expect(kCategories, ['Yemek', 'Evcil hayvan']);
  });

  test('backend\'e ulaşılamazsa yerel liste kalır', () async {
    await http.runWithClient(loadCategories,
        () => MockClient((_) async => throw http.ClientException('kapalı')));
    expect(kCategories, local);
  });

  test('bilinmeyen kategori varsayılan ikon ve rengi alır', () {
    expect(categoryIcon('Evcil hayvan'), categoryIcon('Diğer'));
    expect(categoryColor('Evcil hayvan'), categoryColor('Diğer'));
    expect(categoryIcon('Yemek'), Icons.restaurant);
  });
}
