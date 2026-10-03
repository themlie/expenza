import 'package:flutter/material.dart';

import '../theme.dart';

/// Açılış ekranı: kayıtlı oturum geri yüklenirken (ApiClient.restoreSession) gösterilir.
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
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.account_balance_wallet,
                  color: AppColors.onPrimary, size: 30),
            ),
            const SizedBox(height: 20),
            Text('Expenza',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.onSurface)),
            const SizedBox(height: 28),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
