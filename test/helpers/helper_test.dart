import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:isolate_kit/isolate_kit.dart';

/// Test helper utilities for isolate_controller tests
class TestHelpers {
  TestHelpers._();

  /// Create a basic test registry with common tasks
  static IsolateTaskRegistry createBasicRegistry() {
    final registry = IsolateTaskRegistry();

    registry.register<SimpleTask>(
      'simple_task',
      (payload, transferables) => SimpleTask.fromPayload(payload),
    );

    registry.register<LongRunningTask>(
      'long_task',
      (payload, transferables) => LongRunningTask.fromPayload(payload),
    );

    registry.register<ProgressTask>(
      'progress_task',
      (payload, transferables) => ProgressTask.fromPayload(payload),
    );

    registry.register<ErrorTask>(
      'error_task',
      (payload, transferables) => ErrorTask.fromPayload(payload),
    );

    registry.register<TransferableTask>(
      'transferable_task',
      (payload, transferables) =>
          TransferableTask.fromPayload(payload, transferables),
    );

    registry.register<PriorityTask>(
      'priority_task',
      (payload, transferables) => PriorityTask.fromPayload(payload),
    );

    return registry;
  }

  /// Create a test controller with basic configuration
  static IsolateKit createTestController({
    IsolateTaskRegistry? registry,
    String debugName = 'TestController',
    int maxConcurrentTasks = 3,
    bool usePool = false,
    int poolSize = 2,
  }) {
    return IsolateKit.create(
      taskRegistry: registry ?? createBasicRegistry(),
      debugName: debugName,
      maxConcurrentTasks: maxConcurrentTasks,
      usePool: usePool,
      poolSize: poolSize,
    );
  }

  /// Wait for a condition with timeout
  static Future<void> waitFor(
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
    Duration checkInterval = const Duration(milliseconds: 100),
  }) async {
    final endTime = DateTime.now().add(timeout);

    while (!condition()) {
      if (DateTime.now().isAfter(endTime)) {
        throw TimeoutException('Condition not met within timeout');
      }
      await Future.delayed(checkInterval);
    }
  }

  /// Create test data of specific size
  static Uint8List createTestData(int sizeInBytes, {int? seed}) {
    final data = Uint8List(sizeInBytes);
    for (int i = 0; i < sizeInBytes; i++) {
      data[i] = (seed ?? i) % 256;
    }
    return data;
  }

  /// Measure execution time
  static Future<Duration> measureTime(Future<void> Function() fn) async {
    final start = DateTime.now();
    await fn();
    return DateTime.now().difference(start);
  }

  /// Run function with timeout
  static Future<T> withTimeout<T>(
    Future<T> Function() fn,
    Duration timeout,
  ) async {
    return await fn().timeout(timeout);
  }
}

/// Progress tracker for testing
class ProgressTracker {
  final List<IsolateTaskProgress> updates = [];
  double? lastPercentage;
  String? lastMessage;

  void track(IsolateTaskProgress progress) {
    updates.add(progress);
    lastPercentage = progress.percentage;
    lastMessage = progress.message;
  }

  void clear() {
    updates.clear();
    lastPercentage = null;
    lastMessage = null;
  }

  bool get hasUpdates => updates.isNotEmpty;

  int get updateCount => updates.length;

  bool get isComplete => lastPercentage == 1.0;
}

/// Test task implementations
class SimpleTask extends IsolateTask<int, int> {
  final int value;

  SimpleTask({required this.value});

  factory SimpleTask.fromPayload(Map<String, dynamic> payload) {
    return SimpleTask(value: payload['value'] as int);
  }

  @override
  int get command => value;

  @override
  Map<String, dynamic> get payload => {'value': value};

  @override
  String get taskType => 'simple_task';

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    return value * 2;
  }
}

class LongRunningTask extends IsolateTask<int, int> {
  final int duration;

  LongRunningTask({required this.duration});

  factory LongRunningTask.fromPayload(Map<String, dynamic> payload) {
    return LongRunningTask(duration: payload['duration'] as int);
  }

  @override
  int get command => duration;

  @override
  Map<String, dynamic> get payload => {'duration': duration};

  @override
  String get taskType => 'long_task';

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start).inMilliseconds < duration) {
      cancellationToken?.throwIfCancelled();
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return duration;
  }
}

class ProgressTask extends IsolateTask<int, int> {
  final int steps;

  ProgressTask({required this.steps});

  factory ProgressTask.fromPayload(Map<String, dynamic> payload) {
    return ProgressTask(steps: payload['steps'] as int);
  }

  @override
  int get command => steps;

  @override
  Map<String, dynamic> get payload => {'steps': steps};

  @override
  String get taskType => 'progress_task';

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    for (int i = 0; i <= steps; i++) {
      cancellationToken?.throwIfCancelled();

      sendProgress?.call(IsolateTaskProgress(
        percentage: i / steps,
        message: 'Step $i of $steps',
      ));

      await Future.delayed(const Duration(milliseconds: 50));
    }
    return steps;
  }
}

class ErrorTask extends IsolateTask<void, void> {
  final String message;

  ErrorTask({required this.message});

  factory ErrorTask.fromPayload(Map<String, dynamic> payload) {
    return ErrorTask(message: payload['message'] as String);
  }

  @override
  void get command {}

  @override
  Map<String, dynamic> get payload => {'message': message};

  @override
  String get taskType => 'error_task';

  @override
  Future<void> execute({
    void Function(IsolateTaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    throw Exception(message);
  }
}

class TransferableTask extends IsolateTask<Uint8List, int> {
  final Uint8List data;

  TransferableTask({required this.data});

  factory TransferableTask.fromPayload(
    Map<String, dynamic> payload,
    List<TransferableTypedData>? transferables,
  ) {
    return TransferableTask(
      data: transferables != null
          ? TransferableHelper.toUint8List(transferables[0])
          : Uint8List(0),
    );
  }

  @override
  Uint8List get command => data;

  @override
  Map<String, dynamic> get payload => {};

  @override
  String get taskType => 'transferable_task';

  @override
  List<TransferableTypedData>? get transferables {
    if (TransferableHelper.shouldUseTransferable(data.length)) {
      return [TransferableHelper.fromUint8List(data)];
    }
    return null;
  }

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    return data.length;
  }
}

class PriorityTask extends IsolateTask<int, int> {
  final int id;
  final int taskPriority;

  PriorityTask({required this.id, required this.taskPriority});

  factory PriorityTask.fromPayload(Map<String, dynamic> payload) {
    return PriorityTask(
      id: payload['id'] as int,
      taskPriority: payload['priority'] as int,
    );
  }

  @override
  int get command => id;

  @override
  Map<String, dynamic> get payload => {
        'id': id,
        'priority': taskPriority,
      };

  @override
  String get taskType => 'priority_task';

  @override
  int get priority => taskPriority;

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return id;
  }
}

class UnregisteredTask extends IsolateTask<void, void> {
  @override
  void get command {}

  @override
  Map<String, dynamic> get payload => {};

  @override
  String get taskType => 'unregistered_task';

  @override
  Future<void> execute({
    void Function(IsolateTaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {}
}

/// Assertion helpers
class TestAssertions {
  TestAssertions._();

  /// Assert task completed successfully
  static Future<void> assertTaskCompletes<T>(
    TaskHandle<T> handle, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await handle.future.timeout(timeout);
  }

  /// Assert task throws specific exception
  static Future<void> assertTaskThrows<T, E>(
    TaskHandle<T> handle,
  ) async {
    try {
      await handle.future;
      throw AssertionError(
          'Expected task to throw $E but completed successfully');
    } catch (e) {
      if (e is! E) {
        throw AssertionError('Expected $E but got ${e.runtimeType}: $e');
      }
    }
  }

  /// Assert task is cancelled
  static Future<void> assertTaskCancelled<T>(TaskHandle<T> handle) async {
    await assertTaskThrows<T, TaskCancelledException>(handle);
  }

  /// Assert task times out
  static Future<void> assertTaskTimesOut<T>(TaskHandle<T> handle) async {
    await assertTaskThrows<T, TaskTimeoutException>(handle);
  }

  /// Assert progress was reported
  static void assertProgressReported(ProgressTracker tracker) {
    if (!tracker.hasUpdates) {
      throw AssertionError('No progress updates were received');
    }
  }

  /// Assert progress reached completion
  static void assertProgressComplete(ProgressTracker tracker) {
    if (!tracker.isComplete) {
      throw AssertionError(
        'Progress did not reach 100% (last: ${tracker.lastPercentage})',
      );
    }
  }
}

/// Mock objects for testing
class MockProgressCallback {
  final List<IsolateTaskProgress> calls = [];
  int callCount = 0;

  void call(IsolateTaskProgress progress) {
    calls.add(progress);
    callCount++;
  }

  void reset() {
    calls.clear();
    callCount = 0;
  }

  bool get wasCalled => callCount > 0;

  IsolateTaskProgress? get lastCall => calls.isEmpty ? null : calls.last;

  IsolateTaskProgress? get firstCall => calls.isEmpty ? null : calls.first;
}

/// Test fixtures
class TestFixtures {
  TestFixtures._();

  /// Small data (< 100KB)
  static Uint8List get smallData => TestHelpers.createTestData(50 * 1024);

  /// Large data (> 100KB)
  static Uint8List get largeData => TestHelpers.createTestData(200 * 1024);

  /// Very large data (> 1MB)
  static Uint8List get veryLargeData =>
      TestHelpers.createTestData(2 * 1024 * 1024);

  /// Common test values
  static const int defaultTimeout = 5000;
  static const int shortDelay = 100;
  static const int mediumDelay = 500;
  static const int longDelay = 2000;
}
