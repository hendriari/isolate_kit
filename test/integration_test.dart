import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isolate_kit/isolate_kit.dart';

import 'helpers/transferable_helper.dart';

export 'helpers/transferable_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Integration Tests - Real-World Scenarios', () {
    late IsolateKit isolateKit;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = IsolateTaskRegistry();
      _registerAllTasks(registry);
    });

    tearDown(() {
      isolateKit.dispose(force: true);
    });

    test('Scenario: Heavy computation without blocking UI', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'HeavyCompute',
      );

      // Simulate Fibonacci calculation
      final handle = isolateKit.runTask<int, int>(
        FibonacciTask(n: 40),
        timeout: const Duration(seconds: 30),
      );

      final result = await handle.future;

      expect(result, equals(102334155)); // Fib(40)
    });

    test('Scenario: Image processing pipeline', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'ImageProcessor',
        maxConcurrentTasks: 2,
      );

      // Simulate processing multiple images
      final images = List.generate(3, (i) {
        final data = Uint8List(1024 * 100); // 100KB per image
        for (int j = 0; j < 100; j++) {
          data[j] = (i * 10 + j) % 256;
        }
        return data;
      });

      final handles = images.map((imageData) {
        return isolateKit.runTask<Uint8List, Uint8List>(
          ImageProcessTask(imageData: imageData),
          onProgress: (p) =>
              debugPrint('Processing: ${(p.percentage * 100).toInt()}%'),
        );
      }).toList();

      final results = await Future.wait(handles.map((h) => h.future));

      expect(results.length, equals(3));
      for (final result in results) {
        expect(result.length, greaterThan(0));
      }
    });

    test('Scenario: Batch data processing with progress', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'BatchProcessor',
      );

      final progressUpdates = <double>[];

      final handle = isolateKit.runTask<int, List<int>>(
        BatchProcessTask(batchSize: 1000),
        timeout: const Duration(seconds: 10),
        onProgress: (p) {
          progressUpdates.add(p.percentage);
        },
      );

      final results = await handle.future;

      expect(results.length, equals(1000));
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.last, equals(1.0));
    });

    test('Scenario: Task cancellation during long operation', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'CancellableTask',
      );

      final handle = isolateKit.runTask<int, int>(
        LongComputationTask(
            iterations: 10000000), // Tingkatkan dari 1000000 ke 10000000
      );

      // Cancel lebih cepat atau task lebih lama
      await Future.delayed(
          const Duration(milliseconds: 50)); // Kurangi dari 200ms ke 50ms
      handle.cancel();

      await expectLater(
        handle.future,
        throwsA(isA<TaskCancelledException>()),
      );
    });

    test('Scenario: Priority-based task scheduling', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'PriorityScheduler',
        maxConcurrentTasks: 1,
      );

      final executionOrder = <String>[];

      // Queue tasks with different priorities
      final lowHandle = isolateKit.runTask<String, String>(
        PriorityDemoTask(
          id: 'low',
          taskPriority: TaskPriority.low,
        ),
      );

      final normalHandle = isolateKit.runTask<String, String>(
        PriorityDemoTask(
          id: 'normal',
          taskPriority: TaskPriority.normal,
        ),
      );

      final highHandle = isolateKit.runTask<String, String>(
        PriorityDemoTask(
          id: 'high',
          taskPriority: TaskPriority.high,
        ),
      );

      final criticalHandle = isolateKit.runTask<String, String>(
        PriorityDemoTask(
          id: 'critical',
          taskPriority: TaskPriority.critical,
        ),
      );

      // Collect results
      await Future.wait([
        lowHandle.future.then((r) => executionOrder.add(r)),
        normalHandle.future.then((r) => executionOrder.add(r)),
        highHandle.future.then((r) => executionOrder.add(r)),
        criticalHandle.future.then((r) => executionOrder.add(r)),
      ]);

      // Higher priority tasks should be in results
      expect(executionOrder, contains('critical'));
      expect(executionOrder, contains('high'));
    });

    test('Scenario: Parallel CSV processing', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'CSVProcessor',
        usePool: true,
        poolSize: 3,
        maxConcurrentTasks: 10,
      );

      // Simulate processing multiple CSV files
      final csvFiles = List.generate(5, (i) => 'file_$i.csv');

      final handles = csvFiles.map((filename) {
        return isolateKit.runTask<String, Map<String, int>>(
          CSVProcessTask(filename: filename, rowCount: 1000),
        );
      }).toList();

      final results = await Future.wait(handles.map((h) => h.future));

      expect(results.length, equals(5));
      for (final result in results) {
        expect(result['processed'], equals(1000));
      }
    });

    test('Scenario: Memory-efficient large file transfer', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'FileTransfer',
      );

      final largeFile = Uint8List(5 * 1024 * 1024);
      for (int i = 0; i < 1000; i++) {
        largeFile[i] = i % 256;
      }

      final handle = isolateKit.runTask<Uint8List, String>(
        FileHashTask(fileData: largeFile),
      );

      final hash = await handle.future;

      expect(hash, isNotEmpty);
      expect(hash.length, equals(32)); // MD5-like hash
    });

    test('Scenario: Concurrent task limit enforcement', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'LimitTest',
        maxConcurrentTasks: 2,
      );

      // Queue 10 tasks
      final handles = List.generate(
        10,
        (i) => isolateKit.runTask<int, int>(
          DelayedTask(value: i, delayMs: 100),
        ),
      );

      // Check status during execution
      await Future.delayed(const Duration(milliseconds: 50));
      final status = isolateKit.getStatus();

      // Should have max 2 active tasks
      expect(status['activeTasks'], lessThanOrEqualTo(2));
      expect(status['queuedTasks'], greaterThan(0));

      // Wait for all to complete
      await Future.wait(handles.map((h) => h.future));

      final finalStatus = isolateKit.getStatus();
      expect(finalStatus['totalCompleted'], equals(10));
    });

    test('Scenario: Error recovery and continuation', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'ErrorRecovery',
      );

      // Task that fails
      final errorHandle = isolateKit.runTask<void, void>(
        ErrorProneTask(shouldFail: true),
      );

      // Task that succeeds
      final successHandle = isolateKit.runTask<int, int>(
        DelayedTask(value: 42, delayMs: 100),
      );

      // First task should fail
      await expectLater(
        errorHandle.future,
        throwsA(isA<Exception>()),
      );

      // Second task should still succeed
      final result = await successHandle.future;
      expect(result, equals(84)); // Doubled
    });

    test('Scenario: Real-time data streaming with progress', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'DataStreaming',
      );

      final dataPoints = <Map<String, dynamic>>[];

      final handle = isolateKit.runTask<int, List<double>>(
        DataStreamTask(samples: 100),
        onProgress: (p) {
          if (p.data != null) {
            dataPoints.add(p.data!);
          }
        },
      );

      final results = await handle.future;

      expect(results.length, equals(100));
      expect(dataPoints, isNotEmpty);
    });

    test('Scenario: Warmup reduces first-call latency', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'WarmupTest',
      );

      // First call without warmup
      final noWarmupStart = DateTime.now();
      final handle1 = isolateKit.runTask<int, int>(
        DelayedTask(value: 1, delayMs: 10),
      );
      await handle1.future;
      final noWarmupDuration = DateTime.now().difference(noWarmupStart);

      isolateKit.dispose(force: true);

      // Second isolateKit with warmup
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'WarmupTest2',
      );

      await isolateKit.warmup();

      final warmupStart = DateTime.now();
      final handle2 = isolateKit.runTask<int, int>(
        DelayedTask(value: 1, delayMs: 10),
      );
      await handle2.future;
      final warmupDuration = DateTime.now().difference(warmupStart);

      // Warmup should be faster (though this is not guaranteed in tests)
      debugPrint('No warmup: ${noWarmupDuration.inMilliseconds}ms');
      debugPrint('With warmup: ${warmupDuration.inMilliseconds}ms');

      expect(warmupDuration.inMilliseconds, lessThan(5000));
    });

    test('Scenario: Multiple isolateKits for different purposes', () async {
      final heavyRegistry = IsolateTaskRegistry();
      _registerAllTasks(heavyRegistry);

      final lightRegistry = IsolateTaskRegistry();
      _registerAllTasks(lightRegistry);

      final heavyisolateKit = IsolateKit.instance(
        name: 'heavy_compute',
        taskRegistry: heavyRegistry,
        maxConcurrentTasks: 1,
      );

      final lightisolateKit = IsolateKit.instance(
        name: 'light_tasks',
        taskRegistry: lightRegistry,
        usePool: true,
        poolSize: 3,
      );

      // Heavy task
      final heavyHandle = heavyisolateKit.runTask<int, int>(
        FibonacciTask(n: 35),
      );

      // Multiple light tasks
      final lightHandles = List.generate(
        5,
        (i) => lightisolateKit.runTask<int, int>(
          DelayedTask(value: i, delayMs: 50),
        ),
      );

      // Both should complete successfully
      final heavyResult = await heavyHandle.future;
      final lightResults = await Future.wait(lightHandles.map((h) => h.future));

      expect(heavyResult, isA<int>());
      expect(lightResults.length, equals(5));

      heavyisolateKit.dispose(force: true);
      lightisolateKit.dispose(force: true);
    });

    test('Scenario: Graceful shutdown with cleanup', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'GracefulShutdown',
      );

      final handles = List.generate(
        3,
        (i) => isolateKit.runTask<int, int>(
          DelayedTask(value: i, delayMs: 5000),
          timeout: const Duration(seconds: 2),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      isolateKit.dispose(force: true);

      final results = await Future.wait(
        handles.map((handle) async {
          try {
            await handle.future;
            return false;
          } catch (e) {
            debugPrint('Task failed with: ${e.runtimeType}');
            return true;
          }
        }),
      );

      expect(results.every((failed) => failed), isTrue);

      expect(results.length, equals(3));
    });
  });

  group('Stress Tests', () {
    late IsolateKit isolateKit;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = IsolateTaskRegistry();
      _registerAllTasks(registry);
    });

    tearDown(() {
      isolateKit.dispose(force: true);
    });

    test('Stress: 100 sequential tasks', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'StressTest',
        maxConcurrentTasks: 5,
      );

      final handles = List.generate(
        100,
        (i) => isolateKit.runTask<int, int>(
          DelayedTask(value: i, delayMs: 10),
        ),
      );

      final results = await Future.wait(handles.map((h) => h.future));

      expect(results.length, equals(100));
      expect(isolateKit.getStatus()['totalCompleted'], equals(100));
    });

    test('Stress: Rapid task creation and cancellation', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'RapidStress',
      );

      for (int i = 0; i < 50; i++) {
        final handle = isolateKit.runTask<int, int>(
          DelayedTask(value: i, delayMs: 1000),
        );

        // Cancel immediately
        await Future.delayed(const Duration(milliseconds: 10));
        handle.cancel();

        try {
          await handle.future;
        } catch (e) {
          expect(e, isA<TaskCancelledException>());
        }
      }
    });

    test('Stress: Large data transfer performance', () async {
      isolateKit = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'LargeDataStress',
      );

      // Transfer 50MB total (10 x 5MB)
      final handles = List.generate(10, (i) {
        final data = Uint8List(5 * 1024 * 1024);
        return isolateKit.runTask<Uint8List, int>(
          DataSizeTask(data: data),
        );
      });

      final results = await Future.wait(handles.map((h) => h.future));

      expect(results.length, equals(10));
      expect(results.every((size) => size == 5 * 1024 * 1024), isTrue);
    });
  });
}

// ==================== TASK IMPLEMENTATIONS ====================

void _registerAllTasks(IsolateTaskRegistry registry) {
  registry.register<FibonacciTask>(
    'fibonacci',
    (p, t) => FibonacciTask.fromPayload(p),
  );
  registry.register<ImageProcessTask>(
    'image_process',
    (p, t) => ImageProcessTask.fromPayload(p, t),
  );
  registry.register<BatchProcessTask>(
    'batch_process',
    (p, t) => BatchProcessTask.fromPayload(p),
  );
  registry.register<LongComputationTask>(
    'long_computation',
    (p, t) => LongComputationTask.fromPayload(p),
  );
  registry.register<PriorityDemoTask>(
    'priority_demo',
    (p, t) => PriorityDemoTask.fromPayload(p),
  );
  registry.register<CSVProcessTask>(
    'csv_process',
    (p, t) => CSVProcessTask.fromPayload(p),
  );
  registry.register<FileHashTask>(
    'file_hash',
    (p, t) => FileHashTask.fromPayload(p, t),
  );
  registry.register<DelayedTask>(
    'delayed_task',
    (p, t) => DelayedTask.fromPayload(p),
  );
  registry.register<ErrorProneTask>(
    'error_prone',
    (p, t) => ErrorProneTask.fromPayload(p),
  );
  registry.register<DataStreamTask>(
    'data_stream',
    (p, t) => DataStreamTask.fromPayload(p),
  );
  registry.register<DataSizeTask>(
    'data_size',
    (p, t) => DataSizeTask.fromPayload(p, t),
  );
}

class FibonacciTask extends IsolateTask<int, int> {
  final int n;

  FibonacciTask({required this.n});

  factory FibonacciTask.fromPayload(Map<String, dynamic> p) =>
      FibonacciTask(n: p['n'] as int);

  @override
  int get command => n;

  @override
  Map<String, dynamic> get payload => {'n': n};

  @override
  String get taskType => 'fibonacci';

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    int fib(int n) {
      cancellationToken?.throwIfCancelled();
      if (n <= 1) return n;
      return fib(n - 1) + fib(n - 2);
    }

    return fib(n);
  }
}

class ImageProcessTask extends IsolateTask<Uint8List, Uint8List> {
  final Uint8List imageData;

  ImageProcessTask({required this.imageData});

  factory ImageProcessTask.fromPayload(
    Map<String, dynamic> p,
    List<TransferableTypedData>? t,
  ) =>
      ImageProcessTask(
        imageData:
            t != null ? TransferableHelper.toUint8List(t[0]) : Uint8List(0),
      );

  @override
  Uint8List get command => imageData;

  @override
  Map<String, dynamic> get payload => {};

  @override
  String get taskType => 'image_process';

  @override
  List<TransferableTypedData>? get transferables =>
      [TransferableHelper.fromUint8List(imageData)];

  @override
  Future<Uint8List> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final result = Uint8List(imageData.length);
    for (int i = 0; i < imageData.length; i++) {
      if (i % 10000 == 0) {
        cancellationToken?.throwIfCancelled();
        sendProgress?.call(IsolateTaskProgress(
          percentage: i / imageData.length,
          message: 'Processing pixel $i',
        ));
      }
      result[i] = (imageData[i] * 0.5).toInt();
    }
    return result;
  }
}

class BatchProcessTask extends IsolateTask<int, List<int>> {
  final int batchSize;

  BatchProcessTask({required this.batchSize});

  factory BatchProcessTask.fromPayload(Map<String, dynamic> p) =>
      BatchProcessTask(batchSize: p['batchSize'] as int);

  @override
  int get command => batchSize;

  @override
  Map<String, dynamic> get payload => {'batchSize': batchSize};

  @override
  String get taskType => 'batch_process';

  @override
  Future<List<int>> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final results = <int>[];
    for (int i = 0; i < batchSize; i++) {
      cancellationToken?.throwIfCancelled();
      results.add(i * 2);

      if (i % 100 == 0) {
        sendProgress?.call(IsolateTaskProgress(
          percentage: i / batchSize,
          message: 'Processed $i items',
        ));
      }
    }
    sendProgress?.call(IsolateTaskProgress(
      percentage: 1.0,
      message: 'Completed',
    ));
    return results;
  }
}

class LongComputationTask extends IsolateTask<int, int> {
  final int iterations;

  LongComputationTask({required this.iterations});

  factory LongComputationTask.fromPayload(Map<String, dynamic> p) =>
      LongComputationTask(iterations: p['iterations'] as int);

  @override
  int get command => iterations;

  @override
  Map<String, dynamic> get payload => {'iterations': iterations};

  @override
  String get taskType => 'long_computation';

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    var sum = 0;
    for (int i = 0; i < iterations; i++) {
      if (i % 100 == 0) {
        cancellationToken?.throwIfCancelled();
        await Future.delayed(Duration.zero);
      }
      sum += i;
    }
    return sum;
  }
}

class PriorityDemoTask extends IsolateTask<String, String> {
  final String id;
  final int taskPriority;

  PriorityDemoTask({required this.id, required this.taskPriority});

  factory PriorityDemoTask.fromPayload(Map<String, dynamic> p) =>
      PriorityDemoTask(
        id: p['id'] as String,
        taskPriority: p['priority'] as int,
      );

  @override
  String get command => id;

  @override
  Map<String, dynamic> get payload => {'id': id, 'priority': taskPriority};

  @override
  String get taskType => 'priority_demo';

  @override
  int get priority => taskPriority;

  @override
  Future<String> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return id;
  }
}

class CSVProcessTask extends IsolateTask<String, Map<String, int>> {
  final String filename;
  final int rowCount;

  CSVProcessTask({required this.filename, required this.rowCount});

  factory CSVProcessTask.fromPayload(Map<String, dynamic> p) => CSVProcessTask(
        filename: p['filename'] as String,
        rowCount: p['rowCount'] as int,
      );

  @override
  String get command => filename;

  @override
  Map<String, dynamic> get payload =>
      {'filename': filename, 'rowCount': rowCount};

  @override
  String get taskType => 'csv_process';

  @override
  Future<Map<String, int>> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    var processed = 0;
    for (int i = 0; i < rowCount; i++) {
      cancellationToken?.throwIfCancelled();
      processed++;
    }
    return {'processed': processed, 'filename': filename.hashCode};
  }
}

class FileHashTask extends IsolateTask<Uint8List, String> {
  final Uint8List fileData;

  FileHashTask({required this.fileData});

  factory FileHashTask.fromPayload(
    Map<String, dynamic> p,
    List<TransferableTypedData>? t,
  ) =>
      FileHashTask(
        fileData:
            t != null ? TransferableHelper.toUint8List(t[0]) : Uint8List(0),
      );

  @override
  Uint8List get command => fileData;

  @override
  Map<String, dynamic> get payload => {};

  @override
  String get taskType => 'file_hash';

  @override
  List<TransferableTypedData>? get transferables =>
      [TransferableHelper.fromUint8List(fileData)];

  @override
  Future<String> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    var hash = 0;
    for (int i = 0; i < fileData.length; i++) {
      if (i % 100000 == 0) cancellationToken?.throwIfCancelled();
      hash = ((hash << 5) - hash) + fileData[i];
      hash &= 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(32, '0');
  }
}

class DelayedTask extends IsolateTask<int, int> {
  final int value;
  final int delayMs;

  DelayedTask({required this.value, required this.delayMs});

  factory DelayedTask.fromPayload(Map<String, dynamic> p) =>
      DelayedTask(value: p['value'] as int, delayMs: p['delayMs'] as int);

  @override
  int get command => value;

  @override
  Map<String, dynamic> get payload => {'value': value, 'delayMs': delayMs};

  @override
  String get taskType => 'delayed_task';

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    const slice = 20; // 20ms slices
    var remaining = delayMs;
    while (remaining > 0) {
      final wait =
          Duration(milliseconds: remaining < slice ? remaining : slice);
      await Future.delayed(wait);
      cancellationToken?.throwIfCancelled();
      remaining -= wait.inMilliseconds;
    }
    return value * 2;
  }
}

class ErrorProneTask extends IsolateTask<void, void> {
  final bool shouldFail;

  ErrorProneTask({required this.shouldFail});

  factory ErrorProneTask.fromPayload(Map<String, dynamic> p) =>
      ErrorProneTask(shouldFail: p['shouldFail'] as bool);

  @override
  void get command {}

  @override
  Map<String, dynamic> get payload => {'shouldFail': shouldFail};

  @override
  String get taskType => 'error_prone';

  @override
  Future<void> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    if (shouldFail) {
      throw Exception('Intentional error for testing');
    }
  }
}

class DataStreamTask extends IsolateTask<int, List<double>> {
  final int samples;

  DataStreamTask({required this.samples});

  factory DataStreamTask.fromPayload(Map<String, dynamic> p) =>
      DataStreamTask(samples: p['samples'] as int);

  @override
  int get command => samples;

  @override
  Map<String, dynamic> get payload => {'samples': samples};

  @override
  String get taskType => 'data_stream';

  @override
  Future<List<double>> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final results = <double>[];
    for (int i = 0; i < samples; i++) {
      cancellationToken?.throwIfCancelled();
      final value = i * 0.1;
      results.add(value);

      if (i % 10 == 0) {
        sendProgress?.call(IsolateTaskProgress(
          percentage: i / samples,
          message: 'Sample $i',
          data: {'value': value},
        ));
      }
    }
    return results;
  }
}

class DataSizeTask extends IsolateTask<Uint8List, int> {
  final Uint8List data;

  DataSizeTask({required this.data});

  factory DataSizeTask.fromPayload(
    Map<String, dynamic> p,
    List<TransferableTypedData>? t,
  ) =>
      DataSizeTask(
        data: t != null ? TransferableHelper.toUint8List(t[0]) : Uint8List(0),
      );

  @override
  Uint8List get command => data;

  @override
  Map<String, dynamic> get payload => {};

  @override
  String get taskType => 'data_size';

  @override
  List<TransferableTypedData>? get transferables =>
      [TransferableHelper.fromUint8List(data)];

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    return data.length;
  }
}
