import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';

/// Kategoriler: istemcideki tek kaynak.
///
/// Hangi kategorilerin olduğunu backend belirler (GET /categories, açılışta
/// [loadCategories] ile yüklenir). Burada yalnızca her kategorinin görünümü (ikon ve
/// renk) tutulur. Backend yeni bir kategori eklerse uygulama onu varsayılan ikon ve
/// renkle gösterir; güncelleme gerekmez.

/// Bütün giderleri kapsayan bütçe. Bir işlem kategorisi değildir; yalnızca bütçelerde
/// kullanılır.
const kTotalBudget = 'Toplam';

// Renkler marka paletine göre seçildi ve renk körlüğü/kontrast kontrolünden geçti
// (açık mod bej, koyu mod antrasit kart zemininde). Sıra sabit: grafiklerde komşu
// dilimler birbirinden ayrışır. Diğer bilinçli olarak nötr gri.
const _styles = <String, ({IconData icon, Color light, Color dark})>{
  'Yemek': (icon: Icons.restaurant, light: Color(0xFF2E64B5), dark: Color(0xFF5B8BD6)),
  'Ulaşım': (icon: Icons.directions_car, light: Color(0xFFB8761F), dark: Color(0xFFBA7E2C)),
  'Faturalar': (icon: Icons.receipt_long, light: Color(0xFF1E9A85), dark: Color(0xFF2AA38D)),
  'Eğlence': (icon: Icons.movie, light: Color(0xFF8A4FA0), dark: Color(0xFFA776C2)),
  'Sağlık': (icon: Icons.medical_services, light: Color(0xFF3E8A4A), dark: Color(0xFF57A062)),
  'Eğitim': (icon: Icons.school, light: Color(0xFF5B4FB0), dark: Color(0xFF8A7FE0)),
  'Alışveriş': (icon: Icons.shopping_bag, light: Color(0xFFC25B7E), dark: Color(0xFFC66A88)),
  'Diğer': _fallback,
};

const _fallback = (icon: Icons.more_horiz, light: Color(0xFF8C8A84), dark: Color(0xFF8E8B84));

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

Color categoryColor(String category) {
  final st = _styles[category] ?? _fallback;
  return AppColors.isDark ? st.dark : st.light;
}
