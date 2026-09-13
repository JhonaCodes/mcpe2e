import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcpe2e/core/mcp_screen_capture.dart';

/// Decodes a PNG and returns its raw RGBA pixels plus dimensions.
Future<(Uint8List pixels, int width, int height)> _decodePng(
  Uint8List pngBytes,
) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = byteData!.buffer.asUint8List();
  final result = (pixels, image.width, image.height);
  image.dispose();
  return result;
}

Color _pixelAt(Uint8List rgba, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
}

void main() {
  testWidgets(
    'capture() returns an image whose content is scaled by devicePixelRatio exactly once',
    (tester) async {
      // A non-integer, non-default ratio makes a double-scaling bug obvious:
      // logical 100x100 -> physical 250x250 at 2.5x, not 400x400 (2.5^2).
      const pixelRatio = 2.5;
      const logicalSize = Size(100, 100);
      tester.view.physicalSize = logicalSize * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Red background with a small blue marker square in the bottom-right
      // quadrant, at a known logical offset. If devicePixelRatio is applied
      // twice, the marker is drawn far outside the (correctly physical-sized)
      // output canvas and the expected pixel is never blue.
      const markerLogicalLeft = 80.0;
      const markerLogicalTop = 80.0;
      const markerLogicalSize = 10.0;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Container(color: Colors.red, width: 100, height: 100),
              Positioned(
                left: markerLogicalLeft,
                top: markerLogicalTop,
                child: Container(
                  color: Colors.blue,
                  width: markerLogicalSize,
                  height: markerLogicalSize,
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      // toImage()/toByteData() schedule real raster-thread work that the
      // fake-async testWidgets zone never drives; runAsync escapes that zone
      // so the futures actually resolve instead of hanging until timeout.
      final (pixels, width, height) = await tester.runAsync(() async {
        final result = await McpScreenCapture.capture();
        expect(result.containsKey('error'), isFalse, reason: '${result['error']}');
        final base64 = result['base64'] as String;
        return _decodePng(Uint8List.fromList(base64Decode(base64)));
      }) ?? (throw StateError('runAsync returned null'));

      // The output image must be the PHYSICAL screen size: logical size times
      // devicePixelRatio, applied once.
      expect(width, (logicalSize.width * pixelRatio).round());
      expect(height, (logicalSize.height * pixelRatio).round());

      // The marker's centre, mapped through devicePixelRatio exactly once,
      // must be blue. A double-application of devicePixelRatio scales and
      // shifts the marker out of frame (or into the wrong quadrant), so this
      // is the assertion that fails under the bug and passes once fixed.
      final expectedX =
          ((markerLogicalLeft + markerLogicalSize / 2) * pixelRatio).round();
      final expectedY =
          ((markerLogicalTop + markerLogicalSize / 2) * pixelRatio).round();
      final centre = _pixelAt(pixels, width, expectedX, expectedY);
      expect(
        centre.toARGB32(),
        Colors.blue.toARGB32(),
        reason:
            'expected the marker at physical ($expectedX,$expectedY) to be blue; '
            'got $centre. devicePixelRatio is likely applied twice.',
      );

      // A pixel where the double-scaled bug would have placed content
      // (near the far edge/corner of the canvas) should NOT be blue once
      // fixed: the marker only occupies its correctly-scaled small square.
      final farCorner = _pixelAt(pixels, width, width - 1, height - 1);
      expect(farCorner.toARGB32(), isNot(Colors.blue.toARGB32()));
    },
  );
}
