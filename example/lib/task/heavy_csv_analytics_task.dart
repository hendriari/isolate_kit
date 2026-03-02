import 'dart:math' as math;
import 'package:isolate_kit/isolate_kit.dart';

/// Heavy CSV analytics with complex computations
/// Performs statistical analysis, pattern matching, and data transformations
class HeavyCsvAnalyticsTask extends IsolateTask<String, String> {
  final Map<String, dynamic> _payload;

  HeavyCsvAnalyticsTask(this._payload);

  // @override
  // int get priority => TaskPriority.high; [DEFAULT PRIORITY: NORMAL]
  @override
  String get command => '';
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'HeavyCsvAnalyticsTask';

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final rows = _payload['rows'] as int? ?? 100000;
    final iterations = _payload['iterations'] as int? ?? 5;

    sendProgress?.call(
      TaskProgress(percentage: 0.0, message: 'Generating synthetic data...'),
    );

    final stopwatch = Stopwatch()..start();
    int totalOps = 0;

    // Generate realistic dataset with complex patterns
    final data = _generateComplexDataset(rows);
    totalOps += rows * 10;

    sendProgress?.call(
      TaskProgress(percentage: 0.1, message: 'Generated $rows rows'),
    );

    final analytics = <String, dynamic>{};

    for (int iter = 0; iter < iterations; iter++) {
      cancellationToken?.throwIfCancelled();

      // 1. Statistical analysis
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.2) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: Statistical analysis...',
        ),
      );
      final stats = await _computeStatistics(data, cancellationToken);
      totalOps += rows * 50;
      analytics['stats_iter_$iter'] = stats;

      // 2. Correlation matrix
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.4) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: Correlation analysis...',
        ),
      );
      final correlations = await _computeCorrelations(data, cancellationToken);
      totalOps += rows * rows ~/ 1000; // O(n²) but sampled
      analytics['correlations_iter_$iter'] = correlations;

      // 3. Clustering analysis
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.6) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: K-means clustering...',
        ),
      );
      final clusters = await _kMeansClustering(data, 5, cancellationToken);
      totalOps += rows * 100; // Multiple iterations
      analytics['clusters_iter_$iter'] = clusters;

      // 4. Outlier detection
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.8) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: Outlier detection...',
        ),
      );
      final outliers = await _detectOutliers(data, cancellationToken);
      totalOps += rows * 30;
      analytics['outliers_iter_$iter'] = outliers;

      // 5. Pattern recognition
      sendProgress?.call(
        TaskProgress(
          percentage: (iter + 0.95) / iterations,
          message: 'Iteration ${iter + 1}/$iterations: Pattern recognition...',
        ),
      );
      final patterns = await _recognizePatterns(data, cancellationToken);
      totalOps += rows * 40;
      analytics['patterns_iter_$iter'] = patterns;
    }

    stopwatch.stop();

    final elapsedSeconds = (stopwatch.elapsedMilliseconds / 1000)
        .toStringAsFixed(2);
    final opsPerSec = _formatNumber(
      (totalOps / stopwatch.elapsedMilliseconds * 1000).round(),
    );

    sendProgress?.call(
      TaskProgress(percentage: 1.0, message: 'Analytics complete!'),
    );

    return '''
CSV Analytics Complete
Dataset: ${_formatNumber(rows)} rows
Iterations: $iterations
Analyses: Stats, Correlation, Clustering, Outliers, Patterns
Total Operations: ${_formatNumber(totalOps)}
Time: ${elapsedSeconds}s
Throughput: $opsPerSec ops/sec
Outliers Found: ${analytics['outliers_iter_0']?['count'] ?? 0}
Clusters: 5 groups identified
''';
  }

  /// Generate complex synthetic dataset with realistic patterns
  List<Map<String, double>> _generateComplexDataset(int rows) {
    final random = math.Random(42);
    final data = <Map<String, double>>[];

    for (int i = 0; i < rows; i++) {
      // Generate correlated features with noise
      final baseValue = random.nextDouble() * 100;

      data.add({
        'feature1': baseValue + random.nextGaussian() * 10,
        'feature2': baseValue * 0.8 + random.nextGaussian() * 15,
        'feature3': baseValue * 1.2 + random.nextGaussian() * 20,
        'feature4': random.nextDouble() * 50, // Independent
        'feature5':
            math.sin(i / 100) * 30 + random.nextGaussian() * 5, // Periodic
      });
    }

    return data;
  }

  /// Compute comprehensive statistics
  /// Includes: mean, median, std, skewness, kurtosis
  Future<Map<String, Map<String, double>>> _computeStatistics(
    List<Map<String, double>> data,
    CancellationToken? token,
  ) async {
    final stats = <String, Map<String, double>>{};
    final features = data.first.keys.toList();

    for (final feature in features) {
      token?.throwIfCancelled();

      final values = data.map((row) => row[feature]!).toList();
      values.sort();

      // Mean
      final mean = values.reduce((a, b) => a + b) / values.length;

      // Variance & Std Dev
      final variance =
          values.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) /
          values.length;
      final stdDev = math.sqrt(variance);

      // Median
      final median = values.length % 2 == 0
          ? (values[values.length ~/ 2 - 1] + values[values.length ~/ 2]) / 2
          : values[values.length ~/ 2];

      // Skewness (measure of asymmetry)
      final skewness =
          values
              .map((x) => math.pow((x - mean) / stdDev, 3))
              .reduce((a, b) => a + b) /
          values.length;

      // Kurtosis (measure of tail heaviness)
      final kurtosis =
          values
                  .map((x) => math.pow((x - mean) / stdDev, 4))
                  .reduce((a, b) => a + b) /
              values.length -
          3;

      stats[feature] = {
        'mean': mean,
        'median': median,
        'std': stdDev,
        'min': values.first,
        'max': values.last,
        'skewness': skewness,
        'kurtosis': kurtosis,
      };
    }

    return stats;
  }

  /// Compute correlation matrix between features
  /// O(n × m²) where m = number of features
  Future<Map<String, double>> _computeCorrelations(
    List<Map<String, double>> data,
    CancellationToken? token,
  ) async {
    final features = data.first.keys.toList();
    final correlations = <String, double>{};

    for (int i = 0; i < features.length; i++) {
      for (int j = i + 1; j < features.length; j++) {
        token?.throwIfCancelled();

        final f1 = features[i];
        final f2 = features[j];

        // Pearson correlation coefficient
        final x = data.map((row) => row[f1]!).toList();
        final y = data.map((row) => row[f2]!).toList();

        final meanX = x.reduce((a, b) => a + b) / x.length;
        final meanY = y.reduce((a, b) => a + b) / y.length;

        double numerator = 0;
        double denomX = 0;
        double denomY = 0;

        for (int k = 0; k < x.length; k++) {
          final dx = x[k] - meanX;
          final dy = y[k] - meanY;
          numerator += dx * dy;
          denomX += dx * dx;
          denomY += dy * dy;
        }

        final correlation = numerator / math.sqrt(denomX * denomY);
        correlations['${f1}_$f2'] = correlation;
      }
    }

    return correlations;
  }

  /// K-means clustering
  /// Expensive iterative algorithm: O(k × n × iterations)
  Future<Map<String, dynamic>> _kMeansClustering(
    List<Map<String, double>> data,
    int k,
    CancellationToken? token,
  ) async {
    final features = data.first.keys.toList();
    final random = math.Random(42);

    // Initialize centroids randomly
    var centroids = List.generate(
      k,
      (_) => features.map((f) => random.nextDouble() * 100).toList(),
    );

    final maxIterations = 20;
    for (int iter = 0; iter < maxIterations; iter++) {
      token?.throwIfCancelled();

      // Assign points to nearest centroid
      final clusters = List.generate(k, (_) => <List<double>>[]);

      for (final row in data) {
        final point = features.map((f) => row[f]!).toList();
        var minDist = double.infinity;
        var nearestCluster = 0;

        for (int c = 0; c < k; c++) {
          final dist = _euclideanDistance(point, centroids[c]);
          if (dist < minDist) {
            minDist = dist;
            nearestCluster = c;
          }
        }

        clusters[nearestCluster].add(point);
      }

      // Update centroids
      final newCentroids = <List<double>>[];
      for (final cluster in clusters) {
        if (cluster.isEmpty) {
          newCentroids.add(centroids[newCentroids.length]);
          continue;
        }

        final centroid = <double>[];
        for (int f = 0; f < features.length; f++) {
          final mean =
              cluster.map((p) => p[f]).reduce((a, b) => a + b) / cluster.length;
          centroid.add(mean);
        }
        newCentroids.add(centroid);
      }

      centroids = newCentroids;
    }

    // Compute cluster sizes
    final clusterSizes = <int>[];
    for (final row in data) {
      final point = features.map((f) => row[f]!).toList();
      var nearestCluster = 0;
      var minDist = double.infinity;

      for (int c = 0; c < k; c++) {
        final dist = _euclideanDistance(point, centroids[c]);
        if (dist < minDist) {
          minDist = dist;
          nearestCluster = c;
        }
      }

      if (clusterSizes.length <= nearestCluster) {
        clusterSizes.addAll(
          List.filled(nearestCluster - clusterSizes.length + 1, 0),
        );
      }
      clusterSizes[nearestCluster]++;
    }

    return {'k': k, 'iterations': maxIterations, 'cluster_sizes': clusterSizes};
  }

  /// Detect outliers using IQR method
  Future<Map<String, dynamic>> _detectOutliers(
    List<Map<String, double>> data,
    CancellationToken? token,
  ) async {
    final features = data.first.keys.toList();
    int outlierCount = 0;

    for (final feature in features) {
      token?.throwIfCancelled();

      final values = data.map((row) => row[feature]!).toList();
      values.sort();

      final q1 = values[values.length ~/ 4];
      final q3 = values[3 * values.length ~/ 4];
      final iqr = q3 - q1;
      final lowerBound = q1 - 1.5 * iqr;
      final upperBound = q3 + 1.5 * iqr;

      outlierCount += values
          .where((v) => v < lowerBound || v > upperBound)
          .length;
    }

    return {
      'count': outlierCount,
      'percentage': (outlierCount / (data.length * features.length) * 100)
          .toStringAsFixed(2),
    };
  }

  /// Pattern recognition using autocorrelation
  Future<Map<String, dynamic>> _recognizePatterns(
    List<Map<String, double>> data,
    CancellationToken? token,
  ) async {
    final features = data.first.keys.toList();
    final patterns = <String, bool>{};

    for (final feature in features) {
      token?.throwIfCancelled();

      final values = data.map((row) => row[feature]!).toList();

      // Check for periodicity using autocorrelation
      bool isPeriodic = false;
      final lag = values.length ~/ 10;

      if (lag > 0) {
        final autocorr = _autocorrelation(values, lag);
        isPeriodic = autocorr.abs() > 0.7; // Strong correlation
      }

      patterns['${feature}_periodic'] = isPeriodic;
    }

    return {
      'periodic_features': patterns.values.where((v) => v).length,
      'details': patterns,
    };
  }

  double _euclideanDistance(List<double> a, List<double> b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      sum += math.pow(a[i] - b[i], 2);
    }
    return math.sqrt(sum);
  }

  double _autocorrelation(List<double> values, int lag) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    double numerator = 0;
    double denominator = 0;

    for (int i = 0; i < values.length - lag; i++) {
      numerator += (values[i] - mean) * (values[i + lag] - mean);
    }

    for (final value in values) {
      denominator += math.pow(value - mean, 2);
    }

    return numerator / denominator;
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

// Extension for Gaussian random
extension on math.Random {
  double nextGaussian() {
    final u1 = nextDouble();
    final u2 = nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
