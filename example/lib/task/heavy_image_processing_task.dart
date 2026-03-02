import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:isolate_kit/isolate_kit.dart';

/// Heavy image processing pipeline with multiple filters and iterations
/// Simulates real-world image enhancement workflow
class HeavyImageProcessingTask extends IsolateTask<Uint8List, String> {
  final Map<String, dynamic> _payload;
  final Uint8List _imageData;

  HeavyImageProcessingTask(this._payload, this._imageData);

  // @override
  // int get priority => TaskPriority.high; [DEFAULT PRIORITY: NORMAL]
  @override
  Uint8List get command => _imageData;
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'HeavyImageProcessingTask';
  @override
  List<TransferableTypedData>? get transferables => [
    TransferableTypedData.fromList([_imageData]),
  ];

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final width = _payload['width'] as int;
    final height = _payload['height'] as int;
    final iterations = _payload['iterations'] as int? ?? 3;
    final totalPixels = width * height;

    sendProgress?.call(
      TaskProgress(percentage: 0.0, message: 'Starting image pipeline...'),
    );

    final stopwatch = Stopwatch()..start();
    int totalOps = 0;

    var currentImage = _imageData;

    for (int iter = 0; iter < iterations; iter++) {
      cancellationToken?.throwIfCancelled();

      // Step 1: Gamma correction with HDR tone mapping
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.1) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: HDR tone mapping...',
        ),
      );
      currentImage = await _hdrToneMapping(
        currentImage,
        width,
        height,
        cancellationToken,
            (ops) => totalOps += ops,
      );

      // Step 2: Bilateral filter (edge-preserving blur)
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.3) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: Bilateral filter...',
        ),
      );
      currentImage = await _bilateralFilter(
        currentImage,
        width,
        height,
        cancellationToken,
            (ops) => totalOps += ops,
      );

      // Step 3: Unsharp masking for edge enhancement
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.5) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: Unsharp masking...',
        ),
      );
      currentImage = await _unsharpMask(
        currentImage,
        width,
        height,
        cancellationToken,
            (ops) => totalOps += ops,
      );

      // Step 4: Histogram equalization
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.7) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: Histogram equalization...',
        ),
      );
      currentImage = await _histogramEqualization(
        currentImage,
        width,
        height,
        cancellationToken,
            (ops) => totalOps += ops,
      );

      // Step 5: Simple Gaussian blur (replaces NLM for stability)
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.9) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: Gaussian blur...',
        ),
      );
      currentImage = await _gaussianBlur5x5Full(
        currentImage,
        width,
        height,
        cancellationToken,
            (ops) => totalOps += ops,
      );
    }

    stopwatch.stop();

    final elapsedSeconds = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2);
    final opsPerSec = _formatNumber((totalOps / stopwatch.elapsedMilliseconds * 1000).round());

    sendProgress?.call(
      TaskProgress(
        percentage: 1.0,
        message: 'Pipeline complete in ${elapsedSeconds}s',
      ),
    );

    return '''
Image Processing Pipeline Complete
Resolution: ${width}x$height (${_formatNumber(totalPixels)} pixels)
Iterations: $iterations
Total Operations: ${_formatNumber(totalOps)}
Time: ${elapsedSeconds}s
Throughput: $opsPerSec ops/sec
Pipeline: HDR → Bilateral → Unsharp → Histogram → Gaussian
''';
  }

  /// HDR tone mapping with gamma correction
  /// Expensive: 6 exp/pow operations per pixel
  Future<Uint8List> _hdrToneMapping(
      Uint8List data,
      int width,
      int height,
      CancellationToken? token,
      void Function(int) addOps,
      ) async {
    final result = Uint8List(width * height * 3);
    final gamma = 2.2;
    final exposure = 1.2;

    for (int i = 0; i < width * height; i++) {
      token?.throwIfCancelled();

      final pixelIndex = i * 3;
      final r = data[pixelIndex] / 255.0;
      final g = data[pixelIndex + 1] / 255.0;
      final b = data[pixelIndex + 2] / 255.0;

      // Apply exposure and gamma (Reinhard tone mapping)
      final rTone = 1 - math.exp(-r * exposure);
      final gTone = 1 - math.exp(-g * exposure);
      final bTone = 1 - math.exp(-b * exposure);

      result[pixelIndex] = (math.pow(rTone, 1 / gamma) * 255).clamp(0, 255).toInt();
      result[pixelIndex + 1] = (math.pow(gTone, 1 / gamma) * 255).clamp(0, 255).toInt();
      result[pixelIndex + 2] = (math.pow(bTone, 1 / gamma) * 255).clamp(0, 255).toInt();
    }

    addOps(width * height * 15); // 15 ops per pixel
    return result;
  }

  /// Bilateral filter - edge-preserving smoothing
  /// VERY expensive: O(width × height × kernel²)
  Future<Uint8List> _bilateralFilter(
      Uint8List data,
      int width,
      int height,
      CancellationToken? token,
      void Function(int) addOps,
      ) async {
    final result = Uint8List.fromList(data); // Copy input as fallback
    final kernelSize = 5;
    final halfKernel = kernelSize ~/ 2;
    final sigmaSpatial = 3.0;
    final sigmaRange = 50.0;

    for (int y = halfKernel; y < height - halfKernel; y++) {
      token?.throwIfCancelled();

      for (int x = halfKernel; x < width - halfKernel; x++) {
        token?.throwIfCancelled();

        final centerIdx = (y * width + x) * 3;

        double sumR = 0, sumG = 0, sumB = 0, sumWeight = 0;

        // Iterate through kernel
        for (int ky = -halfKernel; ky <= halfKernel; ky++) {
          token?.throwIfCancelled();

          for (int kx = -halfKernel; kx <= halfKernel; kx++) {
            token?.throwIfCancelled();

            final ny = y + ky;
            final nx = x + kx;

            // Bounds check
            if (ny < 0 || ny >= height || nx < 0 || nx >= width) continue;

            final idx = (ny * width + nx) * 3;

            // Spatial weight
            final spatialDist = math.sqrt(kx * kx + ky * ky);
            final spatialWeight = math.exp(-(spatialDist * spatialDist) / (2 * sigmaSpatial * sigmaSpatial));

            // Range weight
            final rDiff = data[centerIdx] - data[idx];
            final gDiff = data[centerIdx + 1] - data[idx + 1];
            final bDiff = data[centerIdx + 2] - data[idx + 2];
            final rangeDist = math.sqrt(rDiff * rDiff + gDiff * gDiff + bDiff * bDiff);
            final rangeWeight = math.exp(-(rangeDist * rangeDist) / (2 * sigmaRange * sigmaRange));

            final weight = spatialWeight * rangeWeight;
            sumWeight += weight;
            sumR += data[idx] * weight;
            sumG += data[idx + 1] * weight;
            sumB += data[idx + 2] * weight;
          }
        }

        if (sumWeight > 0) {
          result[centerIdx] = (sumR / sumWeight).clamp(0, 255).toInt();
          result[centerIdx + 1] = (sumG / sumWeight).clamp(0, 255).toInt();
          result[centerIdx + 2] = (sumB / sumWeight).clamp(0, 255).toInt();
        }
      }
    }

    addOps(width * height * kernelSize * kernelSize * 20); // ~500 ops per pixel!
    return result;
  }

  /// Unsharp masking for edge enhancement
  Future<Uint8List> _unsharpMask(
      Uint8List data,
      int width,
      int height,
      CancellationToken? token,
      void Function(int) addOps,
      ) async {
    // First, create blurred version (5x5 Gaussian)
    final blurred = await _gaussianBlur5x5(data, width, height, token);

    final result = Uint8List(width * height * 3);
    final amount = 1.5; // Sharpening strength

    for (int i = 0; i < width * height * 3; i++) {
      token?.throwIfCancelled();
      final original = data[i];
      final blur = blurred[i];
      final sharp = original + amount * (original - blur);
      result[i] = sharp.clamp(0, 255).toInt();
    }

    addOps(width * height * 30); // Gaussian + subtraction
    return result;
  }

  /// 5x5 Gaussian blur helper (with bounds checking)
  Future<Uint8List> _gaussianBlur5x5(
      Uint8List data,
      int width,
      int height,
      CancellationToken? token,
      ) async {
    final result = Uint8List.fromList(data); // Copy input
    final kernel = [
      1, 4, 6, 4, 1,
      4, 16, 24, 16, 4,
      6, 24, 36, 24, 6,
      4, 16, 24, 16, 4,
      1, 4, 6, 4, 1,
    ];
    final kernelSum = 256;

    for (int y = 2; y < height - 2; y++) {
      token?.throwIfCancelled();
      for (int x = 2; x < width - 2; x++) {
        token?.throwIfCancelled();

        int sumR = 0, sumG = 0, sumB = 0;

        for (int ky = -2; ky <= 2; ky++) {
          token?.throwIfCancelled();

          for (int kx = -2; kx <= 2; kx++) {
            token?.throwIfCancelled();

            final ny = y + ky;
            final nx = x + kx;

            // Bounds check
            if (ny < 0 || ny >= height || nx < 0 || nx >= width) continue;

            final idx = (ny * width + nx) * 3;
            final kernelIdx = (ky + 2) * 5 + (kx + 2);
            sumR += data[idx] * kernel[kernelIdx];
            sumG += data[idx + 1] * kernel[kernelIdx];
            sumB += data[idx + 2] * kernel[kernelIdx];
          }
        }

        final outIdx = (y * width + x) * 3;
        result[outIdx] = sumR ~/ kernelSum;
        result[outIdx + 1] = sumG ~/ kernelSum;
        result[outIdx + 2] = sumB ~/ kernelSum;
      }
    }

    return result;
  }

  /// Full 5x5 Gaussian blur as standalone step
  Future<Uint8List> _gaussianBlur5x5Full(
      Uint8List data,
      int width,
      int height,
      CancellationToken? token,
      void Function(int) addOps,
      ) async {
    final result = await _gaussianBlur5x5(data, width, height, token);
    addOps(width * height * 25); // 25 ops per pixel
    return result;
  }

  /// Histogram equalization for contrast enhancement
  Future<Uint8List> _histogramEqualization(
      Uint8List data,
      int width,
      int height,
      CancellationToken? token,
      void Function(int) addOps,
      ) async {
    final result = Uint8List(width * height * 3);

    // Process each channel separately
    for (int channel = 0; channel < 3; channel++) {
      token?.throwIfCancelled();

      // Build histogram
      final histogram = List<int>.filled(256, 0);
      for (int i = 0; i < width * height; i++) {
        token?.throwIfCancelled();

        final pixelIdx = i * 3 + channel;
        if (pixelIdx < data.length) {
          histogram[data[pixelIdx]]++;
        }
      }

      // Build cumulative distribution
      final cdf = List<int>.filled(256, 0);
      cdf[0] = histogram[0];
      for (int i = 1; i < 256; i++) {
        cdf[i] = cdf[i - 1] + histogram[i];
      }

      // Normalize and create lookup table
      final totalPixels = width * height;
      final lut = List<int>.filled(256, 0);
      for (int i = 0; i < 256; i++) {
        lut[i] = ((cdf[i] * 255) / totalPixels).round();
      }

      // Apply equalization
      for (int i = 0; i < width * height; i++) {
        final pixelIdx = i * 3 + channel;
        if (pixelIdx < data.length && pixelIdx < result.length) {
          result[pixelIdx] = lut[data[pixelIdx]];
        }
      }
    }

    addOps(width * height * 10);
    return result;
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