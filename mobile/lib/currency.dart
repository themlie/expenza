// Para birimi seçimi ve döviz kurları. Tutarlar sunucuda TRY'dir; ekranda seçili
// birime bu kurlarla çevrilir (bkz. format.dart).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Seçili para biriminin simgesi (₺, $, €, £). Profil ekranından değişir.
final ValueNotifier<String> currencyNotifier = ValueNotifier('₺');

class CurrencyService {
  static final Map<String, double> rates = {
    '₺': 1.0,
    '\$': 0.0303, // 1 TRY = 0.0303 USD (approx 33 TRY/USD)
    '€': 0.0278,  // 1 TRY = 0.0278 EUR (approx 36 TRY/EUR)
    '£': 0.0238,  // 1 TRY = 0.0238 GBP (approx 42 TRY/GBP)
  };

  static Future<void> updateRates() async {
    try {
      final res = await http.get(Uri.parse('https://open.er-api.com/v6/latest/TRY'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fetchedRates = data['rates'] as Map<String, dynamic>;
        rates['₺'] = 1.0;
        if (fetchedRates.containsKey('USD')) {
          rates['\$'] = (fetchedRates['USD'] as num).toDouble();
        }
        if (fetchedRates.containsKey('EUR')) {
          rates['€'] = (fetchedRates['EUR'] as num).toDouble();
        }
        if (fetchedRates.containsKey('GBP')) {
          rates['£'] = (fetchedRates['GBP'] as num).toDouble();
        }
      }
    } catch (e) {
      debugPrint('Döviz kurları güncellenemedi, varsayılan kurlar kullanılacak: $e');
    }
  }

  static double convertFromTry(double tryAmount, String targetSymbol) {
    final rate = rates[targetSymbol] ?? 1.0;
    return tryAmount * rate;
  }

  static double convertToTry(double targetAmount, String sourceSymbol) {
    final rate = rates[sourceSymbol] ?? 1.0;
    return targetAmount / rate;
  }
}
