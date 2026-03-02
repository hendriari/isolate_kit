import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:isolate_kit/isolate_kit.dart';

/// Heavy image resize with high-quality interpolation methods
/// Supports: Bilinear, Bicubic, Lanczos3 interpolation
class HeavyImageResizeTask extends IsolateTask<Uint8List, String> {
  final Map<String, dynamic> _payload;
  final Uint8List _imageData;

  HeavyImageResizeTask(this._payload, this._imageData);

  // @override
  // int get priority => TaskPriority.high; [DEFAULT PRIORITY: NORMAL]
  @override
  Uint8List get command => _imageData;
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'HeavyImageResizeTask';
  @override
  List<TransferableTypedData>? get transferables => [
    TransferableTypedData.fromList([_imageData]),
  ];

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final srcWidth = _payload['sourceWidth'] as int;
    final srcHeight = _payload['sourceHeight'] as int;
    final dstWidth = _payload['targetWidth'] as int;
    final dstHeight = _payload['targetHeight'] as int;
    final method = _payload['method'] as String? ?? 'lanczos3';

    // Validate input
    final expectedSize = srcWidth * srcHeight * 4;
    if (_imageData.length != expectedSize) {
      throw Exception(
        'Invalid image data size: expected $expectedSize bytes (${srcWidth}x${srcHeight}x4), got ${_imageData.length} bytes',
      );
    }

    sendProgress?.call(
      TaskProgress(percentage: 0.0, message: 'Starting $method resize...'),
    );

    final stopwatch = Stopwatch()..start();
    int totalOps = 0;

    switch (method) {
      case 'bilinear':
        await _bilinearResize(
          srcWidth,
          srcHeight,
          dstWidth,
          dstHeight,
          sendProgress,
          cancellationToken,
          (ops) => totalOps += ops,
        );
        break;
      case 'bicubic':
        await _bicubicResize(
          srcWidth,
          srcHeight,
          dstWidth,
          dstHeight,
          sendProgress,
          cancellationToken,
          (ops) => totalOps += ops,
        );
        break;
      case 'lanczos3':
        await _lanczos3Resize(
          srcWidth,
          srcHeight,
          dstWidth,
          dstHeight,
          sendProgress,
          cancellationToken,
          (ops) => totalOps += ops,
        );
        break;
      default:
        throw Exception('Unknown method: $method');
    }

    stopwatch.stop();

    final elapsedSeconds = (stopwatch.elapsedMilliseconds / 1000)
        .toStringAsFixed(2);
    final opsPerSec = _formatNumber(
      (totalOps / stopwatch.elapsedMilliseconds * 1000).round(),
    );

    sendProgress?.call(
      TaskProgress(percentage: 1.0, message: 'Resize complete!'),
    );

    return '''
Image Resize Complete
Method: ${method.toUpperCase()}
Resolution: ${srcWidth}x$srcHeight → ${dstWidth}x$dstHeight
Total Operations: ${_formatNumber(totalOps)}
Time: ${elapsedSeconds}s
Throughput: $opsPerSec ops/sec
''';
  }

  /// Safe pixel access with bounds checking
  int _getPixel(int x, int y, int channel, int width, int height) {
    // Clamp coordinates
    x = x.clamp(0, width - 1);
    y = y.clamp(0, height - 1);

    final index = (y * width + x) * 4 + channel;

    // Double check bounds
    if (index < 0 || index >= _imageData.length) {
      return 0; // Return black as fallback
    }

    return _imageData[index];
  }

  /// Bilinear interpolation - smooth, moderate cost
  /// ~16 ops per output pixel
  Future<Uint8List> _bilinearResize(
    int srcW,
    int srcH,
    int dstW,
    int dstH,
    void Function(TaskProgress)? sendProgress,
    CancellationToken? token,
    void Function(int) addOps,
  ) async {
    final output = Uint8List(dstW * dstH * 4);
    final xRatio = (srcW - 1) / dstW;
    final yRatio = (srcH - 1) / dstH;

    for (int y = 0; y < dstH; y++) {
      token?.throwIfCancelled();

      for (int x = 0; x < dstW; x++) {
        token?.throwIfCancelled();

        final srcX = x * xRatio;
        final srcY = y * yRatio;

        final x1 = srcX.floor();
        final y1 = srcY.floor();
        final x2 = math.min(x1 + 1, srcW - 1);
        final y2 = math.min(y1 + 1, srcH - 1);

        final xWeight = srcX - x1;
        final yWeight = srcY - y1;

        final dstIdx = (y * dstW + x) * 4;

        // Interpolate each channel with safe access
        for (int c = 0; c < 4; c++) {
          token?.throwIfCancelled();

          final p11 = _getPixel(x1, y1, c, srcW, srcH);
          final p21 = _getPixel(x2, y1, c, srcW, srcH);
          final p12 = _getPixel(x1, y2, c, srcW, srcH);
          final p22 = _getPixel(x2, y2, c, srcW, srcH);

          final top = p11 * (1 - xWeight) + p21 * xWeight;
          final bottom = p12 * (1 - xWeight) + p22 * xWeight;
          final value = top * (1 - yWeight) + bottom * yWeight;

          output[dstIdx + c] = value.clamp(0, 255).toInt();
        }
      }

      if (y % (dstH ~/ 20).clamp(1, dstH) == 0) {
        sendProgress?.call(
          TaskProgress(percentage: y / dstH, message: 'Bilinear: row $y/$dstH'),
        );
      }
    }

    addOps(dstW * dstH * 16); // ~16 ops per pixel
    return output;
  }

  /// Bicubic interpolation - higher quality, expensive
  /// ~64 ops per output pixel (4x4 kernel)
  Future<Uint8List> _bicubicResize(
    int srcW,
    int srcH,
    int dstW,
    int dstH,
    void Function(TaskProgress)? sendProgress,
    CancellationToken? token,
    void Function(int) addOps,
  ) async {
    final output = Uint8List(dstW * dstH * 4);
    final xRatio = (srcW - 1) / dstW;
    final yRatio = (srcH - 1) / dstH;

    for (int y = 0; y < dstH; y++) {
      token?.throwIfCancelled();

      for (int x = 0; x < dstW; x++) {
        token?.throwIfCancelled();

        final srcX = x * xRatio;
        final srcY = y * yRatio;

        final x1 = srcX.floor();
        final y1 = srcY.floor();

        final dx = srcX - x1;
        final dy = srcY - y1;

        final dstIdx = (y * dstW + x) * 4;

        // Process each channel
        for (int c = 0; c < 4; c++) {
          token?.throwIfCancelled();

          double sum = 0;

          // 4x4 bicubic kernel
          for (int ky = -1; ky <= 2; ky++) {
            token?.throwIfCancelled();

            for (int kx = -1; kx <= 2; kx++) {
              token?.throwIfCancelled();

              final sx = x1 + kx;
              final sy = y1 + ky;

              final pixel = _getPixel(sx, sy, c, srcW, srcH);
              final wx = _cubicWeight(kx - dx);
              final wy = _cubicWeight(ky - dy);

              sum += pixel * wx * wy;
            }
          }

          output[dstIdx + c] = sum.clamp(0, 255).toInt();
        }
      }

      if (y % (dstH ~/ 20).clamp(1, dstH) == 0) {
        sendProgress?.call(
          TaskProgress(percentage: y / dstH, message: 'Bicubic: row $y/$dstH'),
        );
      }
    }

    addOps(dstW * dstH * 64); // 4×4 kernel × 4 channels
    return output;
  }

  /// Lanczos3 interpolation - highest quality, VERY expensive
  /// ~144 ops per output pixel (6x6 kernel + sinc calculations)
  Future<Uint8List> _lanczos3Resize(
    int srcW,
    int srcH,
    int dstW,
    int dstH,
    void Function(TaskProgress)? sendProgress,
    CancellationToken? token,
    void Function(int) addOps,
  ) async {
    final output = Uint8List(dstW * dstH * 4);
    final xRatio = srcW / dstW;
    final yRatio = srcH / dstH;
    const a = 3; // Lanczos kernel size

    for (int y = 0; y < dstH; y++) {
      token?.throwIfCancelled();

      for (int x = 0; x < dstW; x++) {
        token?.throwIfCancelled();

        final srcX = (x + 0.5) * xRatio - 0.5;
        final srcY = (y + 0.5) * yRatio - 0.5;

        final x0 = srcX.floor();
        final y0 = srcY.floor();

        final dstIdx = (y * dstW + x) * 4;

        // Process each channel
        for (int c = 0; c < 4; c++) {
          token?.throwIfCancelled();

          double sum = 0;
          double weightSum = 0;

          // 6x6 Lanczos kernel
          for (int ky = -a + 1; ky <= a; ky++) {
            token?.throwIfCancelled();

            for (int kx = -a + 1; kx <= a; kx++) {
              token?.throwIfCancelled();

              final sx = x0 + kx;
              final sy = y0 + ky;

              final pixel = _getPixel(sx, sy, c, srcW, srcH);

              final dx = srcX - (x0 + kx);
              final dy = srcY - (y0 + ky);

              final wx = _lanczosWeight(dx, a);
              final wy = _lanczosWeight(dy, a);
              final weight = wx * wy;

              sum += pixel * weight;
              weightSum += weight;
            }
          }

          output[dstIdx + c] = (sum / (weightSum + 1e-8)).clamp(0, 255).toInt();
        }
      }

      if (y % (dstH ~/ 20).clamp(1, dstH) == 0) {
        sendProgress?.call(
          TaskProgress(percentage: y / dstH, message: 'Lanczos3: row $y/$dstH'),
        );
      }
    }

    addOps(dstW * dstH * 144); // 6×6 kernel × 4 channels
    return output;
  }

  /// Cubic interpolation weight function
  double _cubicWeight(double x) {
    x = x.abs();
    if (x <= 1) {
      return 1.5 * x * x * x - 2.5 * x * x + 1;
    } else if (x < 2) {
      return -0.5 * x * x * x + 2.5 * x * x - 4 * x + 2;
    }
    return 0;
  }

  /// Lanczos windowed sinc function
  double _lanczosWeight(double x, int a) {
    if (x == 0) return 1;
    if (x.abs() >= a) return 0;

    final px = math.pi * x;
    return a * math.sin(px) * math.sin(px / a) / (px * px);
  }

  String _formatNumber(int number) {
    final str = number.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return buffer.toString();
  }
}
