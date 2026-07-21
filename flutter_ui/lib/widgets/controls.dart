// House controls, owned rather than Material (docs/flutter-port/04): every
// colour and metric reads the theme, idle widgets are borderless, hover and
// press bring an edge back (the K-084 owner amendment).

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';

/// The theme + workspace scope: an InheritedNotifier the whole tree reads.
class ThemeScope extends InheritedWidget {
  final LumitTheme theme;
  final AnimationLevel animationLevel;
  final bool showTooltips;

  const ThemeScope({
    super.key,
    required this.theme,
    required this.animationLevel,
    required this.showTooltips,
    required super.child,
  });

  static ThemeScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!;

  @override
  bool updateShouldNotify(ThemeScope old) =>
      old.theme != theme ||
      old.animationLevel != animationLevel ||
      old.showTooltips != showTooltips;
}

/// A borderless hover-reactive button: idle `surface3` fill (or nothing when
/// `frameless`), hover `surface4` + strong hairline, press strong fill +
/// accent edge — the egui widget-state table.
class HouseButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool frameless;
  final bool small;
  final EdgeInsets? padding;

  const HouseButton({
    super.key,
    required this.child,
    this.onPressed,
    this.frameless = false,
    this.small = false,
    this.padding,
  });

  @override
  State<HouseButton> createState() => _HouseButtonState();
}

class _HouseButtonState extends State<HouseButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scope = ThemeScope.of(context);
    final t = scope.theme;
    final enabled = widget.onPressed != null;
    Color? fill;
    Color? edge;
    if (!enabled) {
      fill = widget.frameless ? null : t.surface2;
    } else if (_down) {
      fill = t.hairlineStrong;
      edge = t.accent;
    } else if (_hover) {
      fill = t.surface4;
      edge = t.hairlineStrong;
    } else {
      fill = widget.frameless ? null : t.surface3;
    }
    final pad = widget.padding ??
        (widget.small
            ? const EdgeInsets.symmetric(horizontal: 5, vertical: 2)
            : const EdgeInsets.symmetric(horizontal: 8, vertical: 3));
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: animationDuration(scope.animationLevel),
          padding: pad,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(t.tokens.controlRadius),
            border: edge == null ? null : Border.all(color: edge, width: 1),
          ),
          child: DefaultTextStyle(
            style: enabled ? t.bodyPrimary : t.body.copyWith(color: t.textDisabled),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// One row in a dropdown/menu popup.
class MenuRow extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final bool selected;
  const MenuRow({
    super.key,
    required this.child,
    required this.onPressed,
    this.selected = false,
  });

  @override
  State<MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    final fill = _hover
        ? t.surface4
        : widget.selected
            ? t.accent.withValues(alpha: 0.5)
            : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(t.tokens.controlRadius),
          ),
          child: DefaultTextStyle(style: t.bodyPrimary, child: widget.child),
        ),
      ),
    );
  }
}

/// The floating popup surface every menu and dropdown shares: `surface3`
/// fill, hairline edge, the float radius and the real drop shadow.
class FloatSurface extends StatelessWidget {
  final Widget child;
  final double? width;
  const FloatSurface({super.key, required this.child, this.width});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(t.tokens.floatRadius),
        border: Border.all(color: t.hairline, width: 1),
        boxShadow: t.floatShadow,
      ),
      child: child,
    );
  }
}

/// A dropdown drawn as a bare label + caret; the open list floats on the
/// standard menu surface (`bare_dropdown` in the Rust settings window).
class BareDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> options;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  const BareDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return HouseButton(
      onPressed: () async {
        final box = context.findRenderObject()! as RenderBox;
        final origin = box.localToGlobal(Offset.zero);
        final picked = await showLumitPopup<T>(
          context: context,
          position: origin + Offset(0, box.size.height + 2),
          // IntrinsicWidth bounds the stretch: a float in the overlay has
          // unbounded width, and a stretched Column inside one otherwise
          // forces an infinite width (the settings-dropdown crash).
          builder: (close) => FloatSurface(
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final o in options)
                    MenuRow(
                      selected: o == value,
                      onPressed: () => close(o),
                      child: Text(label(o)),
                    ),
                ],
              ),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label(value)),
          const SizedBox(width: 4),
          CustomPaint(
            size: const Size(9, 9),
            painter: _CaretPainter(t.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  final Color color;
  const _CaretPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    canvas.drawLine(Offset(w * 0.2, h * 0.35), Offset(w * 0.5, h * 0.65), p);
    canvas.drawLine(Offset(w * 0.5, h * 0.65), Offset(w * 0.8, h * 0.35), p);
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.color != color;
}

/// Show a positioned popup and complete with the value handed to `close`.
/// Clicking outside (or Escape, via the route) dismisses with null.
Future<T?> showLumitPopup<T>({
  required BuildContext context,
  required Offset position,
  required Widget Function(void Function(T?) close) builder,
}) {
  final overlay = Overlay.of(context);
  final completer = _PopupCompleter<T>();
  late OverlayEntry entry;
  void close(T? v) {
    completer.complete(v);
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => close(null),
            onSecondaryTap: () => close(null),
          ),
        ),
        Positioned(
          left: position.dx,
          top: position.dy,
          child: builder(close),
        ),
      ],
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _PopupCompleter<T> {
  final _c = Completer<T?>();
  bool _done = false;
  void complete(T? v) {
    if (!_done) {
      _done = true;
      _c.complete(v);
    }
  }

  Future<T?> get future => _c.future;
}

/// A 14 px themed checkbox.
class HouseCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const HouseCheckbox({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: value ? t.accent : t.surface3,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: value ? t.accent : t.hairlineStrong),
        ),
        child: value
            ? CustomPaint(painter: _TickPainter(t.surface0))
            : null,
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  final Color color;
  const _TickPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.74)
      ..lineTo(size.width * 0.8, size.height * 0.28);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}

/// egui's DragValue: drag horizontally to adjust, click to type.
class DragValueField extends StatefulWidget {
  final num value;
  final num min;
  final num max;
  final double speed;
  final int decimals;
  final String? suffix;
  final ValueChanged<num> onChanged;

  const DragValueField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.speed = 1,
    this.decimals = 0,
    this.suffix,
  });

  @override
  State<DragValueField> createState() => _DragValueFieldState();
}

class _DragValueFieldState extends State<DragValueField> {
  bool _editing = false;
  bool _hover = false;
  double _dragAccum = 0;
  late TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commitText();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _format(num v) {
    final s = widget.decimals == 0
        ? v.round().toString()
        : v.toDouble().toStringAsFixed(widget.decimals);
    return widget.suffix == null ? s : '$s${widget.suffix}';
  }

  void _commitText() {
    final raw = _controller.text.replaceAll(widget.suffix ?? '', '').trim();
    final parsed = num.tryParse(raw);
    if (parsed != null) {
      widget.onChanged(parsed.clamp(widget.min, widget.max));
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    if (_editing) {
      return SizedBox(
        width: 72,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: t.surface0,
            borderRadius: BorderRadius.circular(t.tokens.controlRadius),
            border: Border.all(color: t.accent),
          ),
          child: EditableText(
            controller: _controller,
            focusNode: _focus,
            style: t.bodyPrimary,
            cursorColor: t.accent,
            backgroundCursorColor: t.surface2,
            selectionColor: t.accent.withValues(alpha: 0.5),
            onSubmitted: (_) => _commitText(),
          ),
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _editing = true;
            _controller.text = widget.decimals == 0
                ? widget.value.round().toString()
                : widget.value.toDouble().toStringAsFixed(widget.decimals);
          });
          _focus.requestFocus();
        },
        onHorizontalDragStart: (_) => _dragAccum = 0,
        onHorizontalDragUpdate: (d) {
          _dragAccum += d.delta.dx * widget.speed;
          if (_dragAccum.abs() >= widget.speed) {
            final next =
                (widget.value + _dragAccum).clamp(widget.min, widget.max);
            _dragAccum = 0;
            widget.onChanged(next);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _hover ? t.surface4 : t.surface3,
            borderRadius: BorderRadius.circular(t.tokens.controlRadius),
            border:
                _hover ? Border.all(color: t.hairlineStrong, width: 1) : null,
          ),
          child: Text(_format(widget.value), style: t.bodyPrimary),
        ),
      ),
    );
  }
}

/// A thin themed slider. `commitOnRelease` reproduces the UI-scale rule
/// (K-117): the dragged value shows live but `onChanged` fires on release.
class HouseSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final double? step;
  final int decimals;
  final String? suffix;
  final bool commitOnRelease;
  final ValueChanged<double> onChanged;

  const HouseSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step,
    this.decimals = 2,
    this.suffix,
    this.commitOnRelease = false,
  });

  @override
  State<HouseSlider> createState() => _HouseSliderState();
}

class _HouseSliderState extends State<HouseSlider> {
  double? _pending;

  double get _shown => _pending ?? widget.value;

  double _fromDx(double dx, double width) {
    var v =
        widget.min + (dx / width).clamp(0.0, 1.0) * (widget.max - widget.min);
    final s = widget.step;
    if (s != null && s > 0) v = (v / s).round() * s;
    return v.clamp(widget.min, widget.max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final t = ThemeScope.of(context).theme;
    const width = 140.0;
    final frac = ((_shown - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => widget.onChanged(_fromDx(d.localPosition.dx, width)),
          onHorizontalDragUpdate: (d) {
            final v = _fromDx(d.localPosition.dx, width);
            if (widget.commitOnRelease) {
              setState(() => _pending = v);
            } else {
              widget.onChanged(v);
            }
          },
          onHorizontalDragEnd: (_) {
            if (_pending != null) {
              widget.onChanged(_pending!);
              setState(() => _pending = null);
            }
          },
          child: SizedBox(
            width: width,
            height: 16,
            child: CustomPaint(
              painter: _SliderPainter(
                track: t.surface0,
                fill: t.accent,
                knob: t.textPrimary,
                frac: frac,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_shown.toStringAsFixed(widget.decimals)}${widget.suffix ?? ''}',
          style: t.bodyPrimary,
        ),
      ],
    );
  }
}

class _SliderPainter extends CustomPainter {
  final Color track, fill, knob;
  final double frac;
  const _SliderPainter({
    required this.track,
    required this.fill,
    required this.knob,
    required this.frac,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - 2, size.width, 4),
      const Radius.circular(2),
    );
    canvas.drawRRect(trackRect, Paint()..color = track);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - 2, size.width * frac, 4),
        const Radius.circular(2),
      ),
      Paint()..color = fill,
    );
    canvas.drawCircle(Offset(size.width * frac, y), 5, Paint()..color = knob);
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.frac != frac || old.fill != fill || old.track != track;
}

/// A tooltip that honours Settings → Interface → Show tooltips app-wide —
/// the one thing Flutter's own Tooltip cannot do.
class LumitTooltip extends StatelessWidget {
  final String message;
  final Widget child;
  const LumitTooltip({super.key, required this.message, required this.child});

  @override
  Widget build(BuildContext context) {
    final scope = ThemeScope.of(context);
    if (!scope.showTooltips) return child;
    return _HoverTip(message: message, child: child);
  }
}

class _HoverTip extends StatefulWidget {
  final String message;
  final Widget child;
  const _HoverTip({required this.message, required this.child});

  @override
  State<_HoverTip> createState() => _HoverTipState();
}

class _HoverTipState extends State<_HoverTip> {
  OverlayEntry? _entry;

  void _show(PointerEnterEvent e) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted || _entry != null) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final origin = box.localToGlobal(Offset(0, box.size.height + 4));
    final scope = ThemeScope.of(context);
    final t = scope.theme;
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: origin.dx,
        top: origin.dy,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: t.surface3,
              borderRadius: BorderRadius.circular(t.tokens.floatRadius),
              border: Border.all(color: t.hairline),
              boxShadow: t.floatShadow,
            ),
            child: Text(widget.message, style: t.body),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: _show,
        onExit: (_) => _hide(),
        child: widget.child,
      );
}
