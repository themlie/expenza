// Hedef ekranının alt sayfaları: hedef formu (yeni/düzenle), para ekleme ve çekme.
// Kaydedince [onSaved] çağrılır; ekran listeyi yeniler.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api_client.dart';
import '../currency.dart';
import '../format.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

Widget _errorLine(String? message) => message == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(message,
            style: TextStyle(fontSize: 14, color: AppColors.error)),
      );

// ---- Alt sayfa kabuğu ----
Future<void> _sheet(
    BuildContext context, Widget Function(BuildContext, StateSetter) builder) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: AppColors.glassBorder),
          ),
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.pill)),
                ),
              ),
              builder(ctx, setSheet),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _sheetTitle(BuildContext ctx, String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.4,
                  color: AppColors.onSurface)),
        ),
        const SizedBox(width: 12),
        Press(
          onTap: () => Navigator.pop(ctx),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassBorder)),
            child:
                Icon(Icons.close, size: 20, color: AppColors.onSurfaceVariant),
          ),
        ),
      ],
    ),
  );
}

Widget _fieldLabel(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Eyebrow(t, size: 11),
    );

Widget _inputBox({required Widget child}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceBright,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: child,
    );

const _bare = InputDecoration(
  isCollapsed: true,
  filled: false,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
);

Widget _primaryButton(String label, VoidCallback onTap) => Press(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 54,
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

/// Yeni hedef ya da [editing] verilirse düzenleme. Son tarih isteğe bağlı.
Future<void> showGoalForm(BuildContext context,
    {GoalModel? editing, required VoidCallback onSaved}) async {
  final nameCtrl = TextEditingController(text: editing?.title ?? '');
  final targetCtrl = TextEditingController(
      text: editing == null ? '' : amountFieldText(editing.targetAmount));
  DateTime? deadline =
      editing?.deadline == null ? null : DateTime.parse(editing!.deadline!);
  String? error;
  var busy = false;

  await _sheet(context, (ctx, setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sheetTitle(ctx, editing == null ? 'Yeni hedef' : 'Hedefi düzenle'),
          _fieldLabel('Hedef adı'),
          _inputBox(
            child: TextField(
              controller: nameCtrl,
              style: TextStyle(fontSize: 17, color: AppColors.onSurface),
              decoration: _bare.copyWith(
                  hintText: 'örn. Yeni telefon',
                  hintStyle:
                      TextStyle(color: AppColors.outline, fontSize: 17)),
            ),
          ),
          const SizedBox(height: 20),
          _fieldLabel('Hedef tutar (${currencyNotifier.value})'),
          _inputBox(
            child: Row(
              children: [
                Text(currencyNotifier.value,
                    style: AppText.mono(
                        size: 18, color: AppColors.onSurfaceVariant)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: targetCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppText.mono(size: 18),
                    decoration: _bare.copyWith(hintText: '0'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _fieldLabel('Son tarih (isteğe bağlı)'),
          Press(
            onTap: () async {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final initial = deadline != null && !deadline!.isBefore(today)
                  ? deadline!
                  : DateTime(today.year, today.month + 6, today.day);
              final picked = await showDatePicker(
                context: ctx,
                initialDate: initial,
                firstDate: today,
                lastDate: DateTime(today.year + 30),
                helpText: 'Hedefin son tarihi',
                cancelText: 'Vazgeç',
                confirmText: 'Seç',
              );
              if (picked != null) setSheet(() => deadline = picked);
            },
            child: _inputBox(
              child: Row(
                children: [
                  Icon(Icons.event_outlined,
                      size: 19, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        deadline == null
                            ? 'Tarih seç'
                            : DateFormat('d MMMM y', 'tr_TR').format(deadline!),
                        style: TextStyle(
                            fontSize: 17,
                            color: deadline == null
                                ? AppColors.outline
                                : AppColors.onSurface)),
                  ),
                  if (deadline != null)
                    Press(
                      onTap: () => setSheet(() => deadline = null),
                      child: Icon(Icons.cancel,
                          size: 18, color: AppColors.outline),
                    ),
                ],
              ),
            ),
          ),
          _errorLine(error),
          const SizedBox(height: 26),
          _primaryButton(
              busy
                  ? 'Kaydediliyor…'
                  : (editing == null ? 'Hedef oluştur' : 'Kaydet'), () async {
            if (busy) return;
            final name = nameCtrl.text.trim();
            final target = parseAmountToTry(targetCtrl.text);
            if (name.isEmpty || target == null) {
              setSheet(() => error = 'Hedef adı ve tutarı gir.');
              return;
            }
            final iso = deadline == null
                ? null
                : DateFormat('yyyy-MM-dd').format(deadline!);
            setSheet(() {
              busy = true;
              error = null;
            });
            try {
              if (editing == null) {
                await ApiClient.instance.createGoal(name, target, deadline: iso);
              } else {
                await ApiClient.instance.updateGoal(editing.id,
                    title: name,
                    targetAmount: target,
                    deadline: iso,
                    clearDeadline: iso == null && editing.deadline != null);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              onSaved();
            } catch (e) {
              setSheet(() {
                busy = false;
                error = errorText(e);
              });
            }
          }),
        ],
      ));
}

/// Hedefte biriken paradan geri alma.
Future<void> showGoalWithdraw(BuildContext context, GoalModel g,
    {required VoidCallback onSaved}) async {
  final amtCtrl = TextEditingController();
  String? error;
  await _sheet(context, (ctx, setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sheetTitle(ctx, '${g.title}: para çek'),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text('Birikim ${money(g.currentAmount)}',
                style: AppText.mono(
                    size: 14, color: AppColors.onSurfaceVariant)),
          ),
          _fieldLabel('Tutar (${currencyNotifier.value})'),
          _inputBox(
            child: Row(
              children: [
                Text(currencyNotifier.value,
                    style: AppText.mono(
                        size: 18, color: AppColors.onSurfaceVariant)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: amtCtrl,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: AppText.mono(size: 18),
                    decoration: _bare.copyWith(hintText: '0'),
                  ),
                ),
              ],
            ),
          ),
          _errorLine(error),
          const SizedBox(height: 26),
          _primaryButton('Çek', () async {
            final amount = parseAmountToTry(amtCtrl.text);
            if (amount == null) {
              setSheet(() => error = 'Tutar gir.');
              return;
            }
            try {
              await ApiClient.instance.withdrawGoal(g.id, amount);
              if (ctx.mounted) Navigator.pop(ctx);
              onSaved();
            } catch (e) {
              setSheet(() => error = errorText(e));
            }
          }),
        ],
      ));
}

Future<void> showGoalContribute(BuildContext context, GoalModel g,
    {required VoidCallback onSaved}) async {
  final amtCtrl = TextEditingController();
  final rate = CurrencyService.rates[currencyNotifier.value] ?? 1.0;
  final remain = g.remaining * rate;
  final quick = [500.0, 1000.0, 2500.0]
      .map((q) => q * rate)
      .where((q) => q <= remain)
      .toList();
  if (remain > 0 && !quick.contains(remain)) quick.add(remain);

  await _sheet(context, (ctx, setSheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sheetTitle(ctx, '${g.title}: katkı ekle'),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
                'Kalan ${money(g.remaining)} · Hedef ${money(g.targetAmount)}',
                style: AppText.mono(
                    size: 14, color: AppColors.onSurfaceVariant)),
          ),
          _fieldLabel('Tutar (${currencyNotifier.value})'),
          _inputBox(
            child: Row(
              children: [
                Text(currencyNotifier.value,
                    style: AppText.mono(
                        size: 18, color: AppColors.onSurfaceVariant)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: amtCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    style: AppText.mono(size: 18),
                    decoration: _bare.copyWith(hintText: '0'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: quick
                .map((q) => Press(
                      onTap: () =>
                          setSheet(() => amtCtrl.text = q.toStringAsFixed(0)),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: AppColors.glassBorder)),
                        child: Text(
                            '+${currencyNotifier.value}${q.toStringAsFixed(0)}',
                            style: AppText.mono(size: 14)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 26),
          _primaryButton('Ekle', () async {
            final amount = parseAmountToTry(amtCtrl.text);
            if (amount == null) return;
            await ApiClient.instance.contributeGoal(g.id, amount);
            if (ctx.mounted) Navigator.pop(ctx);
            onSaved();
          }),
        ],
      ));
}
