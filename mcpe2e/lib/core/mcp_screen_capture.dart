// ─────────────────────────────────────────────────────────────────────────────
// McpScreenCapture
//
// Captura la pantalla actual como PNG usando el layer tree interno de Flutter.
//
// Diseño:
//   - CERO intrusión: no agrega ningún widget al árbol. Usa el layer que ya
//     existe en el pipeline de renderizado de Flutter (debugLayer).
//   - Solo disponible en debug/profile: en release, `debugLayer` retorna null
//     y la función falla grácilmente con {"error":"not_available_in_release"}.
//   - La captura incluye TODA la pantalla: app bar, bottom navigation, overlays.
//
// Mecanismo:
//   renderViews.first         → RenderView raíz del árbol de renderizado
//   .debugLayer as OffsetLayer → layer del frame actual (null en release)
//   .toImage(rect, pixelRatio) → imagen en memoria
//   .toByteData(format: png)   → bytes PNG
//   base64Encode(bytes)        → string listo para JSON
//
// Seguridad en producción:
//   Flutter no mantiene el layer tree en release (optimización de memoria).
//   debugLayer devuelve null → retornamos {"error":"not_available_in_release"}.
//   El HTTP server ya requiere McpEventServer.start() explícito, y ese método
//   tiene un guard que retorna temprano si no estamos en debug/profile.
//
// Output:
//   Éxito: {"format":"png","width":393,"height":852,"pixel_ratio":3.0,
//            "base64":"iVBORw0KGgo..."}
//   Error: {"error":"not_available_in_release" | "capture_failed" | "<msg>"}
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// ── API pública ────────────────────────────────────────────────────────────────

/// Captura la pantalla usando el layer tree interno de Flutter.
///
/// No requiere widgets adicionales en el árbol ni claves especiales.
/// Solo disponible en debug/profile; retorna error en release.
///
/// Uso:
/// ```dart
/// final json = await McpScreenCapture.capture();
/// if (json.containsKey('error')) {
///   // no disponible (release mode o error)
/// } else {
///   final base64 = json['base64'] as String;
///   // enviar como imagen MCP o mostrar
/// }
/// ```
class McpScreenCapture {
  McpScreenCapture._();

  /// Captura el frame actual como PNG.
  ///
  /// Retorna un mapa con:
  /// - `format`: siempre `"png"`
  /// - `width`: ancho lógico en puntos
  /// - `height`: alto lógico en puntos
  /// - `pixel_ratio`: ratio de píxeles del dispositivo
  /// - `base64`: imagen PNG codificada en base64
  ///
  /// En caso de error retorna `{"error": "<motivo>"}`.
  static Future<Map<String, dynamic>> capture() async {
    try {
      // Obtener el RenderView raíz
      final renderViews = WidgetsBinding.instance.renderViews;
      if (renderViews.isEmpty) {
        return {'error': 'no_render_view'};
      }
      final renderView = renderViews.first;

      // debugLayer es null en release mode (Flutter no mantiene el layer tree)
      final layer = renderView.debugLayer;
      if (layer == null || layer is! OffsetLayer) {
        return {'error': 'not_available_in_release'};
      }

      final pixelRatio = renderView.flutterView.devicePixelRatio;
      final logicalSize = renderView.size;

      // Renderizar el layer a una imagen en memoria
      final image = await layer.toImage(
        Offset.zero & logicalSize,
        pixelRatio: pixelRatio,
      );

      // Convertir a PNG
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        return {'error': 'capture_failed'};
      }

      final base64 = base64Encode(byteData.buffer.asUint8List());

      return {
        'format': 'png',
        'width': logicalSize.width.toInt(),
        'height': logicalSize.height.toInt(),
        'pixel_ratio': pixelRatio,
        'base64': base64,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
