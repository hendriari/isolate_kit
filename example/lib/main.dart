import 'dart:isolate';

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
  int _result = 0;
  double _progress = 0.0;
  String _status = 'Ready';
  bool _isProcessing = false;
  TaskHandle<int>? _currentTask;

  @override
  void initState() {
    super.initState();
    _initializeIsolateKit();
  }

  void _initializeIsolateKit() {
    // Create task registry with global registration
    final registry = getTaskRegistry();

    // Initialize IsolateKit
    _isolateKit = IsolateKit.instance(
      name: 'demo',
      taskRegistry: registry,
      maxConcurrentTasks: 2,
      usePool: true,
      poolSize: 2,
      debugName: 'DemoIsolateKit',
    );

    // Optional: Warmup for better performance
    _isolateKit.warmup();
  }

  void _runHeavyTask() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _status = 'Starting...';
      _progress = 0.0;
      _result = 0;
    });

    final task = HeavyComputationTask({'iterations': 1000000});

    _currentTask = _isolateKit.runTask(
      task,
      timeout: const Duration(seconds: 30),
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
        _result = result;
        _status = 'Completed!';
        _progress = 1.0;
        _isProcessing = false;
      });
    } on TaskCancelledException {
      setState(() {
        _status = 'Cancelled';
        _isProcessing = false;
      });
    } on TaskTimeoutException {
      setState(() {
        _status = 'Timeout!';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isProcessing = false;
      });
    }
  }

  void _runFibonacci() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _status = 'Calculating Fibonacci...';
      _progress = 0.0;
      _result = 0;
    });

    final task = FibonacciTask({'n': 40});

    _currentTask = _isolateKit.runTask(
      task,
      timeout: const Duration(seconds: 30),
      onProgress: (progress) {
        setState(() {
          _progress = progress.percentage;
          _status = progress.message ?? 'Calculating...';
        });
      },
    );

    try {
      final result = await _currentTask!.future;
      setState(() {
        _result = result;
        _status = 'Fibonacci completed!';
        _progress = 1.0;
        _isProcessing = false;
      });
    } on TaskCancelledException {
      setState(() {
        _status = 'Cancelled';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isProcessing = false;
      });
    }
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
              Text('Pool Status:', style: Theme.of(context).textTheme.titleSmall),
              Text('  Workers: ${status['poolStatus']?['poolSize'] ?? 'N/A'}'),
              Text('  Total Active: ${status['poolStatus']?['totalActive'] ?? 'N/A'}'),
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
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                'Run heavy computation in background',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),

              // Result display
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Result:',
                      style: TextStyle(fontSize: 14),
                    ),
                    Text(
                      '$_result',
                      style: Theme.of(context).textTheme.headlineLarge,
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
              ),

              const SizedBox(height: 32),

              // Action buttons
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _runHeavyTask,
                    icon: const Icon(Icons.calculate),
                    label: const Text('Heavy Task'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _runFibonacci,
                    icon: const Icon(Icons.functions),
                    label: const Text('Fibonacci'),
                  ),
                  if (_isProcessing)
                    ElevatedButton.icon(
                      onPressed: _cancelTask,
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancel'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 24),

              const Text(
                'Try scrolling while task is running!\nUI stays responsive.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================= GLOBAL TASK REGISTRY =======================

/// Global task registry that can be accessed from any isolate
IsolateTaskRegistry getTaskRegistry() {
  final registry = IsolateTaskRegistry();

  // Register tasks with top-level or static factory functions
  registry.register<HeavyComputationTask>(
    'HeavyComputationTask',
    _createHeavyComputationTask,
  );

  registry.register<FibonacciTask>(
    'FibonacciTask',
    _createFibonacciTask,
  );

  return registry;
}

// Top-level factory functions (can be sent to isolates)
HeavyComputationTask _createHeavyComputationTask(
    Map<String, dynamic> payload,
    List<TransferableTypedData>? transferables,
    ) {
  return HeavyComputationTask(payload);
}

FibonacciTask _createFibonacciTask(
    Map<String, dynamic> payload,
    List<TransferableTypedData>? transferables,
    ) {
  return FibonacciTask(payload);
}

// ======================= TASK IMPLEMENTATIONS =======================

/// Heavy computation task example
class HeavyComputationTask extends IsolateTask<Map<String, dynamic>, int> {
  final Map<String, dynamic> _payload;

  HeavyComputationTask(this._payload);

  @override
  Map<String, dynamic> get command => _payload;

  @override
  Map<String, dynamic> get payload => _payload;

  @override
  String get taskType => 'HeavyComputationTask';

  @override
  int get priority => TaskPriority.high;

  @override
  Future<int> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final iterations = _payload['iterations'] as int;
    int result = 0;
    final progressInterval = iterations ~/ 100; // Report progress 100 times

    for (int i = 0; i < iterations; i++) {
      // Check for cancellation
      cancellationToken?.throwIfCancelled();

      // Heavy computation
      result += (i * 2) % 1000000;

      // Report progress periodically
      if (i % progressInterval == 0) {
        sendProgress?.call(TaskProgress(
          percentage: i / iterations,
          message: 'Processing ${(i / iterations * 100).toStringAsFixed(1)}%',
          data: {'current': i, 'total': iterations},
        ));
      }
    }

    // Final progress
    sendProgress?.call(TaskProgress(
      percentage: 1.0,
      message: 'Complete!',
    ));

    return result;
  }

  @override
  Duration? get estimatedDuration => const Duration(seconds: 10);
}

/// Fibonacci calculation task example
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
  int get priority => TaskPriority.normal;

  @override
  Future<int> execute({
    void Function(TaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final n = _payload['n'] as int;

    sendProgress?.call(TaskProgress(
      percentage: 0.0,
      message: 'Starting Fibonacci calculation...',
    ));

    final result = await _fibonacci(n, sendProgress, cancellationToken);

    sendProgress?.call(TaskProgress(
      percentage: 1.0,
      message: 'Fibonacci calculation complete!',
    ));

    return result;
  }

  Future<int> _fibonacci(
      int n,
      void Function(TaskProgress)? sendProgress,
      CancellationToken? cancellationToken,
      ) async {
    cancellationToken?.throwIfCancelled();

    if (n <= 1) return n;

    // Report progress based on depth
    final progress = 1.0 - (n / _payload['n'] as int);
    if (progress > 0 && progress % 0.1 < 0.01) {
      sendProgress?.call(TaskProgress(
        percentage: progress,
        message: 'Calculating fib($n)...',
      ));
    }

    return await _fibonacci(n - 1, sendProgress, cancellationToken) +
        await _fibonacci(n - 2, sendProgress, cancellationToken);
  }

  @override
  Duration? get estimatedDuration => const Duration(seconds: 15);
}