import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Shrinks its child slightly while a pointer is down on it, so a tap is
/// answered the moment it lands rather than when the action completes.
///
/// A [Listener], not a gesture recogniser: it never competes with the child's
/// own taps, so a button wrapped in it fires exactly as before. The scale is
/// [AppMotion.pressScale] over [AppMotion.press], easing out both ways — a
/// press answers instantly and a release settles just as fast. Wrap the
/// primary actions with it; a row in a list does not need it.
class PressScale extends StatefulWidget {
  final Widget child;

  /// False keeps the child still, for a disabled control.
  final bool enabled;

  const PressScale({super.key, required this.child, this.enabled = true});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && widget.enabled ? AppMotion.pressScale : 1,
        duration: AppMotion.press,
        curve: AppMotion.enter,
        child: widget.child,
      ),
    );
  }
}
