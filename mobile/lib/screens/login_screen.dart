import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../wordmark.dart';

/// Giriş + kayıt ekranı. Web sitesindeki dil: kendini çizen wordmark, ince büyük
/// başlık, hap şeklinde segment ve buton, bej üstünde açık input'lar.
class LoginScreen extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Demo hesabı (seed_demo.py) yalnızca geliştirme derlemesinde önceden doldurulur;
  // release derlemesinde bu değerler koda girmez.
  final _email = TextEditingController(text: kDebugMode ? 'test@expenza.com' : '');
  final _pass = TextEditingController(text: kDebugMode ? 'secret1' : '');
  final _name = TextEditingController();
  bool _isRegister = false;
  bool _busy = false;
  bool _obscure = true;
  // Kapalıysa oturum cihaza kaydedilmez; uygulama kapanınca tekrar giriş gerekir.
  bool _remember = true;
  // Sunucu oturumu düşürdüyse (401) giriş ekranı nedenini gösterir.
  String? _error = ApiClient.instance.sessionEndedReason;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ApiClient.instance;
      if (_isRegister) {
        await api.register(_email.text.trim(), _pass.text, _name.text.trim());
      }
      await api.login(_email.text.trim(), _pass.text, remember: _remember);
      widget.onLoggedIn();
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst satır: wordmark + tema düğmesi
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const ExpenzaWordmark(height: 20, animate: true),
                  Press(
                    onTap: () => setState(toggleThemeMode),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.glassBorder),
                      ),
                      child: Icon(
                          isDark
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined,
                          size: 18,
                          color: AppColors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Başlık
              Rise(
                delayMs: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Kişisel finans takibi'),
                    const SizedBox(height: 14),
                    Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Harcamanı yaz,\ngerisi '),
                        TextSpan(
                            text: "Expenza'da.",
                            style: TextStyle(color: AppColors.primary)),
                      ]),
                      style: AppText.display(size: 38),
                    ),
                    const SizedBox(height: 14),
                    Text(
                        _isRegister
                            ? 'Birkaç saniyede hesabını oluştur.'
                            : 'Hesabına giriş yap, paranı kontrol et.',
                        style: TextStyle(
                            fontSize: 17, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Segment kontrolü
              Rise(delayMs: 200, child: _segmented()),
              const SizedBox(height: 28),

              // Form
              Rise(
                delayMs: 280,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isRegister) ...[
                      _field('Ad soyad', _name, Icons.person_outline,
                          hint: 'Defne Kaya'),
                      const SizedBox(height: 18),
                    ],
                    _field('E-posta', _email, Icons.mail_outline,
                        hint: 'defne@ornek.com',
                        keyboard: TextInputType.emailAddress),
                    const SizedBox(height: 18),
                    _passwordField(),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline,
                              size: 18, color: AppColors.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: TextStyle(
                                    color: AppColors.error, fontSize: 15)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    _rememberRow(),
                    const SizedBox(height: 18),
                    _submitButton(),
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 16, color: AppColors.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Banka hesabına bağlanmaz. Şifre ya da kart bilgisi istemez.',
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: AppColors.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Alt geçiş (büyük yazı boyutunda taşmasın diye Wrap)
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                        _isRegister
                            ? 'Zaten hesabın var mı?'
                            : 'Hesabın yok mu?',
                        style: TextStyle(
                            fontSize: 15, color: AppColors.onSurfaceVariant)),
                    Press(
                      onTap: () => setState(() => _isRegister = !_isRegister),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
                        child: Text(_isRegister ? 'Giriş yap' : 'Kayıt ol',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmented() {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment:
                _isRegister ? Alignment.centerRight : Alignment.centerLeft,
            duration: AppMotion.medium,
            curve: AppMotion.curve,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _segTab('Giriş yap', !_isRegister,
                  () => setState(() => _isRegister = false)),
              _segTab('Kayıt ol', _isRegister,
                  () => setState(() => _isRegister = true)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segTab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: AppMotion.fast,
            style: TextStyle(
                fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: active ? AppColors.onPrimary : AppColors.onSurfaceVariant),
            child: Text(label),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c, IconData icon,
      {String? hint, TextInputType? keyboard}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 10),
        _fieldBox(
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.outline),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: c,
                  keyboardType: keyboard,
                  style: TextStyle(fontSize: 17, color: AppColors.onSurface),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: hint,
                    hintStyle:
                        TextStyle(color: AppColors.outline, fontSize: 17),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _passwordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // E-postayla şifre sıfırlama yok (e-posta altyapısı gerektirir); şifre
        // giriş yaptıktan sonra Profil > Hesap ayarları'ndan değiştirilir.
        const Eyebrow('Parola'),
        const SizedBox(height: 10),
        _fieldBox(
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: AppColors.outline),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _pass,
                  obscureText: _obscure,
                  style: TextStyle(fontSize: 17, color: AppColors.onSurface),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '••••••••',
                    hintStyle:
                        TextStyle(color: AppColors.outline, fontSize: 17),
                  ),
                ),
              ),
              Press(
                onTap: () => setState(() => _obscure = !_obscure),
                child: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: AppColors.outline),
              ),
            ],
          ),
        ),
        if (_isRegister) ...[
          const SizedBox(height: 8),
          Text('En az 8 karakter; en az bir harf ve bir rakam.',
              style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
        ],
      ],
    );
  }

  Widget _fieldBox({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceBright,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: child,
    );
  }

  Widget _rememberRow() {
    return Press(
      onTap: () => setState(() => _remember = !_remember),
      child: Row(
        children: [
          AnimatedContainer(
            duration: AppMotion.fast,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _remember ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: _remember ? AppColors.primary : AppColors.outline,
                  width: 1.5),
            ),
            child: _remember
                ? Icon(Icons.check, size: 14, color: AppColors.onPrimary)
                : null,
          ),
          const SizedBox(width: 10),
          Text('Beni hatırla',
              style: TextStyle(fontSize: 15, color: AppColors.onSurface)),
        ],
      ),
    );
  }

  Widget _submitButton() {
    return Press(
      onTap: _busy ? null : _submit,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Center(
          child: _busy
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.onPrimary))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isRegister ? 'Hesap oluştur' : 'Giriş yap',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.onPrimary)),
                    const SizedBox(width: 10),
                    Icon(Icons.arrow_forward,
                        size: 18, color: AppColors.onPrimary),
                  ],
                ),
        ),
      ),
    );
  }
}
