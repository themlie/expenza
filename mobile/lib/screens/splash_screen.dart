import 'package:flutter/material.dart';

import '../theme.dart';
import '../wordmark.dart';

/// Açılış ekranı: kayıtlı oturum geri yüklenirken (ApiClient.restoreSession) gösterilir.
/// Wordmark kendini çizer, altında ince bir yükleme çizgisi akar.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExpenzaWordmark(height: 30, strokeWidth: 1.8, animate: true),
            const SizedBox(height: 32),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
