import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:isolate_kit/isolate_kit.dart';
import 'package:crypto/crypto.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IsolateKit Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'IsolateKit Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final IsolateKit _isolateKit;
  String _result = 'Ready';
  double _progress = 0.0;
  String _status = 'Ready';
  bool _isProcessing = false;
  TaskHandle? _currentTask;

  @override
  void initState() {
    super.initState();
    _initializeIsolateKit();
  }

  void _initializeIsolateKit() {
    final registry = getTaskRegistry();

    _isolateKit = IsolateKit.instance(
      name: 'demo',
      taskRegistry: registry,
      maxConcurrentTasks: 2,
      usePool: true,
      poolSize: 2,
      debugName: 'DemoIsolateKit',
    );

    _isolateKit.warmup();
  }

  void _runTask(IsolateTask task, String taskName) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _status = 'Starting $taskName...';
      _progress = 0.0;
      _result = 'Processing...';
    });

    _currentTask = _isolateKit.runTask(
      task,
      timeout: const Duration(seconds: 60),
      onProgress: (progress) {
        setState(() {
          _progress = progress.percentage;
          _status = progress.message ?? 'Processing...';
        });
      },
    );

    try {
      final result = await _currentTask!.future;
      setState(() {
        _result = result.toString();
        _status = '$taskName completed!';
        _progress = 1.0;
        _isProcessing = false;
      });
    } on TaskCancelledException {
      setState(() {
        _status = 'Cancelled';
        _result = 'Task was cancelled';
        _isProcessing = false;
      });
    } on TaskTimeoutException {
      setState(() {
        _status = 'Timeout!';
        _result = 'Task timed out';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _result = 'Error occurred';
        _isProcessing = false;
      });
    }
  }

  void _runImageGrayscale() {
    // Create a dummy 1920x1080 RGB image
    final imageData = Uint8List(1920 * 1080 * 3);
    for (int i = 0; i < imageData.length; i++) {
      imageData[i] = (i % 256);
    }

    final task = ImageGrayscaleTask({
      'width': 1920,
      'height': 1080,
    }, imageData);

    _runTask(task, 'Image Grayscale');
  }

  void _runImageResize() {
    // Create a dummy 1920x1080 RGBA image
    final imageData = Uint8List(1920 * 1080 * 4);
    for (int i = 0; i < imageData.length; i++) {
      imageData[i] = (i % 256);
    }

    final task = ImageResizeTask({
      'sourceWidth': 1920,
      'sourceHeight': 1080,
      'targetWidth': 640,
      'targetHeight': 360,
    }, imageData);

    _runTask(task, 'Image Resize');
  }

  void _runCsvParser() {
    // DON'T generate CSV in UI thread!
    // Pass only parameters, generate inside isolate
    final task = CsvChunkParserTask({
      'rows': 500000,  // Generate 500k rows in isolate
      'chunkSize': 10000,
    });

    _runTask(task, 'CSV Parser (500k rows)');
  }

  void _runFileHash() {
    // Generate 200MB file for real heavy computation
    final sizeMB = 200;
    final fileData = Uint8List(sizeMB * 1024 * 1024);
    for (int i = 0; i < fileData.length; i++) {
      fileData[i] = (i % 256);
    }

    final task = FileChunkHashTask({
      'chunkSize': 4 * 1024 * 1024, // 4MB chunks
      'passes': 3, // 3 full passes
    }, fileData);

    _runTask(task, 'SHA-256 File Hash (Real Crypto)');
  }

  void _runBatchNormalize() {
    // Generate dummy data
    final data = List.generate(100000, (i) => (i % 1000).toDouble());

    final task = BatchNormalizeTask({
      'batchSize': 1000,
      'data': data,
    });

    _runTask(task, 'Batch Normalize');
  }

  void _runFibonacci() {
    final task = FibonacciTask({
      'n': 1000000,
      'repeats': 200,
    });
    _runTask(task, 'Matrix Fibonacci (Heavy)');
  }

  void _cancelTask() {
    _currentTask?.cancel();
  }

  void _showStatus() {
    final status = _isolateKit.getStatus();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('IsolateKit Status'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Active Tasks: ${status['activeTasks']}'),
              Text('Queued Tasks: ${status['queuedTasks']}'),
              Text('Total Completed: ${status['totalCompleted']}'),
              Text('Warmed Up: ${status['warmedUp']}'),
              Text('Use Pool: ${status['usePool']}'),
              const SizedBox(height: 8),
              Text('Pool Status:',
                  style: Theme.of(context).textTheme.titleSmall),
              Text('  Workers: ${status['poolStatus']?['poolSize'] ?? 'N/A'}'),
              Text(
                  '  Total Active: ${status['poolStatus']?['totalActive'] ?? 'N/A'}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isolateKit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showStatus,
            tooltip: 'Show Status',
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                'Heavy Background Tasks Demo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Result display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text('Result:', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    Text(
                      _result,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Progress indicator
              if (_isProcessing) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
              ],

              // Status text
              Text(
                _status,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Math Tasks
              _buildSectionTitle(context, 'Math Tasks'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildTaskButton(
                    'Fibonacci',
                    Icons.functions,
                    _runFibonacci,
                  ),
                  _buildTaskButton(
                    'Normalize Data',
                    Icons.analytics,
                    _runBatchNormalize,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Image Processing Tasks
              _buildSectionTitle(context, 'Image Processing'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildTaskButton(
                    'Grayscale',
                    Icons.image,
                    _runImageGrayscale,
                  ),
                  _buildTaskButton(
                    'Resize',
                    Icons.photo_size_select_large,
                    _runImageResize,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Data Processing Tasks
              _buildSectionTitle(context, 'Data Processing'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildTaskButton(
                    'Parse CSV',
                    Icons.table_chart,
                    _runCsvParser,
                  ),
                  _buildTaskButton(
                    'Hash File',
                    Icons.fingerprint,
                    _runFileHash,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              if (_isProcessing)
                ElevatedButton.icon(
                  onPressed: _cancelTask,
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel Task'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),

              const SizedBox(height: 24),

              const Text(
                'Monitor the indicators below while the task is in progress!\nUI stays responsive.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),


              const SizedBox(height: 32),

              CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildTaskButton(String label, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: _isProcessing ? null : onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}

// ======================= GLOBAL TASK REGISTRY =======================

IsolateTaskRegistry getTaskRegistry() {
  final registry = IsolateTaskRegistry();

  registry.register<FibonacciTask>(
    'FibonacciTask',
    _createFibonacciTask,
  );

  registry.register<ImageGrayscaleTask>(
    'ImageGrayscaleTask',
    _createImageGrayscaleTask,
  );

  registry.register<ImageResizeTask>(
    'ImageResizeTask',
    _createImageResizeTask,
  );

  registry.register<CsvChunkParserTask>(
    'CsvChunkParserTask',
    _createCsvChunkParserTask,
  );

  registry.register<FileChunkHashTask>(
    'FileChunkHashTask',
    _createFileChunkHashTask,
  );

  registry.register<BatchNormalizeTask>(
    'BatchNormalizeTask',
    _createBatchNormalizeTask,
  );

  return registry;
}

// Factory functions
FibonacciTask _createFibonacciTask(
    Map<String, dynamic> payload,
    List<TransferableTypedData>? transferables,
    ) {
  return FibonacciTask(payload);
}

ImageGrayscaleTask _createImageGrayscaleTask(
    Map<String, dynamic> payload,
    List<TransferableTypedData>? transferables,
    ) {
  final imageData = transferables != null && transferables.isNotEmpty
      ? transferables[0].materialize().asUint8List()
      : Uint8List(0);
  return ImageGrayscaleTask(payload, imageData);
}

ImageResizeTask _createImageResizeTask(
    Map<String, dynamic> payload,
    List<TransferableTypedData>? transferables,
    ) {
  final imageData = transferables != null && transferables.isNotEmpty
      ? transferables[0].materialize().asUint8List()
      : Uint8List(0);
  return ImageResizeTask(payload, imageData);
}

CsvChunkParserTask _createCsvChunkParserTask(
    Map<String, dynamic> payload,
    List<TransferableTypedData>? transferables,
    ) {
  return CsvChunkParserTask(payload);
}

FileChunkHashTask _createFileChunkHashTask(
    Map<String, dynamic> payload,
    List<TransferableTypedData>? transferables,
    ) {
  final fileData = transferables != null && transferables.isNotEmpty
      ? transferables[0].materialize().asUint8List()
      : Uint8List(0);
  return FileChunkHashTask(payload, fileData);
}

BatchNormalizeTask _createBatchNormalizeTask(
    Map<String, dynamic> payload,
    List<TransferableTypedData>? transferables,
    ) {
  return BatchNormalizeTask(payload);
}

// ======================= TASK IMPLEMENTATIONS =======================

/// Fibonacci calculation task
/// Matrix-based Fibonacci - O(log n) but repeated many times for heavy load
class FibonacciTask extends IsolateTask<Map<String, dynamic>, int> {
  final Map<String, dynamic> _payload;
  FibonacciTask(this._payload);

  @override
  Map<String, dynamic> get command => _payload;
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'FibonacciTask';

  @override
  Future<int> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final n = _payload['n'] as int? ?? 1000000; // Very large number
    final repeats = _payload['repeats'] as int? ?? 100; // Repeat calculation

    sendProgress?.call(TaskProgress(
      percentage: 0.0,
      message: 'Starting matrix exponentiation ($repeats passes)...',
    ));

    // Matrix multiplication helper
    List<List<int>> multiply(List<List<int>> a, List<List<int>> b) {
      return [
        [a[0][0] * b[0][0] + a[0][1] * b[1][0], a[0][0] * b[0][1] + a[0][1] * b[1][1]],
        [a[1][0] * b[0][0] + a[1][1] * b[1][0], a[1][0] * b[0][1] + a[1][1] * b[1][1]]
      ];
    }

    // Matrix power using binary exponentiation
    List<List<int>> matrixPower(List<List<int>> base, int exp) {
      var result = [[1, 0], [0, 1]]; // Identity matrix
      var power = base;

      while (exp > 0) {
        cancellationToken?.throwIfCancelled();
        if (exp & 1 == 1) {
          result = multiply(result, power);
        }
        power = multiply(power, power);
        exp >>= 1;
      }
      return result;
    }

    final baseMatrix = [[1, 1], [1, 0]];
    int lastResult = 0;

    // Perform multiple passes to create sustained CPU load
    for (int i = 0; i < repeats; i++) {
      cancellationToken?.throwIfCancelled();

      final result = matrixPower(baseMatrix, n ~/ repeats);
      lastResult = result[0][0];

      sendProgress?.call(TaskProgress(
        percentage: (i + 1) / repeats,
        message: 'Matrix pass ${i + 1}/$repeats',
      ));
    }

    sendProgress?.call(TaskProgress(
      percentage: 1.0,
      message: 'Matrix exponentiation complete!',
    ));

    return lastResult;
  }
}

/// Image Grayscale Conversion Task
class ImageGrayscaleTask extends IsolateTask<Uint8List, String> {
  final Map<String, dynamic> _payload;
  final Uint8List _imageData;

  ImageGrayscaleTask(this._payload, this._imageData);

  @override
  Uint8List get command => _imageData;
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'ImageGrayscaleTask';
  @override
  List<TransferableTypedData>? get transferables =>
      [TransferableTypedData.fromList([_imageData])];

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final width = _payload['width'] as int;
    final height = _payload['height'] as int;
    final totalPixels = width * height;

    // Step 1: Grayscale conversion with gamma correction
    final grayscale = Uint8List(totalPixels);

    for (int i = 0; i < totalPixels; i++) {
      cancellationToken?.throwIfCancelled();

      final pixelIndex = i * 3;
      final r = _imageData[pixelIndex] / 255.0;
      final g = _imageData[pixelIndex + 1] / 255.0;
      final b = _imageData[pixelIndex + 2] / 255.0;

      // Apply gamma correction (heavy floating-point ops)
      final gamma = 2.2;
      final rLinear = math.pow(r, gamma);
      final gLinear = math.pow(g, gamma);
      final bLinear = math.pow(b, gamma);

      // Weighted grayscale
      final gray = 0.299 * rLinear + 0.587 * gLinear + 0.114 * bLinear;
      grayscale[i] = (gray * 255).clamp(0, 255).toInt();

      if (i % 50000 == 0) {
        sendProgress?.call(TaskProgress(
          percentage: i / totalPixels * 0.6,
          message: 'Grayscale with gamma: ${(i / totalPixels * 100).toStringAsFixed(1)}%',
        ));
      }
    }

    // Step 2: Apply Gaussian blur (3x3 convolution - HEAVY!)
    final blurred = Uint8List(totalPixels);
    final kernel = [
      1, 2, 1,
      2, 4, 2,
      1, 2, 1
    ];
    final kernelSum = 16;

    for (int y = 1; y < height - 1; y++) {
      cancellationToken?.throwIfCancelled();

      for (int x = 1; x < width - 1; x++) {
        int sum = 0;

        // Apply 3x3 kernel
        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final idx = (y + ky) * width + (x + kx);
            final kernelIdx = (ky + 1) * 3 + (kx + 1);
            sum += grayscale[idx] * kernel[kernelIdx];
          }
        }

        blurred[y * width + x] = (sum ~/ kernelSum);
      }

      if (y % 50 == 0) {
        sendProgress?.call(TaskProgress(
          percentage: 0.6 + (y / height * 0.4),
          message: 'Applying blur: row $y/$height',
        ));
      }
    }

    sendProgress?.call(TaskProgress(
      percentage: 1.0,
      message: 'Grayscale + blur complete!',
    ));

    return 'Processed ${width}x$height with gamma correction + Gaussian blur (${blurred.length} bytes)';
  }
}

/// Image Resize Task (Nearest Neighbor)
class ImageResizeTask extends IsolateTask<Uint8List, String> {
  final Map<String, dynamic> _payload;
  final Uint8List _imageData;

  ImageResizeTask(this._payload, this._imageData);

  @override
  Uint8List get command => _imageData;

  @override
  Map<String, dynamic> get payload => _payload;

  @override
  String get taskType => 'ImageResizeTask';

  @override
  List<TransferableTypedData>? get transferables =>
      [TransferableTypedData.fromList([_imageData])];

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final srcWidth = _payload['sourceWidth'] as int;
    final srcHeight = _payload['sourceHeight'] as int;
    final dstWidth = _payload['targetWidth'] as int;
    final dstHeight = _payload['targetHeight'] as int;

    sendProgress?.call(TaskProgress(
      percentage: 0.0,
      message: 'Resizing image...',
    ));

    final output = Uint8List(dstWidth * dstHeight * 4);
    final xRatio = srcWidth / dstWidth;
    final yRatio = srcHeight / dstHeight;

    for (int y = 0; y < dstHeight; y++) {
      cancellationToken?.throwIfCancelled();

      for (int x = 0; x < dstWidth; x++) {
        final srcX = (x * xRatio).floor();
        final srcY = (y * yRatio).floor();

        final srcIndex = (srcY * srcWidth + srcX) * 4;
        final dstIndex = (y * dstWidth + x) * 4;

        output[dstIndex] = _imageData[srcIndex];
        output[dstIndex + 1] = _imageData[srcIndex + 1];
        output[dstIndex + 2] = _imageData[srcIndex + 2];
        output[dstIndex + 3] = _imageData[srcIndex + 3];
      }

      if (y % 10 == 0) {
        sendProgress?.call(TaskProgress(
          percentage: y / dstHeight,
          message: 'Processing row $y/$dstHeight',
        ));
      }
    }

    sendProgress?.call(TaskProgress(
      percentage: 1.0,
      message: 'Resize complete!',
    ));

    return 'Resized from ${srcWidth}x$srcHeight to ${dstWidth}x$dstHeight';
  }
}

/// CSV Chunk Parser Task
class CsvChunkParserTask extends IsolateTask<String, String> {
  final Map<String, dynamic> _payload;

  CsvChunkParserTask(this._payload);

  @override
  String get command => ''; // No command needed
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'CsvChunkParserTask';

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final rows = _payload['rows'] as int? ?? 100000;
    final chunkSize = _payload['chunkSize'] as int;

    sendProgress?.call(TaskProgress(
      percentage: 0.0,
      message: 'Generating CSV data in isolate...',
    ));

    // Generate CSV INSIDE isolate (not in UI!)
    final csvLines = <String>['id,name,age,score,email,city,country'];

    for (int i = 0; i < rows; i++) {
      cancellationToken?.throwIfCancelled();

      csvLines.add('$i,User$i,${20 + (i % 50)},${i % 100},user$i@example.com,City${i % 100},Country${i % 20}');

      if (i % chunkSize == 0 && i > 0) {
        sendProgress?.call(TaskProgress(
          percentage: i / rows * 0.5,
          message: 'Generated $i/$rows rows',
        ));
      }
    }

    // Heavy parsing work
    final results = <Map<String, String>>[];
    final headers = csvLines[0].split(',');

    for (int i = 1; i < csvLines.length; i++) {
      cancellationToken?.throwIfCancelled();

      final values = csvLines[i].split(',');
      final row = <String, String>{};

      for (int j = 0; j < headers.length && j < values.length; j++) {
        row[headers[j]] = values[j];
      }

      results.add(row);

      if (i % chunkSize == 0) {
        sendProgress?.call(TaskProgress(
          percentage: 0.5 + (i / csvLines.length * 0.5),
          message: 'Parsed ${results.length}/${csvLines.length - 1} rows',
        ));
      }
    }

    sendProgress?.call(TaskProgress(
      percentage: 1.0,
      message: 'CSV parsing complete!',
    ));

    return 'Parsed ${results.length} rows from CSV (${csvLines.length - 1} total)';
  }
}

/// File Chunk Hash Task
class FileChunkHashTask extends IsolateTask<Uint8List, String> {
  final Map<String, dynamic> _payload;
  final Uint8List _fileData;

  FileChunkHashTask(this._payload, this._fileData);

  @override
  Uint8List get command => _fileData;
  @override
  Map<String, dynamic> get payload => _payload;
  @override
  String get taskType => 'FileChunkHashTask';
  @override
  List<TransferableTypedData>? get transferables =>
      [TransferableTypedData.fromList([_fileData])];

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final chunkSize = _payload['chunkSize'] as int;
    final passes = _payload['passes'] as int? ?? 3;
    final totalChunks = (_fileData.length / chunkSize).ceil();

    sendProgress?.call(TaskProgress(
      percentage: 0.0,
      message: 'Starting SHA-256 hashing ($passes passes)...',
    ));

    final hashes = <String>[];

    // Perform multiple passes for heavier computation
    for (int pass = 0; pass < passes; pass++) {
      cancellationToken?.throwIfCancelled();

      // Simple approach: hash the entire data each pass
      // For chunked processing, we'll process in chunks but still compute full hash
      final chunks = <List<int>>[];

      for (int i = 0; i < totalChunks; i++) {
        cancellationToken?.throwIfCancelled();

        final start = i * chunkSize;
        final end = math.min(start + chunkSize, _fileData.length);
        chunks.add(_fileData.sublist(start, end));

        if (i % 10 == 0) {
          sendProgress?.call(TaskProgress(
            percentage: (pass + (i / totalChunks)) / passes,
            message: 'Pass ${pass + 1}/$passes - Chunk ${i + 1}/$totalChunks',
          ));
        }
      }

      // Compute SHA-256 hash of all chunks combined
      final digest = sha256.convert(_fileData);
      hashes.add(digest.toString());

      sendProgress?.call(TaskProgress(
        percentage: (pass + 1) / passes,
        message: 'Pass ${pass + 1}/$passes completed',
      ));
    }

    sendProgress?.call(TaskProgress(
      percentage: 1.0,
      message: 'SHA-256 hashing complete!',
    ));

    return 'SHA-256 hash (${_fileData.length} bytes, $passes passes):\n${hashes.first.substring(0, 32)}...';
  }
}

/// Batch Normalize Task
class BatchNormalizeTask extends IsolateTask<List<double>, String> {
  final Map<String, dynamic> _payload;

  BatchNormalizeTask(this._payload);

  @override
  List<double> get command => _payload['data'] as List<double>;

  @override
  Map<String, dynamic> get payload => _payload;

  @override
  String get taskType => 'BatchNormalizeTask';

  @override
  Future<String> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final data = _payload['data'] as List<double>;
    final batchSize = _payload['batchSize'] as int;
    final totalBatches = (data.length / batchSize).ceil();

    sendProgress?.call(TaskProgress(
      percentage: 0.0,
      message: 'Normalizing data...',
    ));

    final normalized = <double>[];

    for (int i = 0; i < totalBatches; i++) {
      cancellationToken?.throwIfCancelled();

      final start = i * batchSize;
      final end = math.min(start + batchSize, data.length);
      final batch = data.sublist(start, end);

      // Calculate mean
      final mean = batch.reduce((a, b) => a + b) / batch.length;

      // Calculate standard deviation
      final variance =
          batch.map((x) => math.pow(x - mean, 2)).reduce((a, b) => a + b) /
              batch.length;
      final stdDev = math.sqrt(variance);

      // Normalize
      for (final value in batch) {
        normalized.add((value - mean) / (stdDev + 1e-8));
      }

      sendProgress?.call(TaskProgress(
        percentage: (i + 1) / totalBatches,
        message: 'Normalized batch ${i + 1}/$totalBatches',
      ));
    }

    sendProgress?.call(TaskProgress(
      percentage: 1.0,
      message: 'Normalization complete!',
    ));

    return 'Normalized ${normalized.length} values in $totalBatches batches (mean ≈ 0, std ≈ 1)';
  }
}