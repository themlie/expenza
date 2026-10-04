// Ortak biçimlendirme ve tutar girdisi kuralları (format.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:expenza_mobile/format.dart';
import 'package:expenza_mobile/theme.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  tearDown(() => currencyNotifier.value = '₺');

  test('tutar girdisi TRY\'ye çevrilir; geçersiz ya da sıfır null döner', () {
    expect(parseAmountToTry('1250,5'), 1250.5);
    expect(parseAmountToTry(' 99.90 '), 99.9);
    for (final bad in ['', 'abc', '0', '-5']) {
      expect(parseAmountToTry(bad), isNull, reason: bad);
    }
    currencyNotifier.value = '\$';
    final rate = CurrencyService.rates['\$']!;
    expect(parseAmountToTry('10'), closeTo(10 / rate, 1e-9));
  });

  test('alan metni seçili para biriminde, tam sayıysa küsuratsız', () {
    expect(amountFieldText(1500), '1500');
    expect(amountFieldText(12.5), '12.50');
    currencyNotifier.value = '\$';
    final rate = CurrencyService.rates['\$']!;
    expect(amountFieldText(100 / rate), '100');
  });

  test('para gösterimi binlik ayraç ve işaret kullanır', () {
    expect(money(12500), '₺12.500');
    expect(money(-3.5), '−₺3,50');
    expect(money(40, showSign: true), '+₺40');
  });

  test('gün ve ay etiketleri', () {
    final now = DateTime(2026, 10, 4);
    expect(dayLabel('2026-10-04', now: now), 'Bugün');
    expect(dayLabel('2026-10-03', now: now), 'Dün');
    expect(dayLabel('2026-06-12', now: now), '12 Haziran');
    expect(dayLabel('2025-06-12', now: now), '12 Haziran 2025');
    expect(monthKey(DateTime(2026, 3, 9)), '2026-03');
    expect(monthLabel('2026-10'), 'Ekim 2026');
    expect(monthLabel(null), 'Tüm aylar');
  });

  test('hata metni öneksiz', () {
    expect(errorText(Exception('Hedefte bu kadar birikim yok')),
        'Hedefte bu kadar birikim yok');
  });
}
