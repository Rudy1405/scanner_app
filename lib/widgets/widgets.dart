// Reusable components from design/DESIGN.md §3.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../theme.dart';

BoxShadow _shadow(Color c, double opacity, double y, double blur) =>
    BoxShadow(color: c.withValues(alpha: opacity), offset: Offset(0, y), blurRadius: blur);

/// Frosted glass backdrop.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    required this.color,
    this.radius = 20,
    this.blur = 16,
    this.border,
    this.shadows,
    this.padding,
  });
  final Widget child;
  final Color color;
  final double radius;
  final double blur;
  final Color? border;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color,
              borderRadius: r,
              border: border == null ? null : Border.all(color: border!),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Pressable with a light fade, no ripple.
class Tap extends StatefulWidget {
  const Tap(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.label,
      this.minSize = 0});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Spoken name for screen readers. Give one to every control without text.
  final String? label;

  /// Minimum touch target (44 for small controls); the visual stays as drawn.
  final double minSize;
  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    Widget child = AnimatedOpacity(
        opacity: down && widget.onTap != null ? 0.55 : 1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 80),
        child: widget.child);
    if (widget.minSize > 0) {
      child = ConstrainedBox(
        constraints: BoxConstraints(minWidth: widget.minSize, minHeight: widget.minSize),
        child: Center(child: child),
      );
    }
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.label,
      excludeSemantics: widget.label != null,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => down = true),
        onTapUp: (_) => setState(() => down = false),
        onTapCancel: () => setState(() => down = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: child,
      ),
    );
  }
}

enum GlassStyle { light, dark, subtle }

/// Round 40 px toolbar button.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.style = GlassStyle.light,
    this.size = 40,
    this.iconSize = 17,
    this.color,
    required this.label,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final GlassStyle style;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Widget inner;
    switch (style) {
      case GlassStyle.light:
        inner = Glass(
          radius: size / 2,
          blur: 12,
          color: const Color(0xCCFFFFFF),
          border: const Color(0xFFFFFFFF),
          shadows: [_shadow(AppColors.text, 0.08, 4, 12)],
          child: _icon(color ?? AppColors.text),
        );
      case GlassStyle.dark:
        inner = Glass(
          radius: size / 2,
          color: const Color(0x2EFFFFFF),
          border: const Color(0x33FFFFFF),
          child: _icon(color ?? const Color(0xFFFFFFFF)),
        );
      case GlassStyle.subtle:
        inner = Container(
          decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(size / 2)),
          child: _icon(color ?? const Color(0xFFFFFFFF)),
        );
    }
    return Tap(
        onTap: onTap,
        label: label,
        minSize: 48,
        child: SizedBox(width: size, height: size, child: inner));
  }

  Widget _icon(Color c) => Center(child: Icon(icon, size: iconSize, color: c));
}

/// Accent pill button.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 48,
    this.icon,
    this.iconAfter,
    this.fontSize = 16,
    this.expand = true,
    this.horizontalPadding = 20,
  });
  final String label;
  final VoidCallback? onTap;
  final double height;
  final IconData? icon;
  final IconData? iconAfter;
  final double fontSize;
  final bool expand;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tap(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          decoration: BoxDecoration(
            // accentDark, not accent: white text on #00B4D8 is only 2.5:1.
            color: AppColors.accentDark,
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: [_shadow(AppColors.accentDark, 0.35, 6, 16)],
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: const Color(0xFFFFFFFF)),
                const SizedBox(width: 8)
              ],
              Text(label, style: ts(fontSize, w600, const Color(0xFFFFFFFF))),
              if (iconAfter != null) ...[
                const SizedBox(width: 8),
                Icon(iconAfter, size: 13, color: const Color(0xFFFFFFFF))
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Grey translucent pill button (e.g. "Cancelar" in sheets).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onTap, this.height = 52});
  final String label;
  final VoidCallback onTap;
  final double height;
  @override
  Widget build(BuildContext context) => Tap(
        onTap: onTap,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AppColors.fillQuaternary, borderRadius: BorderRadius.circular(height / 2)),
          child: Text(label, style: ts(17, w600)),
        ),
      );
}

/// Big round camera button on the home screen.
class ScanFab extends StatelessWidget {
  const ScanFab({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tap(
        onTap: onTap,
        label: 'Escanear con la cámara',
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x59FFFFFF)),
            boxShadow: [_shadow(AppColors.accent, 0.4, 10, 24)],
          ),
          child: const Icon(CupertinoIcons.camera_fill, size: 30, color: Color(0xFFFFFFFF)),
        ),
      );
}

class GlassFab extends StatelessWidget {
  const GlassFab({super.key, required this.icon, required this.onTap, required this.label});
  final IconData icon;
  final VoidCallback onTap;
  final String label;
  @override
  Widget build(BuildContext context) => Tap(
        onTap: onTap,
        label: label,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Glass(
            radius: 26,
            blur: 12,
            color: const Color(0xB3FFFFFF),
            border: const Color(0xFFFFFFFF),
            shadows: [_shadow(AppColors.text, 0.12, 6, 16)],
            child: Center(child: Icon(icon, size: 17, color: AppColors.text)),
          ),
        ),
      );
}

class PrivacyPill extends StatelessWidget {
  const PrivacyPill({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration:
            BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(18)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(CupertinoIcons.lock_fill, size: 12, color: AppColors.accentDark),
          const SizedBox(width: 6),
          Flexible(
              child: Text(text,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w600, AppColors.text))),
        ]),
      );
}

class GroupedCard extends StatelessWidget {
  const GroupedCard({super.key, required this.children, this.separatorInset = 0});
  final List<Widget> children;
  final double separatorInset;
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Padding(
          padding: EdgeInsets.only(left: separatorInset),
          child: Container(height: 1, color: AppColors.separator),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [_shadow(AppColors.text, 0.05, 2, 8)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class TextChip extends StatelessWidget {
  const TextChip({super.key});
  @override
  Widget build(BuildContext context) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(6)),
        child: Text('Texto', style: ts(12, w600, AppColors.text)),
      );
}

class BarAction {
  const BarAction(this.icon, this.label, this.onTap, {this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
}

/// Floating pill with 4 actions (icon on top, label below).
class FloatingActionBar extends StatelessWidget {
  const FloatingActionBar({super.key, required this.actions, this.dark = false});
  final List<BarAction> actions;
  final bool dark;
  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 33,
      blur: 20,
      color: dark ? const Color(0xE61E2227) : const Color(0xD9FFFFFF),
      border: dark ? const Color(0x1AFFFFFF) : const Color(0xFFFFFFFF),
      shadows: [_shadow(AppColors.text, 0.12, 8, 24)],
      child: SizedBox(
        height: 66,
        child: Row(children: [
          for (final a in actions)
            Expanded(
              child: Tap(
                onTap: a.onTap,
                label: a.label,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(a.icon,
                      size: 20,
                      color: a.color ?? (dark ? const Color(0xFFFFFFFF) : AppColors.accentDark)),
                  const SizedBox(height: 4),
                  Text(a.label,
                      style: ts(
                          12,
                          dark ? w400 : w600,
                          a.color ?? (dark ? const Color(0xCCFFFFFF) : AppColors.text))),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

/// App logo tile.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 30});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            gradient: AppColors.logoGradient, borderRadius: BorderRadius.circular(size * 0.27)),
        child: Icon(CupertinoIcons.doc_text_viewfinder,
            color: const Color(0xFFFFFFFF), size: size * 0.55),
      );
}

/// Large iOS-style title block with optional leading and trailing buttons.
class LargeHeader extends StatelessWidget {
  const LargeHeader({super.key, required this.title, this.leading, this.trailing = const []});
  final String title;
  final Widget? leading;
  final List<Widget> trailing;
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 8, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 44,
          child: Row(children: [
            if (leading != null) leading!,
            const Spacer(),
            for (var i = 0; i < trailing.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              trailing[i],
            ],
          ]),
        ),
        const SizedBox(height: 8),
        Text(title, style: ts(34, w700)),
      ]),
    );
  }
}

/// iOS back link: chevron + label.
class BackLink extends StatelessWidget {
  const BackLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tap(
        onTap: onTap,
        minSize: 44,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(CupertinoIcons.chevron_left, size: 20, color: AppColors.accentDark),
          const SizedBox(width: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(17, w400, AppColors.accentDark)),
          ),
        ]),
      );
}

/// Modal sheet scrim colour helper.
Color scrim(double opacity) => AppColors.scrim.withValues(alpha: opacity);

/// Progress card (screen 16). Use through [showHud].
class HudCard extends StatelessWidget {
  const HudCard({super.key, required this.text, this.subtitle, this.progress});
  final String text;
  final String? subtitle;
  final double? progress;
  @override
  Widget build(BuildContext context) => Glass(
        radius: 28,
        blur: 30,
        color: const Color(0xEBFFFFFF),
        shadows: [_shadow(const Color(0xFF000000), 0.18, 16, 40)],
        child: SizedBox(
          width: 190,
          height: 157,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 52, height: 52, child: _Ring(progress: progress)),
            const SizedBox(height: 14),
            Text(text, style: ts(17, w600), textAlign: TextAlign.center),
            if (subtitle case final sub?) ...[
              const SizedBox(height: 3),
              Text(sub, style: ts(13, w400, AppColors.muted)),
            ],
          ]),
        ),
      );
}

class _Ring extends StatefulWidget {
  const _Ring({this.progress});
  final double? progress;
  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce-motion: a still arc instead of a looping spinner.
    if (MediaQuery.disableAnimationsOf(context)) {
      c.stop();
    } else if (!c.isAnimating) {
      c.repeat();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        builder: (_, _) => CustomPaint(painter: _RingPainter(widget.progress, c.value)),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.t);
  final double? progress;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final deflated = rect.deflate(2);
    canvas.drawArc(
        deflated,
        0,
        6.2832,
        false,
        Paint()
          ..color = AppColors.accentTint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);
    final paint = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if (progress == null) {
      canvas.drawArc(deflated, t * 6.2832 - 1.5708, 1.9, false, paint);
    } else {
      canvas.drawArc(deflated, -1.5708, 6.2832 * progress!.clamp(0.02, 1.0), false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t || old.progress != progress;
}

/// Small toast, e.g. "Copiado".
void showToast(BuildContext context, String text) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.paddingOf(ctx).bottom + 90,
      child: IgnorePointer(
        child: Center(
          child: Glass(
            radius: 18,
            blur: 20,
            color: const Color(0xCC1E2227),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(text, style: ts(14, w600, const Color(0xFFFFFFFF))),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Timer(const Duration(milliseconds: 1600), entry.remove);
}

/// Section header above a grouped card (UPPERCASE, accent).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.color = AppColors.accentDark});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(36, 22, 20, 8),
        child: Text(text.toUpperCase(), style: ts(12, w600, color)),
      );
}
