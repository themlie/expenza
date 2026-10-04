import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// Başlıklardaki ince çerçeveli yuvarlak ikon düğmesi (tema, bildirim, geri...).
/// [onTap] null ise düğme soluk görünür ve dokunulmaz.
class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double iconSize;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.iconSize = 19,
  });

  @override
  Widget build(BuildContext context) {
    final button = Press(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.glassBorder)),
        child: Icon(icon,
            size: iconSize,
            color: onTap == null ? AppColors.outline : AppColors.onSurface),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
