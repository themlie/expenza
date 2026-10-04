import 'package:flutter/material.dart';

import '../api_client.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';

/// Ekrandaki para birimi simgesinin backend'deki kodu.
const _currencyCodes = {'₺': 'TRY', '\$': 'USD', '€': 'EUR', '£': 'GBP'};

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

const _greeting =
    "Merhaba! Ben Expenza Yapay Zekâ Asistanınız. Harcamalarınız, bütçe limitleriniz ve tasarruf hedeflerinizle ilgili sorularınızı yanıtlayabilirim. Nasıl yardımcı olabilirim?";

class _ChatScreenState extends State<ChatScreen> {
  // Ekran kapanıp açılınca konuşma kaldığı yerden devam eder (ApiClient.chatLog).
  // Hata mesajları yalnızca ekranda görünür, asistana geri gönderilmez.
  final List<ChatTurn> _messages = [
    ChatTurn(fromUser: false, text: _greeting),
    ...ApiClient.instance.chatLog,
  ];

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;

  // Veri paylaşımı onayı: null = yükleniyor.
  bool? _consent;
  bool _savingConsent = false;

  @override
  void initState() {
    super.initState();
    ApiClient.instance
        .hasAiConsent()
        .then((v) {
          if (mounted) setState(() => _consent = v);
        })
        .catchError((_) {
          if (mounted) setState(() => _consent = false);
        });
  }

  Future<void> _giveConsent() async {
    setState(() => _savingConsent = true);
    try {
      await ApiClient.instance.setAiConsent(true);
      if (mounted) setState(() => _consent = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorText(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _savingConsent = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    setState(() {
      _messages.add(ChatTurn(fromUser: true, text: text));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final symbol = currencyNotifier.value;
      final reply = await ApiClient.instance.sendChatMessage(
        text,
        currency: _currencyCodes[symbol] ?? 'TRY',
        rate: CurrencyService.rates[symbol] ?? 1,
      );
      if (mounted) {
        setState(() {
          _messages.add(ChatTurn(fromUser: false, text: reply));
        });
      }
    } catch (e) {
      // Backend kullanıcıya gösterilebilir, genel bir mesaj döndürür.
      final detail = errorText(e);
      if (mounted) {
        setState(() {
          _messages.add(
            ChatTurn(
              fromUser: false,
              text: detail.isNotEmpty
                  ? detail
                  : "Üzgünüm, asistan servisine bağlanırken bir hata oluştu. Lütfen tekrar deneyin.",
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _scrollToBottom();
    }
  }

  void _newChat() {
    ApiClient.instance.chatLog.clear();
    setState(() {
      _messages
        ..clear()
        ..add(ChatTurn(fromUser: false, text: _greeting));
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: AppColors.onSurface, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.psychology, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Text(
              "Expenza AI",
              style: TextStyle(
                color: AppColors.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 19,
              ),
            ),
          ],
        ),
        actions: [
          if (_consent == true && _messages.length > 1)
            IconButton(
              tooltip: 'Yeni sohbet',
              icon: Icon(Icons.add_comment_outlined,
                  color: AppColors.onSurfaceVariant),
              onPressed: _isLoading ? null : _newChat,
            ),
        ],
        shape: Border(bottom: BorderSide(color: AppColors.glassBorder)),
      ),
      body: _consent == null
          ? Center(child: CircularProgressIndicator(color: AppColors.outline))
          : _consent == false
          ? _consentPanel()
          : _chatBody(isDark),
    );
  }

  /// Aydınlatma metni ve açık rıza: onay verilmeden hiçbir veri gönderilmez.
  Widget _consentPanel() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      children: [
        Icon(Icons.privacy_tip_outlined, size: 40, color: AppColors.primary),
        const SizedBox(height: 16),
        Text('Veri paylaşımı onayı', style: AppText.display(size: 30)),
        const SizedBox(height: 12),
        Text(
          'Expenza AI sorularını yanıtlarken Google Gemini hizmetini kullanır. '
          'Bunun için her soruda son 30 işlemin (tutar, kategori, tarih ve not), '
          'bütçe limitlerin, tasarruf hedeflerin ve bu sohbetteki önceki '
          'mesajların Google\'a gönderilir. Sohbet cihaza ya da sunucuya '
          'kaydedilmez. '
          'Adın ve e-posta adresin gönderilmez.\n\n'
          'Onayını istediğin zaman Profil > Ayarlar bölümünden geri çekebilirsin.',
          style: TextStyle(
            fontSize: 16,
            height: 1.55,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _savingConsent ? null : _giveConsent,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          child: Text(_savingConsent ? 'Kaydediliyor…' : 'Onaylıyorum'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Vazgeç',
            style: TextStyle(color: AppColors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _chatBody(bool isDark) {
    return Column(
      children: [
        // Mesaj listesi
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            itemCount: _messages.length,
            itemBuilder: (context, idx) {
              final msg = _messages[idx];
              // Yalnızca son mesaj belirerek gelir; kaydırınca eskiler yeniden oynamaz.
              return idx == _messages.length - 1
                  ? Rise(key: ValueKey(idx), child: _chatBubble(msg))
                  : _chatBubble(msg);
            },
          ),
        ),

        if (_isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  PingDot(color: AppColors.primary, size: 6),
                  const SizedBox(width: 10),
                  Text(
                    "Asistan yanıt yazıyor",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Alt mesaj çubuğu
        _bottomBar(isDark),
      ],
    );
  }

  Widget _chatBubble(ChatTurn msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: msg.fromUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: msg.fromUser ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(msg.fromUser ? 22 : 6),
              bottomRight: Radius.circular(msg.fromUser ? 6 : 22),
            ),
            border: msg.fromUser
                ? null
                : Border.all(color: AppColors.glassBorder),
          ),
          child: Text(
            msg.text,
            style: TextStyle(
              color: msg.fromUser ? AppColors.onPrimary : AppColors.onSurface,
              fontSize: 16,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.glassBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceBright,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.glassBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _textController,
                style: TextStyle(color: AppColors.onSurface, fontSize: 17),
                decoration: InputDecoration(
                  hintText: "Asistana sor…",
                  hintStyle: TextStyle(color: AppColors.outline, fontSize: 17),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                maxLines: null,
                keyboardType: TextInputType.multiline,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Press(
            onTap: _sendMessage,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send_rounded,
                color: AppColors.onPrimary,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
