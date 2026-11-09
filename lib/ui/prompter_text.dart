// Texto del teleprompter: resalta lo leído, desplaza suavemente hasta la
// línea de lectura, permite tocar una palabra para saltar y aplica espejo.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/settings.dart';
import '../services/prompter_controller.dart';

class PrompterText extends StatefulWidget {
  const PrompterText({
    super.key,
    required this.controller,
    this.compact = false,
    this.mirror,
    this.fontScale = 1.0,
    this.overCamera = false,
  });

  final PrompterController controller;
  final bool compact;
  final MirrorMode? mirror;
  final double fontScale;
  final bool overCamera;

  @override
  State<PrompterText> createState() => _PrompterTextState();
}

class _PrompterTextState extends State<PrompterText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _scroll = 0; // desplazamiento actual (px)
  double _target = 0;
  TextPainter? _painter;
  String _layoutKey = '';
  double _lastWidth = 0;
  double _lastHeight = 0;
  Duration _lastTick = Duration.zero;

  PrompterController get c => widget.controller;
  AppSettings get s => c.settings;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    c.addListener(_onChange);
    s.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant PrompterText old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      old.controller.settings.removeListener(_onChange);
      c.addListener(_onChange);
      s.addListener(_onChange);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    c.removeListener(_onChange);
    s.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = elapsed;
    final diff = _target - _scroll;
    if (diff.abs() < 0.3) {
      if (_scroll != _target) setState(() => _scroll = _target);
      return;
    }
    // Suavizado exponencial (~150 ms).
    final k = 1 - math.exp(-dt / 0.15);
    setState(() => _scroll += diff * k);
  }

  double get _fontSize =>
      (widget.compact ? s.fontSize * 0.75 : s.fontSize) * widget.fontScale;

  double get _padding => widget.compact ? 14 : 28;

  TextStyle _base() => TextStyle(
        fontSize: _fontSize,
        height: 1.35,
        fontFamily: fontFamilyFor(s.font),
        fontFamilyFallback: fontFallbackFor(s.font),
        color: Colors.white,
        fontWeight: FontWeight.w500,
        shadows: widget.overCamera
            ? const [Shadow(blurRadius: 6, color: Colors.black)]
            : null,
      );

  void _ensureLayout(double width) {
    final cur = c.wordPosition.floor();
    final key = [
      c.collapsed.hashCode,
      c.pageIndex,
      cur,
      widget.overCamera,
      width.round(),
      _fontSize,
      s.font.name,
      s.highlightName,
    ].join('|');
    if (key == _layoutKey && _painter != null) return;
    _layoutKey = key;

    final hl = s.highlightColor;
    final base = _base();
    final spans = <TextSpan>[];
    for (var i = 0; i < c.words.length; i++) {
      final isAnn = c.annotation[i];
      Color color;
      if (isAnn) {
        color = const Color(0xFF8E8E93);
      } else if (i < cur) {
        color = hl.withValues(alpha: 0.55);
      } else if (i == cur) {
        color = hl;
      } else {
        color = Colors.white;
      }
      spans.add(TextSpan(
        text: i == c.words.length - 1 ? c.words[i] : '${c.words[i]} ',
        style: TextStyle(
          color: color,
          fontStyle: isAnn ? FontStyle.italic : FontStyle.normal,
        ),
      ));
    }
    _painter?.dispose();
    _painter = TextPainter(
      text: TextSpan(style: base, children: spans),
      textDirection:
          _isRtl(c.collapsed) ? TextDirection.rtl : TextDirection.ltr,
      textAlign: TextAlign.start,
    )..layout(maxWidth: math.max(10, width - _padding * 2));
  }

  bool _isRtl(String text) => RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]')
      .hasMatch(text.length > 200 ? text.substring(0, 200) : text);

  double _yForWord(int i) {
    final p = _painter!;
    if (c.words.isEmpty) return 0;
    if (i >= c.words.length) return p.height;
    final off =
        p.getOffsetForCaret(TextPosition(offset: c.wordOffsets[i]), Rect.zero);
    return off.dy;
  }

  double _computeTarget(double height) {
    final pos = c.wordPosition;
    final i = pos.floor();
    var y = _yForWord(i);
    if (c.mode != GuidanceMode.wordTracking && i + 1 <= c.words.length) {
      final y2 = _yForWord(i + 1);
      y += (y2 - y) * (pos - i);
    }
    final anchor =
        height * (s.readingLineTop ? (widget.compact ? 0.12 : 0.22) : 0.42);
    return y - anchor;
  }

  void _handleTap(Offset local, Size size) {
    final p = _painter;
    if (p == null || c.words.isEmpty) return;
    var pt = local;
    final m = widget.mirror ?? s.mirror;
    if (m == MirrorMode.horizontal || m == MirrorMode.both) {
      pt = Offset(size.width - pt.dx, pt.dy);
    }
    if (m == MirrorMode.vertical || m == MirrorMode.both) {
      pt = Offset(pt.dx, size.height - pt.dy);
    }
    final textPt = Offset(pt.dx - _padding, pt.dy + _scroll);
    final charIndex = p.getPositionForOffset(textPt).offset;
    var word = 0;
    for (var i = 0; i < c.wordOffsets.length; i++) {
      if (c.wordOffsets[i] <= charIndex) word = i;
    }
    c.jumpToWord(word);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      _ensureLayout(size.width);
      _target = _computeTarget(size.height);
      if (_lastWidth != size.width ||
          _lastHeight != size.height ||
          (_target - _scroll).abs() > size.height * 3) {
        // Cambio de tamaño o salto grande: sin animación.
        _scroll = _target;
        _lastWidth = size.width;
        _lastHeight = size.height;
      }
      final m = widget.mirror ?? s.mirror;
      final sx =
          (m == MirrorMode.horizontal || m == MirrorMode.both) ? -1.0 : 1.0;
      final sy =
          (m == MirrorMode.vertical || m == MirrorMode.both) ? -1.0 : 1.0;

      Widget content = CustomPaint(
        size: size,
        painter: _TextPainterDelegate(
          painter: _painter!,
          scroll: _scroll,
          padding: _padding,
          readingLine: s.readingLineTop
              ? size.height * (widget.compact ? 0.12 : 0.22)
              : size.height * 0.42,
          lineHeight: _fontSize * 1.35,
          showLine: !widget.compact,
          fades: !widget.overCamera,
        ),
      );
      if (sx != 1 || sy != 1) {
        content = Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(sx, sy, 1),
          child: content,
        );
      }

      return Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            c.nudge(e.scrollDelta.dy / 25);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d.localPosition, size),
          onVerticalDragStart: (_) => c.userScrolling = true,
          onVerticalDragUpdate: (d) =>
              c.nudge(-d.delta.dy / (_fontSize * 0.6) * sy),
          onVerticalDragEnd: (_) => c.userScrolling = false,
          onVerticalDragCancel: () => c.userScrolling = false,
          child: ClipRect(child: content),
        ),
      );
    });
  }
}

class _TextPainterDelegate extends CustomPainter {
  _TextPainterDelegate({
    required this.painter,
    required this.scroll,
    required this.padding,
    required this.readingLine,
    required this.lineHeight,
    required this.showLine,
    required this.fades,
  });

  final TextPainter painter;
  final double scroll;
  final double padding;
  final double readingLine;
  final double lineHeight;
  final bool showLine;
  final bool fades;

  @override
  void paint(Canvas canvas, Size size) {
    if (showLine) {
      final guide = Paint()..color = const Color(0x22FFFFFF);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(4, readingLine - 4, size.width - 8, lineHeight + 8),
          const Radius.circular(8),
        ),
        guide,
      );
    }
    painter.paint(canvas, Offset(padding, -scroll));
    if (!fades) return;
    // Degradados arriba y abajo.
    final fadeH = math.min(60.0, size.height * 0.18);
    final top = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black, Color(0x00000000)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, fadeH));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, fadeH), top);
    final bottom = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Colors.black, Color(0x00000000)],
      ).createShader(Rect.fromLTWH(0, size.height - fadeH, size.width, fadeH));
    canvas.drawRect(
        Rect.fromLTWH(0, size.height - fadeH, size.width, fadeH), bottom);
  }

  @override
  bool shouldRepaint(covariant _TextPainterDelegate old) => true;
}
