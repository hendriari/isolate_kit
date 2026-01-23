import 'dart:typed_data';

import 'package:example/task/fibonacci_task.dart';
import 'package:example/task/heavy_csv_analytics_task.dart';
import 'package:example/task/heavy_file_crypto_task.dart';
import 'package:example/task/heavy_image_processing_task.dart';
import 'package:example/task/heavy_image_resize_task.dart';
import 'package:example/task/heavy_normalize_data_task.dart';
import 'package:example/task_register.dart';
import 'package:flutter/material.dart';
import 'package:isolate_kit/isolate_kit.dart';

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
  int _activeTaskCount = 0;
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
    setState(() {
      _activeTaskCount++;
      _isProcessing = true;
      _status = 'Starting $taskName...';
      _progress = 0.0;
      _result = 'Processing...';
    });

    final handle = _isolateKit.runTask(
      task,
      timeout: const Duration(minutes: 5),
      onProgress: (progress) {
        setState(() {
          _progress = progress.percentage;
          _status = progress.message ?? 'Processing...';
        });
      },
    );

    _currentTask = handle;

    try {
      final result = await _currentTask!.future;
      setState(() {
        _result = result.toString();
        _status = '$taskName completed!';
        _progress = 1.0;
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
    } finally {
      if (mounted) {
        setState(() {
          _activeTaskCount--;
          _isProcessing = _activeTaskCount > 0;
          if (!_isProcessing) {
            _status = 'All tasks finished!';
          }
        });
      }
    }
  }

  void _runImageProcessing() {
    // Create a dummy 1920x1080 RGB image
    final imageData = Uint8List(1920 * 1080 * 3);
    for (int i = 0; i < imageData.length; i++) {
      imageData[i] = (i % 256);
    }

    final task = HeavyImageProcessingTask({
      'width': 1920,
      'height': 1080,
    }, imageData);

    _runTask(task, 'Image Processing');
  }

  void _runImageResize() {
    final imageData = Uint8List(8000 * 6000 * 4);
    for (int i = 0; i < imageData.length; i++) {
      imageData[i] = (i % 256);
    }

    final task = HeavyImageResizeTask({
      'sourceWidth': 8000,
      'sourceHeight': 6000,
      'targetWidth': 3840,
      'targetHeight': 2160,
      'method': 'lanczos3',
    }, imageData);

    _runTask(task, 'Image Resize');
  }

  void _runCsvAnalytics() {
    // DON'T generate CSV in UI thread!
    // Pass only parameters, generate inside isolate
    final task = HeavyCsvAnalyticsTask({'rows': 100000, 'iterations': 5});

    _runTask(task, 'CSV Analytics (100k rows)');
  }

  void _runFileCrypto() {
    final sizeMB = 200;
    final fileData = Uint8List(sizeMB * 1024 * 1024);
    for (int i = 0; i < fileData.length; i++) {
      fileData[i] = (i % 256);
    }

    final task = HeavyFileCryptoTask({
      'chunkSize': 4 * 1024 * 1024,
      'iterations': 5000,
      'algorithms': ['sha256', 'sha512', 'hmac'],
    }, fileData);

    _runTask(task, 'SHA-256 File Hash (Real Crypto)');
  }

  void _runNormalizeData() {
    final task = HeavyNormalizeDataTask({
      'dataSize': 50000,
      'iterations': 50,
      'transformations': 5,
    });

    _runTask(task, 'Batch Normalize');
  }

  void _runFibonacci() {
    final task = FibonacciTask({
      'n': 100000,
      'iterations': 200,
      'use_bigint': true,
    });
    _runTask(task, 'Matrix Fibonacci (Heavy)');
  }

  void _cancelTask() async {
    setState(() {
      _status = 'process cancellation';
    });
    await _currentTask?.cancel();
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
              Text(
                'Pool Status:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text('  Workers: ${status['poolStatus']?['poolSize'] ?? 'N/A'}'),
              Text(
                '  Total Active: ${status['poolStatus']?['totalActive'] ?? 'N/A'}',
              ),
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
          // Show status button
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

              const SizedBox(height: 16),

              Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Active Task count: $_activeTaskCount',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 20),

              // Math Tasks
              _buildSectionTitle(context, 'Math Tasks'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  // Fibonacci Task
                  _buildTaskButton('Fibonacci', Icons.functions, _runFibonacci),

                  // Batch Normalize Task
                  _buildTaskButton(
                    'Normalize Data',
                    Icons.analytics,
                    _runNormalizeData,
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
                  // Grayscale Task
                  _buildTaskButton(
                    'Image Processing',
                    Icons.image,
                    _runImageProcessing,
                  ),

                  // Resize Image Task
                  _buildTaskButton(
                    'Image Resize',
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
                  // Parse CSV Task
                  _buildTaskButton(
                    'CSV Analytics',
                    Icons.table_chart,
                    _runCsvAnalytics,
                  ),

                  // Hash File Task
                  _buildTaskButton(
                    'Hash File',
                    Icons.fingerprint,
                    _runFileCrypto,
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
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTaskButton(String label, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      // onPressed: _isProcessing ? null : onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
