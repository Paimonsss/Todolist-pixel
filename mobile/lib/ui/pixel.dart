import 'dart:math';

import 'package:flutter/material.dart';

class Px {
  static const ink = Color(0xFF1D1A4A);
  static const muted = Color(0xFF5D5890);
  static const paper = Color(0xFFFFFBF0);
  static const bg = Color(0xFFF4F1FF);
  static const grid = Color(0xFFE6E1FF);
  static const lav = Color(0xFFB9B0FF);
  static const violet = Color(0xFF7C6EE6);
  static const yellow = Color(0xFFFFD166);
  static const green = Color(0xFF2EC482);
  static const red = Color(0xFFEF476F);
  static const darkRed = Color(0xFFB3123D);

  static const body = TextStyle(
    fontFamily: 'VT323',
    fontSize: 21,
    height: 1.15,
    color: ink,
  );
  static const note = TextStyle(
    fontFamily: 'VT323',
    fontSize: 19,
    height: 1.15,
    color: muted,
  );
  static const display = TextStyle(
    fontFamily: 'PressStart',
    fontSize: 12,
    height: 1.4,
    color: ink,
  );
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.fill, this.border, this.shadow, this.drop);
  final Color fill, border, shadow;
  final double drop;

  void _notched(Canvas c, Rect r, double n, Color color) {
    final p = Paint()..color = color;
    c.drawRect(Rect.fromLTRB(r.left + n, r.top, r.right - n, r.bottom), p);
    c.drawRect(Rect.fromLTRB(r.left, r.top + n, r.right, r.bottom - n), p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final box = Rect.fromLTWH(0, 0, size.width - 6, size.height - 6);
    if (drop > 0) _notched(canvas, box.shift(Offset(drop, drop)), 3, shadow);
    _notched(canvas, box, 3, border);
    _notched(canvas, box.deflate(3), 0, fill);
  }

  @override
  bool shouldRepaint(_FramePainter o) =>
      o.fill != fill ||
      o.border != border ||
      o.shadow != shadow ||
      o.drop != drop;
}

class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.border = Px.ink,
    this.shadow = Px.lav,
    this.fill = Px.paper,
  });
  final Widget child;
  final Color border, shadow, fill;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _FramePainter(fill, border, shadow, 6),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 22, 21),
      child: child,
    ),
  );
}

/// Tombol pixel: ditekan turun, memantul squash-stretch, lalu meledakkan partikel.
class PixelButton extends StatefulWidget {
  const PixelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.sfx,
    this.color = Px.paper,
    this.shadow = Px.lav,
    this.icon,
    this.semanticLabel,
    this.expand = false,
  });

  final String label;
  final String? sfx;
  final VoidCallback? onPressed;
  final Color color, shadow;
  final IconData? icon;
  final String? semanticLabel;
  final bool expand;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _down = false;

  static const _frames = [
    (1.0, 1.0),
    (1.16, .8),
    (1.08, .9),
    (.92, 1.12),
    (.97, 1.05),
    (1.04, .97),
    (1.0, 1.0),
  ];

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _release() {
    setState(() => _down = false);
    if (!MediaQuery.disableAnimationsOf(context)) _anim.forward(from: 0);
    final box = context.findRenderObject() as RenderBox?;
    if (widget.sfx != null && box != null) {
      PixelBurst.show(
        context,
        box.localToGlobal(box.size.center(Offset.zero)),
        widget.sfx!,
      );
    }
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final content = widget.icon != null
        ? Icon(widget.icon, color: Px.ink, size: 24)
        : Text(widget.label, textAlign: TextAlign.center, style: Px.display);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      excludeSemantics: true,
      onTap: enabled ? _release : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => _release() : null,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, child) {
            final i = (_anim.value * (_frames.length - 1)).floor();
            final f = _anim.isAnimating ? _frames[i] : (1.0, 1.0);
            return Transform.scale(scaleX: f.$1, scaleY: f.$2, child: child);
          },
          child: Opacity(
            opacity: enabled ? 1 : .55,
            child: Transform.translate(
              offset: _down ? const Offset(4, 4) : Offset.zero,
              child: CustomPaint(
                painter: _FramePainter(
                  widget.color,
                  Px.ink,
                  widget.shadow,
                  _down ? 0 : 6,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: 54,
                    minWidth: widget.icon != null ? 54 : 88,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      widget.icon != null ? 9 : 16,
                      9,
                      widget.icon != null ? 15 : 22,
                      15,
                    ),
                    child: widget.expand
                        ? Center(child: content)
                        : Align(
                            widthFactor: 1,
                            heightFactor: 1,
                            child: content,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PixelBurst extends StatefulWidget {
  const PixelBurst({
    super.key,
    required this.at,
    required this.word,
    required this.onDone,
  });
  final Offset at;
  final String word;
  final VoidCallback onDone;

  static void show(BuildContext context, Offset at, String word) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) =>
          PixelBurst(at: at, word: word, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
  }

  @override
  State<PixelBurst> createState() => _PixelBurstState();
}

class _PixelBurstState extends State<PixelBurst>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BurstPainter(_c, widget.at, widget.word),
      ),
    ),
  );
}

class _BurstPainter extends CustomPainter {
  _BurstPainter(this.anim, this.at, this.word) : super(repaint: anim);
  final Animation<double> anim;
  final Offset at;
  final String word;
  static const _colors = [Px.yellow, Px.red, Px.violet, Px.green, Px.ink];

  @override
  void paint(Canvas canvas, Size size) {
    final t =
        (anim.value * 14).floor() /
        14; // Gerak patah-patah seperti frame sprite.
    final spark = (t / .68).clamp(0.0, 1.0);
    if (spark < 1) {
      for (var i = 0; i < 14; i++) {
        final a = i / 14 * 2 * pi;
        final d = (42 + (i % 3) * 20) * spark;
        final s = 8 * (1 - spark * .6);
        final c = at + Offset(cos(a) * d, sin(a) * d);
        canvas.drawRect(
          Rect.fromCenter(center: c, width: s, height: s),
          Paint()..color = _colors[i % 5],
        );
      }
    }

    final scale = t < .3
        ? .3 + t / .3 * .95
        : (t < .45 ? 1.25 - (t - .3) / .15 * .25 : 1.0);
    final opacity = t < .75 ? 1.0 : (1 - (t - .75) / .25).clamp(0.0, 1.0);
    final rise = 22 + 40 * t;
    TextPainter label(Color color) => TextPainter(
      text: TextSpan(
        text: word,
        style: TextStyle(
          fontFamily: 'PressStart',
          fontSize: 20,
          color: color.withValues(alpha: opacity),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final main = label(Px.yellow);
    final minX = main.width / 2 + 8;
    final x = at.dx.clamp(minX, max(minX, size.width - minX)).toDouble();
    canvas.save();
    canvas.translate(x, max(at.dy - rise, 34.0));
    canvas.rotate(-.09);
    canvas.scale(scale);
    final origin = Offset(-main.width / 2, -main.height / 2);
    final outline = label(Px.ink);
    label(Px.red).paint(canvas, origin + const Offset(4, 4));
    for (final o in const [
      Offset(-3, 0),
      Offset(3, 0),
      Offset(0, -3),
      Offset(0, 3),
    ]) {
      outline.paint(canvas, origin + o);
    }
    main.paint(canvas, origin);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BurstPainter o) => false;
}

class GridBackground extends StatelessWidget {
  const GridBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _GridPainter(), child: child);
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Px.bg);
    final p = Paint()..color = Px.grid;
    for (double x = 0; x < size.width; x += 32) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, size.height), p);
    }
    for (double y = 0; y < size.height; y += 32) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => false;
}
