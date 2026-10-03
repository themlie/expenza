// Açılış ve giriş ekranı widget testleri.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expenza_mobile/api_client.dart';
import 'package:expenza_mobile/main.dart';
import 'package:expenza_mobile/wordmark.dart';

void main() {
  // Testlerde kayıtlı oturum aranmaz; doğrudan giriş ekranı açılır.
  setUp(() => ApiClient.instance.restoring.value = false);

  testWidgets('Oturum geri yüklenirken açılış ekranı görünür',
      (WidgetTester tester) async {
    ApiClient.instance.restoring.value = true;
    await tester.pumpWidget(const ExpenzaApp());
    await tester.pump();

    expect(find.byType(ExpenzaWordmark), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    ApiClient.instance.restoring.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('Açılışta giriş ekranı görünür', (WidgetTester tester) async {
    await tester.pumpWidget(const ExpenzaApp());
    await tester.pumpAndSettle();

    expect(find.byType(ExpenzaWordmark), findsOneWidget);
    // "Giriş yap" hem üstteki sekmede hem gönder butonunda yazar.
    expect(find.text('Giriş yap'), findsNWidgets(2));
    expect(find.byType(TextField), findsNWidgets(2)); // e-posta ve parola
    expect(find.text('AD SOYAD'), findsNothing);
  });

  testWidgets('Kayıt sekmesi ad alanını açar', (WidgetTester tester) async {
    await tester.pumpWidget(const ExpenzaApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kayıt ol').first);
    await tester.pumpAndSettle();

    expect(find.text('AD SOYAD'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(find.text('Şifremi unuttum'), findsNothing);
  });
}
