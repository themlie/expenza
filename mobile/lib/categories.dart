import 'package:flutter/material.dart';

import 'api_client.dart';

/// Kategoriler: istemcideki tek kaynak.
///
/// Hangi kategorilerin olduğunu backend belirler (GET /categories, açılışta
/// [loadCategories] ile yüklenir). Burada yalnızca her kategorinin görünümü (ikon ve
/// renk) tutulur. Backend yeni bir kategori eklerse uygulama onu varsayılan ikon ve
/// renkle gösterir; güncelleme gerekmez.

/// Bütün giderleri kapsayan bütçe. Bir işlem kategorisi değildir; yalnızca bütçelerde
/// kullanılır.
const kTotalBudget = 'Toplam';

const _styles = <String, ({IconData icon, Color color})>{
  'Yemek': (icon: Icons.restaurant, color: Color(0xFF46F1C5)),
  'Ulaşım': (icon: Icons.directions_car, color: Color(0xFF6EA8FE)),
  'Faturalar': (icon: Icons.receipt_long, color: Color(0xFFB68CF0)),
  'Eğlence': (icon: Icons.movie, color: Color(0xFFF0B36B)),
  'Sağlık': (icon: Icons.medical_services, color: Color(0xFFF2766B)),
  'Eğitim': (icon: Icons.school, color: Color(0xFF5FD4C2)),
  'Alışveriş': (icon: Icons.shopping_bag, color: Color(0xFFEC9BC4)),
  'Diğer': _fallback,
};

const _fallback = (icon: Icons.more_horiz, color: Color(0xFF8A958F));

/// Backend'den gelen kategori listesi. Backend'e ulaşılamazsa yukarıdaki görünüm
/// tablosundaki sıra kullanılır.
final categoriesNotifier = ValueNotifier<List<String>>(_styles.keys.toList());

/// İşlem kategorileri ("Toplam" dahil değil).
List<String> get kCategories => categoriesNotifier.value;

/// Kategori listesini backend'den yükler. Hata olursa yerel liste kalır.
Future<void> loadCategories() async {
  try {
    final names = await ApiClient.instance.getCategories();
    if (names.isNotEmpty) categoriesNotifier.value = names;
  } catch (_) {
    // Çevrimdışı ya da sunucu kapalı: yerel liste yeterli.
  }
}

IconData categoryIcon(String category) => (_styles[category] ?? _fallback).icon;

Color categoryColor(String category) => (_styles[category] ?? _fallback).color;
