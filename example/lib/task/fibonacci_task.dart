import 'package:isolate_kit/isolate_kit.dart';

/// Fibonacci calculation task using matrix exponentiation
/// Time complexity: O(log n) per calculation, but repeated many times for sustained CPU load
class FibonacciTask extends IsolateTask<Map<String, dynamic>, String> {
  final Map<String, dynamic> _payload;
  FibonacciTask(this._payload);

  // @override
  // int get priority => TaskPriority.high; [DEFAULT PRIORITY: NORMAL]
  @override
  Map<String, dynamic> get command => _payload;
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'FibonacciTask';

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final n = _payload['n'] as int? ?? 1000000;
    final iterations = _payload['iterations'] as int? ?? 100;
    final useBigInt = _payload['use_bigint'] as bool? ?? false;

    sendProgress?.call(
      TaskProgress(
        percentage: 0.0,
        message: 'Starting Fibonacci benchmark...',
      ),
    );

    final stopwatch = Stopwatch()..start();
    dynamic lastResult;
    int totalOperations = 0;

    if (useBigInt) {
      lastResult = await _computeWithBigInt(
        n,
        iterations,
        sendProgress,
        cancellationToken,
            (ops) => totalOperations = ops,
      );
    } else {
      lastResult = await _computeWithModulo(
        n,
        iterations,
        sendProgress,
        cancellationToken,
            (ops) => totalOperations = ops,
      );
    }

    stopwatch.stop();

    // Format results for better readability
    final elapsedSeconds = (stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2);
    final opsPerSec = _formatNumber((totalOperations / stopwatch.elapsedMilliseconds * 1000).round());

    sendProgress?.call(
      TaskProgress(
        percentage: 1.0,
        message: 'Completed in ${elapsedSeconds}s | $opsPerSec ops/sec',
      ),
    );

    return _generateSummary(
      n,
      iterations,
      useBigInt,
      lastResult,
      stopwatch.elapsedMilliseconds,
      totalOperations,
    );
  }

  /// Compute Fibonacci using BigInt for arbitrary precision
  /// Slower but accurate for very large numbers
  Future<BigInt> _computeWithBigInt(
      int n,
      int iterations,
      void Function(TaskProgress)? sendProgress,
      CancellationToken? cancellationToken,
      void Function(int) setOps,
      ) async {
    BigInt lastResult = BigInt.zero;
    int totalOps = 0;

    for (int iter = 0; iter < iterations; iter++) {
      cancellationToken?.throwIfCancelled();

      final result = _matrixPowerBigInt(n);
      lastResult = result;
      totalOps += _estimateOperations(n);

      // Report progress every 10% of iterations
      if ((iter + 1) % (iterations ~/ 10).clamp(1, iterations) == 0) {
        final progress = (iter + 1) / iterations;
        final digits = lastResult.toString().length;
        sendProgress?.call(
          TaskProgress(
            percentage: progress,
            message: 'BigInt [${iter + 1}/$iterations] → ${_formatNumber(digits)} digits',
          ),
        );
      }
    }

    setOps(totalOps);
    return lastResult;
  }

  /// Compute Fibonacci using modulo arithmetic
  /// Fast with limited but consistent results (prevents overflow)
  Future<int> _computeWithModulo(
      int n,
      int iterations,
      void Function(TaskProgress)? sendProgress,
      CancellationToken? cancellationToken,
      void Function(int) setOps,
      ) async {
    const int mod = 1000000007; // Prime modulo to prevent overflow
    int lastResult = 0;
    int totalOps = 0;

    for (int iter = 0; iter < iterations; iter++) {
      cancellationToken?.throwIfCancelled();

      final result = _matrixPowerMod(n, mod);
      lastResult = result;
      totalOps += _estimateOperations(n);

      // Report progress every 10% of iterations
      if ((iter + 1) % (iterations ~/ 10).clamp(1, iterations) == 0) {
        final progress = (iter + 1) / iterations;
        final percentage = (progress * 100).toStringAsFixed(0);
        sendProgress?.call(
          TaskProgress(
            percentage: progress,
            message: 'Modulo [$percentage%] → F($n) mod $mod',
          ),
        );
      }
    }

    setOps(totalOps);
    return lastResult;
  }

  /// Matrix exponentiation using BigInt
  /// Computes Fibonacci using the formula: F(n) = [[1,1],[1,0]]^n
  BigInt _matrixPowerBigInt(int exp) {
    if (exp == 0) return BigInt.zero;
    if (exp == 1) return BigInt.one;

    // Helper function to multiply two 2x2 matrices
    List<List<BigInt>> multiply(List<List<BigInt>> a, List<List<BigInt>> b) {
      return [
        [
          a[0][0] * b[0][0] + a[0][1] * b[1][0],
          a[0][0] * b[0][1] + a[0][1] * b[1][1],
        ],
        [
          a[1][0] * b[0][0] + a[1][1] * b[1][0],
          a[1][0] * b[0][1] + a[1][1] * b[1][1],
        ],
      ];
    }

    // Identity matrix
    var result = [
      [BigInt.one, BigInt.zero],
      [BigInt.zero, BigInt.one],
    ];

    // Base matrix for Fibonacci
    var power = [
      [BigInt.one, BigInt.one],
      [BigInt.one, BigInt.zero],
    ];

    // Binary exponentiation
    var n = exp;
    while (n > 0) {
      if (n & 1 == 1) {
        result = multiply(result, power);
      }
      power = multiply(power, power);
      n >>= 1;
    }

    return result[0][1];
  }

  /// Matrix exponentiation using modulo arithmetic
  /// Same algorithm as BigInt version but with modulo to prevent overflow
  int _matrixPowerMod(int exp, int mod) {
    if (exp == 0) return 0;
    if (exp == 1) return 1;

    // Helper function to multiply two 2x2 matrices with modulo
    List<List<int>> multiply(List<List<int>> a, List<List<int>> b) {
      return [
        [
          (a[0][0] * b[0][0] + a[0][1] * b[1][0]) % mod,
          (a[0][0] * b[0][1] + a[0][1] * b[1][1]) % mod,
        ],
        [
          (a[1][0] * b[0][0] + a[1][1] * b[1][0]) % mod,
          (a[1][0] * b[0][1] + a[1][1] * b[1][1]) % mod,
        ],
      ];
    }

    // Identity matrix
    var result = [
      [1, 0],
      [0, 1],
    ];

    // Base matrix for Fibonacci
    var power = [
      [1, 1],
      [1, 0],
    ];

    // Binary exponentiation
    var n = exp;
    while (n > 0) {
      if (n & 1 == 1) {
        result = multiply(result, power);
      }
      power = multiply(power, power);
      n >>= 1;
    }

    return result[0][1];
  }

  /// Estimate the number of mathematical operations performed
  /// Used for calculating throughput metrics
  int _estimateOperations(int n) {
    // Binary exponentiation performs ~log2(n) matrix multiplications
    // Each 2x2 matrix multiplication: 8 multiplications + 4 additions = 12 ops
    final matrixMults = (n.bitLength * 12).toInt();
    return matrixMults;
  }

  /// Format large numbers with thousand separators for readability
  /// Example: 1234567 → "1,234,567"
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

  /// Generate a human-readable summary of the benchmark results
  String _generateSummary(
      int n,
      int iterations,
      bool useBigInt,
      dynamic result,
      int elapsedMs,
      int totalOps,
      ) {
    final mode = useBigInt ? 'BigInt' : 'Modulo';
    final time = (elapsedMs / 1000).toStringAsFixed(2);
    final ops = _formatNumber((totalOps / elapsedMs * 1000).round());
    final resultStr = result.toString();
    final resultInfo = useBigInt
        ? '${_formatNumber(resultStr.length)} digits'
        : 'F($n) mod 1000000007 = $result';

    return '''
Mode: $mode
Input: F($n) × $iterations iterations
Time: ${time}s
Throughput: $ops ops/sec
Result: $resultInfo
''';
  }
}