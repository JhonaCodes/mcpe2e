// ─────────────────────────────────────────────────────────────────────────────
// McpGestureSimulator
//
// Physical gesture simulation layer on top of Flutter's render tree.
//
// Translates coordinates (Offset) into pointer events that Flutter processes
// just as if they were real user touches. Knows nothing about MCP, registered
// widgets, or event types — only receives positions and generates events.
//
// Mechanism: GestureBinding.instance.handlePointerEvent() accepts synthetic
// PointerEvents, which Flutter routes to the correct GestureDetector based on
// position. This works in debug and profile mode; in release mode the same APIs operate.
//
// Flow:
//   Executor calculates position via RenderBox → passes Offset here →
//   GestureSimulator generates PointerEvents → GestureBinding routes them →
//   Widget responds just as it would to a real touch
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:logger_rs/logger_rs.dart';

// ── Simulator ────────────────────────────────────────────────────────────────

/// Low-level gesture simulator.
///
/// Operates on global screen coordinates. The caller is responsible
/// for calculating the correct coordinates from the widget's RenderBox.
class McpGestureSimulator {
  McpGestureSimulator._();

  static final McpGestureSimulator instance = McpGestureSimulator._();

  // Incremental pointer ID counter to avoid collisions between concurrent
  // gestures (although in practice gestures are sequential).
  int _pointerCounter = 1;

  int get _nextPointer => _pointerCounter++;

  // ── Position helpers ──────────────────────────────────────────────────

  /// Calculates the center of a [RenderBox] in global screen coordinates.
  ///
  /// Uses localToGlobal(Offset.zero) to convert the top-left corner
  /// to global coordinates, then adds half the widget's size.
  Offset centerOf(RenderBox renderBox) {
    final origin = renderBox.localToGlobal(Offset.zero);
    return origin + Offset(renderBox.size.width / 2, renderBox.size.height / 2);
  }

  // ── Simple gestures ───────────────────────────────────────────────────────

  /// Simulates a tap (quick touch) at the [position].
  ///
  /// Generates a PointerDownEvent immediately followed by a PointerUpEvent.
  /// Flutter interprets this sequence as a complete tap and triggers the
  /// GestureDetectors with onTap / onPressed that contain that position.
  void simulateTap(Offset position) {
    final pointer = _nextPointer;
    Log.i(
      '[Gesture] 👆 TAP en (${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)})',
    );
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(position: position, pointer: pointer),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(position: position, pointer: pointer),
    );
  }

  /// Simulates a swipe from [start] to [end] over [duration].
  ///
  /// Linear interpolation of 20 steps using Future.delayed to respect
  /// timing. Flutter needs to see intermediate PointerMoveEvents to recognize
  /// the gesture as a swipe and not as a long press.
  ///
  /// Note: the Future.delayed calls are intentionally fire-and-forget — the
  /// caller does not need to wait for all events to be emitted because Flutter
  /// processes them on the same UI isolate.
  void simulateSwipe(Offset start, Offset end, Duration duration) {
    const steps = 20;
    final stepMs = duration.inMilliseconds ~/ steps;
    final pointer = _nextPointer;

    Log.i(
      '[Gesture] 👉 SWIPE de $start a $end (${duration.inMilliseconds}ms, $steps pasos)',
    );

    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(position: start, pointer: pointer),
    );

    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final pos = Offset.lerp(start, end, t)!;
      Future.delayed(Duration(milliseconds: stepMs * i), () {
        GestureBinding.instance.handlePointerEvent(
          PointerMoveEvent(position: pos, pointer: pointer),
        );
      });
    }

    Future.delayed(duration, () {
      GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(position: end, pointer: pointer),
      );
    });
  }

  /// Simulates a scroll event at [position] with the given deltas.
  ///
  /// PointerScrollEvent is the standard mechanism for mouse/trackpad scrolling.
  /// On touch devices, scrolling is better achieved with [simulateSwipe].
  void simulateScroll(Offset position, {double deltaX = 0, double deltaY = 0}) {
    Log.i('[Gesture] 📜 SCROLL en $position (dx=$deltaX, dy=$deltaY)');
    GestureBinding.instance.handlePointerEvent(
      PointerScrollEvent(
        position: position,
        scrollDelta: Offset(deltaX, deltaY),
      ),
    );
  }
}
