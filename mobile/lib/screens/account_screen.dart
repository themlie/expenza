import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';

/// Hesap ayarları: ad, şifre değiştirme ve hesabı silme.
/// Şifre değişince diğer cihazlardaki oturumlar kapanır, bu cihaz açık kalır.
/// Hesap silinince bütün veriler silinir ve giriş ekranına dönülür.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late Future<UserModel> _future;
  final _name = TextEditingController();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _repeat = TextEditingController();

  bool _savingName = false;
  bool _savingPassword = false;
  String? _nameError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.getProfile().then((u) {
      _name.text = u.displayName;
      return u;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _current, _new, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _toast(String text) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(text)));

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Ad boş olamaz.');
      return;
    }
    setState(() {
      _savingName = true;
      _nameError = null;
    });
    try {
      await ApiClient.instance.updateProfile(displayName: name);
      if (mounted) _toast('Adın güncellendi.');
    } catch (e) {
      if (mounted) setState(() => _nameError = _msg(e));
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _changePassword() async {
    if (_current.text.isEmpty || _new.text.isEmpty) {
      setState(() => _passwordError = 'Mevcut ve yeni şifreyi gir.');
      return;
    }
    if (_new.text != _repeat.text) {
      setState(() => _passwordError = 'Yeni şifreler aynı değil.');
      return;
    }
    setState(() {
      _savingPassword = true;
      _passwordError = null;
    });
    try {
      await ApiClient.instance.changePassword(_current.text, _new.text);
      for (final c in [_current, _new, _repeat]) {
        c.clear();
      }
      if (mounted) {
        _toast('Şifren değişti. Diğer cihazlardaki oturumlar kapatıldı.');
      }
    } catch (e) {
      if (mounted) setState(() => _passwordError = _msg(e));
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _deleteAccount() async {
    final pass = TextEditingController();
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Hesabı sil',
              style: TextStyle(color: AppColors.onSurface)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Bütün işlemlerin, bütçelerin ve hedeflerin kalıcı olarak '
                  'silinecek. Bu işlem geri alınamaz. Onaylamak için şifreni gir.',
                  style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 16),
              _field(pass, 'Şifre', obscure: true),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style: TextStyle(fontSize: 14, color: AppColors.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (pass.text.isEmpty) {
                        setDialog(() => error = 'Şifreni gir.');
                        return;
                      }
                      setDialog(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        // Başarılı olunca oturum kapanır; açık sayfalar
                        // (bu pencere dahil) kapanıp giriş ekranı açılır.
                        await ApiClient.instance.deleteAccount(pass.text);
                      } catch (e) {
                        setDialog(() {
                          busy = false;
                          error = _msg(e);
                        });
                      }
                    },
              child: Text('Hesabımı sil',
                  style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<UserModel>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (snap.hasError) {
            return LoadError(
                error: snap.error!,
                onRetry: () => setState(() {
                      _future = ApiClient.instance.getProfile().then((u) {
                        _name.text = u.displayName;
                        return u;
                      });
                    }));
          }
          final user = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 40),
            children: [
              _header(),
              const SizedBox(height: 28),
              Rise(child: _nameCard(user)),
              const SizedBox(height: 16),
              Rise(delayMs: 60, child: _passwordCard()),
              const SizedBox(height: 16),
              Rise(delayMs: 120, child: _deleteCard()),
            ],
          );
        },
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Press(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Icon(Icons.chevron_left, size: 22, color: AppColors.onSurface),
          ),
        ),
        const SizedBox(width: 14),
        Text('Hesap ayarları',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.3,
                color: AppColors.onSurface)),
      ],
    );
  }

  Widget _nameCard(UserModel user) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Profil'),
          const SizedBox(height: 14),
          _field(_name, 'Ad soyad'),
          const SizedBox(height: 10),
          Text(user.email,
              style: TextStyle(fontSize: 14, color: AppColors.onSurfaceVariant)),
          _errorText(_nameError),
          const SizedBox(height: 16),
          _button(_savingName ? 'Kaydediliyor…' : 'Adı kaydet',
              _savingName ? null : _saveName),
        ],
      ),
    );
  }

  Widget _passwordCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Şifre'),
          const SizedBox(height: 14),
          _field(_current, 'Mevcut şifre', obscure: true),
          const SizedBox(height: 10),
          _field(_new, 'Yeni şifre', obscure: true),
          const SizedBox(height: 10),
          _field(_repeat, 'Yeni şifre (tekrar)', obscure: true),
          const SizedBox(height: 10),
          Text('En az 8 karakter, en az bir harf ve bir rakam.',
              style: TextStyle(fontSize: 13, color: AppColors.outline)),
          _errorText(_passwordError),
          const SizedBox(height: 16),
          _button(_savingPassword ? 'Değiştiriliyor…' : 'Şifreyi değiştir',
              _savingPassword ? null : _changePassword),
        ],
      ),
    );
  }

  Widget _deleteCard() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Tehlikeli bölge', color: AppColors.error),
          const SizedBox(height: 10),
          Text('Hesabını ve bütün verilerini kalıcı olarak siler.',
              style: TextStyle(
                  fontSize: 15, height: 1.4, color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 16),
          Press(
            onTap: _deleteAccount,
            child: Container(
              width: double.infinity,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.error),
              ),
              child: Text('Hesabı sil',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.error)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorText(String? message) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(message,
              style: TextStyle(fontSize: 14, color: AppColors.error)),
        );

  Widget _button(String label, VoidCallback? onTap) => Press(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onPrimary)),
        ),
      );

  Widget _field(TextEditingController c, String hint, {bool obscure = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceBright,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: TextField(
        controller: c,
        obscureText: obscure,
        style: TextStyle(fontSize: 16, color: AppColors.onSurface),
        decoration: InputDecoration(
          isCollapsed: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.outline, fontSize: 16),
        ),
      ),
    );
  }
}
