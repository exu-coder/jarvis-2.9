import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 𝐉.𝐀.𝐑.𝐕.𝐈.𝐒 HUD component set.
///
/// Angular cyan-on-black panels with cut corners, thin luminous borders and
/// serif typography — the same language as `assets/hud/uI.html`.
/// (Formerly the "Liquid Glass" set; API kept compatible.)

const Color _cyan = AppTheme.hudCyan;

/// Corner-cut panel shape, matching the HUD's `clip-path` polygons.
class HudClipper extends CustomClipper<Path> {
  const HudClipper({this.cut = 10, this.inverted = false});

  final double cut;
  final bool inverted;

  @override
  Path getClip(Size size) {
    final c = cut;
    final path = Path();
    if (!inverted) {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width - c, 0)
        ..lineTo(size.width, c)
        ..lineTo(size.width, size.height)
        ..lineTo(c, size.height)
        ..lineTo(0, size.height - c)
        ..close();
    } else {
      path
        ..moveTo(c, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height - c)
        ..lineTo(size.width - c, size.height)
        ..lineTo(0, size.height)
        ..lineTo(0, c)
        ..close();
    }
    return path;
  }

  @override
  bool shouldReclip(covariant HudClipper oldClipper) =>
      oldClipper.cut != cut || oldClipper.inverted != inverted;
}

/// HUD panel: translucent navy slab with a cut corner and cyan hairline.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final List<BoxShadow>? shadows;
  final double? width;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 2,
    this.blur = 0,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.onTap,
    this.gradient,
    this.shadows,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final line = borderColor ?? _cyan.withValues(alpha: isDark ? 0.22 : 0.4);

    final panel = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ??
            (isDark ? const Color(0xE606131F) : Colors.white.withValues(alpha: 0.92)),
        gradient: gradient,
        border: Border.all(color: line, width: borderWidth),
        boxShadow: shadows ??
            [
              BoxShadow(
                color: _cyan.withValues(alpha: isDark ? 0.06 : 0.05),
                blurRadius: 18,
                spreadRadius: 0,
              ),
            ],
      ),
      child: Padding(padding: padding, child: child),
    );

    Widget result = ClipPath(
      clipper: const HudClipper(cut: 12),
      child: panel,
    );

    // Corner ticks — the HUD's signature framing.
    result = Stack(
      children: [
        result,
        Positioned(
          top: 0,
          right: 0,
          child: CustomPaint(
            size: const Size(14, 14),
            painter: _CornerTickPainter(color: _cyan.withValues(alpha: 0.75)),
          ),
        ),
      ],
    );

    if (margin != null) {
      result = Padding(padding: margin!, child: result);
    }

    if (onTap != null) {
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: result,
      );
    }

    return result;
  }
}

class _CornerTickPainter extends CustomPainter {
  const _CornerTickPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(size.width - 12, 0), Offset(size.width, 0), paint);
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, 12),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CornerTickPainter old) => old.color != color;
}

/// Compact HUD chip / tag.
class GlassPill extends StatelessWidget {
  final Widget? icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  final bool isSelected;
  final EdgeInsetsGeometry padding;

  const GlassPill({
    super.key,
    this.icon,
    required this.label,
    this.color,
    this.onTap,
    this.isSelected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: padding,
      decoration: BoxDecoration(
        color: isSelected
            ? accent.withValues(alpha: 0.16)
            : accent.withValues(alpha: 0.04),
        border: Border.all(
          color: isSelected
              ? accent.withValues(alpha: 0.85)
              : accent.withValues(alpha: 0.25),
          width: isSelected ? 1.2 : 0.8,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 14,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.serif,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? accent : accent.withValues(alpha: 0.72),
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: child);
    }
    return child;
  }
}

/// HUD data-entry field.
class GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final int minLines;
  final int maxLines;

  const GlassTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.enabled = true,
    this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText.toUpperCase(),
          style: TextStyle(
            fontSize: 8.5,
            letterSpacing: 2.4,
            color: accent.withValues(alpha: 0.62),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF010D16).withValues(alpha: 0.9),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            enabled: enabled,
            onChanged: onChanged,
            minLines: minLines,
            maxLines: maxLines,
            cursorColor: accent,
            style: TextStyle(
              fontFamily: AppTheme.serif,
              fontSize: 13.5,
              letterSpacing: 0.6,
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                fontFamily: AppTheme.serif,
                fontSize: 12.5,
                color: accent.withValues(alpha: 0.35),
              ),
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: accent, width: 1.2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            ),
          ),
        ),
      ],
    );
  }
}

/// HUD slider row with a value read-out bracket.
class GlassSliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const GlassSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.03),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.6,
                    color: accent.withValues(alpha: 0.75),
                  ),
                ),
              ),
              Text(
                displayValue,
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  color: accent,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              activeTrackColor: accent,
              inactiveTrackColor: accent.withValues(alpha: 0.14),
              thumbColor: accent,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayColor: accent.withValues(alpha: 0.16),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// HUD switch row: label + status tag + toggle.
class GlassSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;

  const GlassSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final on = value;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: on ? 0.07 : 0.02),
        border: Border.all(
          color: accent.withValues(alpha: on ? 0.42 : 0.13),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? accent : accent.withValues(alpha: 0.28),
              boxShadow: on
                  ? [BoxShadow(color: accent.withValues(alpha: 0.8), blurRadius: 8)]
                  : null,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 14,
                        color: accent.withValues(alpha: on ? 0.95 : 0.4),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.5,
                          letterSpacing: 0.7,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                          color: on
                              ? accent
                              : accent.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.35,
                      color: accent.withValues(alpha: 0.42),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF01121A),
            activeTrackColor: accent,
            inactiveThumbColor: accent.withValues(alpha: 0.4),
            inactiveTrackColor: accent.withValues(alpha: 0.08),
            trackOutlineColor:
                WidgetStatePropertyAll(accent.withValues(alpha: 0.35)),
          ),
        ],
      ),
    );
  }
}

/// HUD backdrop — black gradient field with a faint targeting grid.
class LiquidGlassScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? drawer;
  final Widget? bottomNavigationBar;
  final bool isJarvis;

  const LiquidGlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.drawer,
    this.bottomNavigationBar,
    this.isJarvis = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      backgroundColor: AppTheme.hudInk,
      drawer: drawer,
      bottomNavigationBar: bottomNavigationBar,
      appBar: appBar,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _HudGridPainter()),
          ),
          body,
        ],
      ),
    );
  }
}

class _HudGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 44.0;
    final paint = Paint()
      ..color = _cyan.withValues(alpha: 0.045)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          _cyan.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.5, size.height * 0.1),
          radius: size.width * 0.75,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
