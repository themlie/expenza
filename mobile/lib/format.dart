// Ekranların ortak biçimlendirme ve girdi kuralları.
//
// Tutarlar sunucuda TRY olarak tutulur; ekranda kullanıcının seçtiği para biriminde
// gösterilir ve girilir. Çevirme yalnızca burada yapılır.
import 'package:intl/intl.dart';

import 'theme.dart' show CurrencyService, currencyNotifier;

export 'categories.dart' show categoryColor, categoryIcon;

final _grp = NumberFormat('#,##0', 'tr_TR');

/// Binlik ayraçlı tam sayı ("12.500").
String groupDigits(num v) => _grp.format(v);

/// Para gösterimi: işaret + simge + binlik ayraç, küsurat varsa 2 hane.
/// [v] TRY'dir; seçili para birimine çevrilerek yazılır.
String money(double v, {bool showSign = false}) {
  final converted = CurrencyService.convertFromTry(v, currencyNotifier.value);
  final neg = converted < 0;
  final abs = converted.abs();
  final whole = abs.truncate();
  final cents = ((abs - whole) * 100).round();
  final sign = neg ? '−' : (showSign ? '+' : '');
  final symbol = currencyNotifier.value;
  final base = '$sign$symbol${_grp.format(whole)}';
  final sep = symbol == '₺' ? ',' : '.';
  return cents == 0 ? base : '$base$sep${cents.toString().padLeft(2, '0')}';
}

/// Kullanıcının seçili para biriminde girdiği tutarı ("1250,5") TRY'ye çevirir.
/// Sayı değilse ya da sıfırdan büyük değilse null döner.
double? parseAmountToTry(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null || v <= 0) return null;
  return CurrencyService.convertToTry(v, currencyNotifier.value);
}

/// TRY tutarını giriş alanında gösterilecek metne çevirir (tam sayıysa küsuratsız).
String amountFieldText(double tryAmount) {
  final shown = CurrencyService.convertFromTry(tryAmount, currencyNotifier.value);
  return shown.toStringAsFixed(shown % 1 == 0 ? 0 : 2);
}

/// Sunucunun döndürdüğü hata mesajı ("Exception: " öneki olmadan).
String errorText(Object e) => e.toString().replaceFirst('Exception: ', '');

/// "YYYY-MM" ay anahtarı (API'nin month parametresi).
String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// "2026-10" -> "Ekim 2026"; null -> "Tüm aylar".
String monthLabel(String? month) {
  if (month == null) return 'Tüm aylar';
  final text =
      DateFormat('MMMM yyyy', 'tr_TR').format(DateTime.parse('$month-01'));
  return text[0].toUpperCase() + text.substring(1);
}

/// "YYYY-MM-DD" -> "Bugün" / "Dün" / "12 Haziran" (başka yılsa "12 Haziran 2025").
String dayLabel(String iso, {DateTime? now}) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return 'Bugün';
  if (diff == 1) return 'Dün';
  return DateFormat(d.year == now.year ? 'd MMMM' : 'd MMMM y', 'tr_TR').format(d);
}
