import 'dart:math' as math;
import 'package:isolate_kit/isolate_kit.dart';

/// Heavy statistical processing task with multiple transformations
/// Simulates real ML pipeline preprocessing with sustained CPU load
class HeavyNormalizeDataTask extends IsolateTask<Map<String, dynamic>, String> {
  final Map<String, dynamic> _payload;

  HeavyNormalizeDataTask(this._payload);

  // @override
  // int get priority => TaskPriority.high; [DEFAULT PRIORITY: NORMAL]
  @override
  Map<String, dynamic> get command => _payload;
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'HeavyNormalizeDataTask';

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final dataSize = _payload['dataSize'] as int? ?? 100000;
    final iterations = _payload['iterations'] as int? ?? 100;
    final transformations = _payload['transformations'] as int? ?? 5;

    sendProgress?.call(
      TaskProgress(percentage: 0.0, message: 'Generating synthetic data...'),
    );

    final stopwatch = Stopwatch()..start();

    // Generate large dataset
    final data = _generateSyntheticData(dataSize);
    int totalOps = 0;

    for (int iter = 0; iter < iterations; iter++) {
      cancellationToken?.throwIfCancelled();

      var transformed = data;

      // Apply multiple heavy transformations
      for (int t = 0; t < transformations; t++) {
        cancellationToken?.throwIfCancelled();

        switch (t % 5) {
          case 0:
            transformed = _standardNormalization(transformed);
            totalOps += transformed.length * 10;
            break;
          case 1:
            transformed = _robustScaling(transformed);
            totalOps += transformed.length * 15;
            break;
          case 2:
            transformed = _powerTransform(transformed, 0.5);
            totalOps += transformed.length * 20;
            break;
          case 3:
            transformed = _winsorize(transformed, 0.05);
            totalOps += transformed.length * 12;
            break;
          case 4:
            transformed = _quantileTransform(transformed, 100);
            totalOps += transformed.length * 25;
            break;
        }

        // Report progress for transformations
        if ((t + 1) % math.max(1, transformations ~/ 5) == 0) {
          final iterProgress = iter / iterations;
          final transformProgress = (t + 1) / transformations / iterations;
          final totalProgress = iterProgress + transformProgress;

          sendProgress?.call(
            TaskProgress(
              percentage: totalProgress,
              message:
                  'Iteration ${iter + 1}/$iterations | Transform ${t + 1}/$transformations',
            ),
          );
        }
      }
    }

    stopwatch.stop();

    final elapsedSeconds = (stopwatch.elapsedMilliseconds / 1000)
        .toStringAsFixed(2);
    final opsPerSec = _formatNumber(
      (totalOps / stopwatch.elapsedMilliseconds * 1000).round(),
    );

    sendProgress?.call(
      TaskProgress(
        percentage: 1.0,
        message: 'Completed in ${elapsedSeconds}s | $opsPerSec ops/sec',
      ),
    );

    return '''
Mode: Multi-Transform Pipeline
Data Size: ${_formatNumber(dataSize)} samples
Iterations: $iterations
Transformations per Iteration: $transformations
Total Operations: ${_formatNumber(totalOps)}
Time: ${elapsedSeconds}s
Throughput: $opsPerSec ops/sec
''';
  }

  /// Generate synthetic data with realistic distribution
  List<double> _generateSyntheticData(int size) {
    final random = math.Random(42);
    return List.generate(size, (i) {
      // Mix of normal, uniform, and exponential distributions
      final normal = _boxMullerTransform(random);
      final uniform = random.nextDouble();
      final exponential = -math.log(random.nextDouble());
      return normal * 10 + uniform * 5 + exponential * 2;
    });
  }

  /// Box-Muller transform for generating normal distribution
  double _boxMullerTransform(math.Random random) {
    final u1 = random.nextDouble();
    final u2 = random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  /// Standard normalization (z-score)
  /// Transforms data to mean=0, std=1
  List<double> _standardNormalization(List<double> data) {
    final mean = data.reduce((a, b) => a + b) / data.length;
    final variance =
        data.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) /
        data.length;
    final stdDev = math.sqrt(variance);

    return data.map((x) => (x - mean) / (stdDev + 1e-8)).toList();
  }

  /// Robust scaling using median and IQR
  /// More resistant to outliers than standard normalization
  List<double> _robustScaling(List<double> data) {
    final sorted = List<double>.from(data)..sort();
    final median = _percentile(sorted, 50);
    final q1 = _percentile(sorted, 25);
    final q3 = _percentile(sorted, 75);
    final iqr = q3 - q1;

    return data.map((x) => (x - median) / (iqr + 1e-8)).toList();
  }

  /// Power transformation (Box-Cox style)
  /// Helps normalize skewed distributions
  List<double> _powerTransform(List<double> data, double lambda) {
    // Shift data to be positive
    final minVal = data.reduce(math.min);
    final shifted = minVal <= 0
        ? data.map((x) => x + (minVal.abs() + 1)).toList()
        : data;

    if (lambda.abs() < 1e-8) {
      // lambda ≈ 0: use log transform
      return shifted.map((x) => math.log(x + 1e-8)).toList();
    } else {
      // lambda != 0: use power transform
      return shifted.map((x) => (math.pow(x, lambda) - 1) / lambda).toList();
    }
  }

  /// Winsorization - cap extreme values at percentiles
  /// Reduces impact of outliers
  List<double> _winsorize(List<double> data, double fraction) {
    final sorted = List<double>.from(data)..sort();
    final lowerBound = _percentile(sorted, fraction * 100);
    final upperBound = _percentile(sorted, (1 - fraction) * 100);

    return data.map((x) {
      if (x < lowerBound) return lowerBound;
      if (x > upperBound) return upperBound;
      return x;
    }).toList();
  }

  /// Quantile transformation
  /// Maps data to uniform distribution using rank-based transformation
  List<double> _quantileTransform(List<double> data, int nQuantiles) {
    final sorted = List<double>.from(data)..sort();
    final quantiles = <double>[];

    // Calculate quantile boundaries
    for (int i = 0; i <= nQuantiles; i++) {
      final percentile = (i / nQuantiles) * 100;
      quantiles.add(_percentile(sorted, percentile));
    }

    // Map each value to its quantile
    return data.map((x) {
      for (int i = 0; i < quantiles.length - 1; i++) {
        if (x >= quantiles[i] && x <= quantiles[i + 1]) {
          return i / (quantiles.length - 1);
        }
      }
      return 1.0; // For values at or above max
    }).toList();
  }

  /// Calculate percentile of sorted data
  double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0.0;
    if (p <= 0) return sorted.first;
    if (p >= 100) return sorted.last;

    final index = (p / 100) * (sorted.length - 1);
    final lower = index.floor();
    final upper = index.ceil();

    if (lower == upper) return sorted[lower];

    final fraction = index - lower;
    return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
  }

  /// Format large numbers with thousand separators
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
