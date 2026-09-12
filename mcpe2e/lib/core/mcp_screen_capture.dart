// ─────────────────────────────────────────────────────────────────────────────
// McpScreenCapture
//
// Captures the current screen as PNG using Flutter's internal layer tree.
//
// Design:
//   - ZERO intrusion: does not add any widget to the tree. Uses the layer that
//     already exists in Flutter's rendering pipeline (debugLayer).
//   - Only available in debug/profile: in release, `debugLayer` returns null
//     and the function fails gracefully with {"error":"not_available_in_release"}.
//   - The capture includes the ENTIRE screen: app bar, bottom navigation, overlays.
//
// Mechanism:
//   renderViews.first         → root RenderView of the render tree
//   .debugLayer as OffsetLayer → layer of the current frame (null in release)
//   .toImage(rect, pixelRatio) → in-memory image
//   .toByteData(format: png)   → PNG bytes
//   base64Encode(bytes)        → string ready for JSON
//
// Production safety:
//   Flutter does not maintain the layer tree in release (memory optimization).
//   debugLayer returns null → we return {"error":"not_available_in_release"}.
//   The HTTP server already requires an explicit McpEventServer.start(), and
//   that method has a guard that returns early if we are not in debug/profile.
//
// Output:
//   Success: {"format":"png","width":393,"height":852,"pixel_ratio":3.0,
//              "base64":"iVBORw0KGgo..."}
//   Error:   {"error":"not_available_in_release" | "capture_failed" | "<msg>"}
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Captures the screen using Flutter's internal layer tree.
///
/// Does not require additional widgets in the tree or special keys.
/// Only available in debug/profile; returns error in release.
///
/// Usage:
/// ```dart
/// final json = await McpScreenCapture.capture();
/// if (json.containsKey('error')) {
///   // not available (release mode or error)
/// } else {
///   final base64 = json['base64'] as String;
///   // send as MCP image or display
/// }
/// ```
class McpScreenCapture {
  McpScreenCapture._();

  /// Captures the current frame as PNG.
  ///
  /// Returns a map with:
  /// - `format`: always `"png"`
  /// - `width`: logical width in points
  /// - `height`: logical height in points
  /// - `pixel_ratio`: device pixel ratio
  /// - `base64`: base64-encoded PNG image
  ///
  /// On error returns `{"error": "<reason>"}`.
  static Future<Map<String, dynamic>> capture() async {
    try {
      // Get the root RenderView
      final renderViews = WidgetsBinding.instance.renderViews;
      if (renderViews.isEmpty) {
        return {'error': 'no_render_view'};
      }
      final renderView = renderViews.first;

      // debugLayer is null in release mode (Flutter does not maintain the layer tree)
      final layer = renderView.debugLayer;
      if (layer == null || layer is! OffsetLayer) {
        return {'error': 'not_available_in_release'};
      }

      final pixelRatio = renderView.flutterView.devicePixelRatio;
      final logicalSize = renderView.size;

      // `renderView.debugLayer` is the RenderView's OWN root layer, which
      // Flutter creates as a TransformLayer whose transform already IS the
      // device pixel ratio scale (RenderView._updateMatricesAndCreateNewRootLayer,
      // ViewConfiguration.toMatrix). Passing `pixelRatio` to `toImage()` on
      // top of that double-applies the device pixel ratio: the output image's
      // dimensions come out correct (logicalSize * pixelRatio, matching the
      // physical screen), which is why this looked fine from the returned
      // width/height, but the actual content is scaled and positioned as if
      // drawn onto a canvas pixelRatio times larger again, so only a small
      // fragment near one corner survives inside the correctly-sized buffer.
      //
      // The fix: since the layer's own transform already applies pixelRatio,
      // bounds must be given in the post-transform (physical) coordinate
      // space, and the additional pixelRatio passed to toImage() must be 1.0
      // so it isn't applied a second time.
      final physicalSize = logicalSize * pixelRatio;
      final image = await layer.toImage(
        Offset.zero & physicalSize,
        pixelRatio: 1.0,
      );

      // Convert to PNG
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
