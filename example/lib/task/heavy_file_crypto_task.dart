import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:isolate_kit/isolate_kit.dart';

/// Heavy file cryptographic processing task
/// Performs multiple cryptographic operations: hashing, HMAC, PBKDF2-like derivation
class HeavyFileCryptoTask extends IsolateTask<Uint8List, String> {
  final Map<String, dynamic> _payload;
  final Uint8List _fileData;

  HeavyFileCryptoTask(this._payload, this._fileData);

  @override
  int get priority => TaskPriority.critical; // [DEFAULT PRIORITY: NORMAL]
  @override
  Uint8List get command => _fileData;
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'HeavyFileCryptoTask';
  @override
  List<TransferableTypedData>? get transferables => [
    TransferableTypedData.fromList([_fileData]),
  ];

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final chunkSize = _payload['chunkSize'] as int? ?? 4 * 1024 * 1024; // 4MB
    final iterations = _payload['iterations'] as int? ?? 1000;
    final algorithms =
        _payload['algorithms'] as List<String>? ?? ['sha256', 'sha512', 'hmac'];

    sendProgress?.call(
      TaskProgress(
        percentage: 0.0,
        message: 'Starting cryptographic processing...',
      ),
    );

    final stopwatch = Stopwatch()..start();
    int totalOps = 0;
    final results = <String, String>{};

    // Step 1: Merkle tree hash (chunk-by-chunk)
    sendProgress?.call(
      TaskProgress(percentage: 0.1, message: 'Computing Merkle tree hash...'),
    );
    final merkleRoot = await _computeMerkleTree(
      _fileData,
      chunkSize,
      sendProgress,
      cancellationToken,
      (ops) => totalOps += ops,
    );
    results['merkle_root'] = merkleRoot;

    // Step 2: Progressive hashing with multiple algorithms
    var progress = 0.2;
    for (final algo in algorithms) {
      cancellationToken?.throwIfCancelled();

      sendProgress?.call(
        TaskProgress(
          percentage: progress,
          message: 'Computing ${algo.toUpperCase()} hash...',
        ),
      );

      switch (algo) {
        case 'sha256':
          final hash = await _computeChunkedHash(
            _fileData,
            chunkSize,
            (data) => sha256.convert(data),
            cancellationToken,
            (ops) => totalOps += ops,
          );
          results['sha256'] = hash;
          break;

        case 'sha512':
          final hash = await _computeChunkedHash(
            _fileData,
            chunkSize,
            (data) => sha512.convert(data),
            cancellationToken,
            (ops) => totalOps += ops,
          );
          results['sha512'] = hash;
          break;

        case 'hmac':
          final hmacKey = List<int>.generate(32, (i) => i);
          final hash = await _computeHMAC(
            _fileData,
            hmacKey,
            chunkSize,
            cancellationToken,
            (ops) => totalOps += ops,
          );
          results['hmac_sha256'] = hash;
          break;
      }

      progress += 0.3 / algorithms.length;
    }

    // Step 3: PBKDF2-like key derivation (VERY EXPENSIVE)
    sendProgress?.call(
      TaskProgress(
        percentage: 0.5,
        message: 'Deriving cryptographic keys ($iterations iterations)...',
      ),
    );
    final derivedKey = await _pbkdf2Like(
      _fileData,
      iterations,
      sendProgress,
      cancellationToken,
      (ops) => totalOps += ops,
    );
    results['derived_key'] = derivedKey;

    // Step 4: Integrity verification
    sendProgress?.call(
      TaskProgress(percentage: 0.9, message: 'Verifying data integrity...'),
    );
    final checksum = await _computeChecksum(_fileData, cancellationToken);
    results['checksum'] = checksum;
    totalOps += _fileData.length;

    stopwatch.stop();

    final elapsedSeconds = (stopwatch.elapsedMilliseconds / 1000)
        .toStringAsFixed(2);
    final opsPerSec = _formatNumber(
      (totalOps / stopwatch.elapsedMilliseconds * 1000).round(),
    );
    final mbPerSec =
        (_fileData.length /
                (1024 * 1024) /
                (stopwatch.elapsedMilliseconds / 1000))
            .toStringAsFixed(2);

    sendProgress?.call(
      TaskProgress(
        percentage: 1.0,
        message: 'Cryptographic processing complete!',
      ),
    );

    return '''
Cryptographic Processing Complete
File Size: ${_formatBytes(_fileData.length)}
Algorithms: ${algorithms.join(', ').toUpperCase()}
Key Derivation Iterations: ${_formatNumber(iterations)}
Total Operations: ${_formatNumber(totalOps)}
Time: ${elapsedSeconds}s
Throughput: $mbPerSec MB/s, $opsPerSec ops/sec

Results:
SHA-256: ${results['sha256']?.substring(0, 16)}...
SHA-512: ${results['sha512']?.substring(0, 16)}...
HMAC: ${results['hmac_sha256']?.substring(0, 16)}...
Merkle Root: ${results['merkle_root']?.substring(0, 16)}...
Derived Key: ${results['derived_key']?.substring(0, 16)}...
Checksum: ${results['checksum']}
''';
  }

  /// Compute Merkle tree hash (binary tree of hashes)
  /// Very useful for verifying large files efficiently
  Future<String> _computeMerkleTree(
    Uint8List data,
    int chunkSize,
    void Function(TaskProgress)? sendProgress,
    CancellationToken? token,
    void Function(int) addOps,
  ) async {
    final totalChunks = (data.length / chunkSize).ceil();
    var hashes = <List<int>>[];

    // Leaf level: hash each chunk
    for (int i = 0; i < totalChunks; i++) {
      token?.throwIfCancelled();

      final start = i * chunkSize;
      final end = math.min(start + chunkSize, data.length);
      final chunk = data.sublist(start, end);
      final hash = sha256.convert(chunk).bytes;
      hashes.add(hash);

      addOps(chunk.length * 2); // Estimate: 2 ops per byte for hashing
    }

    // Build tree bottom-up
    while (hashes.length > 1) {
      token?.throwIfCancelled();

      final newLevel = <List<int>>[];
      for (int i = 0; i < hashes.length; i += 2) {
        if (i + 1 < hashes.length) {
          // Hash pair
          final combined = [...hashes[i], ...hashes[i + 1]];
          final hash = sha256.convert(combined).bytes;
          newLevel.add(hash);
          addOps(combined.length * 2);
        } else {
          // Odd node, promote as-is
          newLevel.add(hashes[i]);
        }
      }
      hashes = newLevel;
    }

    return hashes.first
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('');
  }

  /// Compute hash with chunked processing
  /// More memory efficient and allows progress reporting
  Future<String> _computeChunkedHash(
    Uint8List data,
    int chunkSize,
    Digest Function(List<int>) hashFunction,
    CancellationToken? token,
    void Function(int) addOps,
  ) async {
    final totalChunks = (data.length / chunkSize).ceil();
    final chunks = <List<int>>[];

    for (int i = 0; i < totalChunks; i++) {
      token?.throwIfCancelled();

      final start = i * chunkSize;
      final end = math.min(start + chunkSize, data.length);
      chunks.add(data.sublist(start, end));
    }

    // Hash all chunks combined
    final digest = hashFunction(data);
    addOps(data.length * 2); // ~2 ops per byte for crypto hash

    return digest.toString();
  }

  /// Compute HMAC (keyed hash)
  Future<String> _computeHMAC(
    Uint8List data,
    List<int> key,
    int chunkSize,
    CancellationToken? token,
    void Function(int) addOps,
  ) async {
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(data);

    addOps(data.length * 3); // HMAC is more expensive than plain hash

    return digest.toString();
  }

  /// PBKDF2-like key derivation
  /// EXTREMELY EXPENSIVE: Iterates hash thousands of times
  Future<String> _pbkdf2Like(
    Uint8List data,
    int iterations,
    void Function(TaskProgress)? sendProgress,
    CancellationToken? token,
    void Function(int) addOps,
  ) async {
    // Use a sample of the data as "password" for speed
    final password = data.length > 1024 ? data.sublist(0, 1024) : data;

    var derived = sha256.convert(password).bytes;

    for (int i = 0; i < iterations; i++) {
      token?.throwIfCancelled();

      // Iteratively hash
      derived = sha256.convert([...derived, ...password]).bytes;

      if (i % (iterations ~/ 10).clamp(1, iterations) == 0) {
        sendProgress?.call(
          TaskProgress(
            percentage: 0.5 + (i / iterations * 0.4),
            message: 'Key derivation: ${i + 1}/$iterations iterations',
          ),
        );
      }

      addOps(derived.length * 2);
    }

    return derived.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  /// Simple checksum for integrity verification
  Future<String> _computeChecksum(
    Uint8List data,
    CancellationToken? token,
  ) async {
    int checksum = 0;
    for (int i = 0; i < data.length; i++) {
      token?.throwIfCancelled();
      checksum = (checksum + data[i]) % 0xFFFFFFFF;
    }
    return checksum.toRadixString(16).padLeft(8, '0');
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
