// ─────────────────────────────────────────────────────────────────────────────
// McpGestureSimulator
//
// Capa de simulación de gestos físicos sobre el árbol de renderizado de Flutter.
//
// Traduce coordenadas (Offset) en eventos de puntero que Flutter procesa igual
// que si fueran toques reales del usuario. No conoce nada de MCP, widgets
// registrados ni tipos de eventos — solo recibe posiciones y genera eventos.
//
// Mecanismo: GestureBinding.instance.handlePointerEvent() acepta PointerEvent
// sintéticos, que Flutter enruta al GestureDetector correcto según la posición.
// Esto funciona en debug y profile mode; en release mode las mismas APIs operan.
//
// Flujo:
//   Executor calcula posición via RenderBox → pasa Offset aquí →
//   GestureSimulator genera PointerEvents → GestureBinding los enruta →
//   Widget responde igual que a un toque real
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:logger_rs/logger_rs.dart';

// ── Simulator ────────────────────────────────────────────────────────────────

/// Simulador de gestos de bajo nivel.
///
/// Opera sobre coordenadas globales de pantalla. El llamador es responsable
/// de calcular las coordenadas correctas a partir del RenderBox del widget.
class McpGestureSimulator {
  McpGestureSimulator._();

  static final McpGestureSimulator instance = McpGestureSimulator._();

  // Contador incremental de pointer IDs para evitar colisiones entre gestos
  // concurrentes (aunque en la práctica los gestos son secuenciales).
  int _pointerCounter = 1;

  int get _nextPointer => _pointerCounter++;

  // ── Helpers de posición ──────────────────────────────────────────────────

  /// Calcula el centro de un [RenderBox] en coordenadas globales de pantalla.
  ///
  /// Usa localToGlobal(Offset.zero) para convertir la esquina superior-izquierda
  /// a coordenadas globales, y luego suma la mitad del tamaño del widget.
  Offset centerOf(RenderBox renderBox) {
    final origin = renderBox.localToGlobal(Offset.zero);
    return origin + Offset(renderBox.size.width / 2, renderBox.size.height / 2);
  }

  // ── Gestos simples ───────────────────────────────────────────────────────

  /// Simula un tap (toque rápido) en la posición [position].
  ///
  /// Genera un PointerDownEvent seguido inmediatamente de un PointerUpEvent.
  /// Flutter interpreta esta secuencia como un tap completo y activa los
  /// GestureDetector con onTap / onPressed que contengan esa posición.
  void simulateTap(Offset position) {
    final pointer = _nextPointer;
    Log.i('[Gesture] 👆 TAP en (${position.dx.toStringAsFixed(1)}, ${position.dy.toStringAsFixed(1)})');
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(position: position, pointer: pointer));
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(position: position, pointer: pointer));
  }

  /// Simula un swipe (deslizamiento) desde [start] hasta [end] en [duration].
  ///
  /// Interpolación lineal de 20 pasos usando Future.delayed para respetar el
  /// timing. Flutter necesita ver PointerMoveEvents intermedios para reconocer
  /// el gesto como swipe y no como tap largo.
  ///
  /// Nota: los Future.delayed son fire-and-forget intencionales — el caller
  /// no necesita esperar a que todos los eventos se emitan porque Flutter
  /// los procesa en el mismo isolate de UI.
  void simulateSwipe(Offset start, Offset end, Duration duration) {
    const steps = 20;
    final stepMs = duration.inMilliseconds ~/ steps;
    final pointer = _nextPointer;

    Log.i('[Gesture] 👉 SWIPE de $start a $end (${duration.inMilliseconds}ms, $steps pasos)');

    GestureBinding.instance.handlePointerEvent(PointerDownEvent(position: start, pointer: pointer));

    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final pos = Offset.lerp(start, end, t)!;
      Future.delayed(Duration(milliseconds: stepMs * i), () {
        GestureBinding.instance.handlePointerEvent(PointerMoveEvent(position: pos, pointer: pointer));
      });
    }

    Future.delayed(duration, () {
      GestureBinding.instance.handlePointerEvent(PointerUpEvent(position: end, pointer: pointer));
    });
  }

  /// Simula un evento de scroll en [position] con los deltas dados.
  ///
  /// PointerScrollEvent es el mecanismo estándar para scroll de mouse/trackpad.
  /// En dispositivos táctiles, el scroll se logra mejor con [simulateSwipe].
  void simulateScroll(Offset position, {double deltaX = 0, double deltaY = 0}) {
    Log.i('[Gesture] 📜 SCROLL en $position (dx=$deltaX, dy=$deltaY)');
    GestureBinding.instance.handlePointerEvent(
      PointerScrollEvent(position: position, scrollDelta: Offset(deltaX, deltaY)),
    );
  }
}
