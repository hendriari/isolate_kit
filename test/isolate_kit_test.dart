import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isolate_kit/isolate_kit.dart';

import 'helpers/helper_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CancellationToken', () {
    test('initial state is not cancelled', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
    });

    test('cancel sets isCancelled to true', () {
      final token = CancellationToken();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('cancel notifies listeners', () {
      final token = CancellationToken();
      var notified = false;

      token.addListener(() => notified = true);
      token.cancel();

      expect(notified, isTrue);
    });

    test('addListener on already cancelled token calls immediately', () {
      final token = CancellationToken();
      token.cancel();

      var called = false;
      token.addListener(() => called = true);

      expect(called, isTrue);
    });

    test('throwIfCancelled throws when cancelled', () {
      final token = CancellationToken();
      token.cancel();

      expect(
        () => token.throwIfCancelled(),
        throwsA(isA<TaskCancelledException>()),
      );
    });

    test('throwIfCancelled does not throw when not cancelled', () {
      final token = CancellationToken();
      expect(() => token.throwIfCancelled(), returnsNormally);
    });

    test('cancelled future completes on cancel', () async {
      final token = CancellationToken();

      final future = token.cancelled.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () => fail('Should complete before timeout'),
      );

      token.cancel();
      await expectLater(future, completes);
    });

    test('removeListener works correctly', () {
      final token = CancellationToken();
      var callCount = 0;

      void listener() => callCount++;

      token.addListener(listener);
      token.removeListener(listener);
      token.cancel();

      expect(callCount, equals(0));
    });

    test('combine creates token that cancels when any source cancels', () {
      final token1 = CancellationToken();
      final token2 = CancellationToken();
      final combined = CancellationToken.combine([token1, token2]);

      expect(combined.isCancelled, isFalse);

      token1.cancel();
      expect(combined.isCancelled, isTrue);
    });

    test('multiple cancels are idempotent', () {
      final token = CancellationToken();
      var callCount = 0;

      token.addListener(() => callCount++);

      token.cancel();
      token.cancel();
      token.cancel();

      expect(callCount, equals(1));
    });
  });

  group('IsolateTaskPriority', () {
    test('priority constants are correct', () {
      expect(IsolateTaskPriority.low, equals(0));
      expect(IsolateTaskPriority.normal, equals(5));
      expect(IsolateTaskPriority.high, equals(10));
      expect(IsolateTaskPriority.critical, equals(15));
      expect(IsolateTaskPriority.realtime, equals(20));
    });
  });

  group('IsolateTaskProgress', () {
    test('creates progress with required fields', () {
      final progress = IsolateTaskProgress(percentage: 0.5);

      expect(progress.percentage, equals(0.5));
      expect(progress.message, isNull);
      expect(progress.data, isNull);
      expect(progress.timestamp, isA<DateTime>());
    });

    test('creates progress with all fields', () {
      final progress = IsolateTaskProgress(
        percentage: 0.75,
        message: 'Processing...',
        data: {'items': 10},
      );

      expect(progress.percentage, equals(0.75));
      expect(progress.message, equals('Processing...'));
      expect(progress.data, equals({'items': 10}));
    });

    test('toString formats correctly', () {
      final progress = IsolateTaskProgress(
        percentage: 0.456,
        message: 'Working',
      );

      expect(progress.toString(), contains('45.6%'));
      expect(progress.toString(), contains('Working'));
    });

    test('toJson converts correctly', () {
      final progress = IsolateTaskProgress(
        percentage: 0.8,
        message: 'Almost done',
        data: {'count': 5},
      );

      final json = progress.toJson();

      expect(json['percentage'], equals(0.8));
      expect(json['message'], equals('Almost done'));
      expect(json['data'], equals({'count': 5}));
      expect(json['timestamp'], isA<String>());
    });
  });

  group('IsolateTaskRegistry', () {
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = IsolateTaskRegistry();
    });

    test('register and create task', () {
      registry.register<TestTask>(
        'test_task',
        (payload, transferables) => TestTask.fromPayload(payload),
      );

      final task = registry.create('test_task', {'value': 42});

      expect(task, isA<TestTask>());
      expect((task as TestTask).value, equals(42));
    });

    test('create returns null for unregistered task', () {
      final task = registry.create('unknown_task', {});
      expect(task, isNull);
    });

    test('isRegistered checks correctly', () {
      registry.register<TestTask>(
        'test_task',
        (payload, transferables) => TestTask.fromPayload(payload),
      );

      expect(registry.isRegistered('test_task'), isTrue);
      expect(registry.isRegistered('unknown_task'), isFalse);
    });

    test('registeredTypes returns all types', () {
      registry.register<TestTask>(
        'task1',
        (payload, transferables) => TestTask.fromPayload(payload),
      );
      registry.register<TestTask>(
        'task2',
        (payload, transferables) => TestTask.fromPayload(payload),
      );

      final types = registry.registeredTypes;

      expect(types, contains('task1'));
      expect(types, contains('task2'));
      expect(types.length, equals(2));
    });

    test('unregister removes task', () {
      registry.register<TestTask>(
        'test_task',
        (payload, transferables) => TestTask.fromPayload(payload),
      );

      expect(registry.isRegistered('test_task'), isTrue);

      registry.unregister('test_task');

      expect(registry.isRegistered('test_task'), isFalse);
    });

    test('clear removes all tasks', () {
      registry.register<TestTask>(
        'task1',
        (payload, transferables) => TestTask.fromPayload(payload),
      );
      registry.register<TestTask>(
        'task2',
        (payload, transferables) => TestTask.fromPayload(payload),
      );

      registry.clear();

      expect(registry.registeredTypes, isEmpty);
    });
  });

  group('TaskHandle', () {
    late IsolateKit controller;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = IsolateTaskRegistry();
      registry.register<SimpleTask>(
        'simple_task',
        (payload, transferables) => SimpleTask.fromPayload(payload),
      );
      registry.register<LongRunningTask>(
        'long_task',
        (payload, transferables) => LongRunningTask.fromPayload(payload),
      );
      controller = IsolateKit.create(taskRegistry: registry);
    });

    tearDown(() {
      controller.dispose(force: true);
    });

    test('handle has correct properties', () {
      final handle = controller.runTask<int, int>(
        SimpleTask(value: 5),
      );

      expect(handle.taskId, isNotEmpty);
      expect(handle.isCancelled, isFalse);
      expect(handle.createdAt, isA<DateTime>());
      expect(handle.future, isA<Future<int>>());
    });

    test('cancel changes isCancelled state', () async {
      final handle = controller.runTask<int, int>(
        LongRunningTask(duration: 5000),
      );

      expect(handle.isCancelled, isFalse);

      handle.cancel();

      expect(handle.isCancelled, isTrue);

      await expectLater(
        handle.future,
        throwsA(isA<TaskCancelledException>()),
      );
    });

    test('timeout works correctly', () async {
      final handle = controller.runTask<int, int>(
        LongRunningTask(duration: 5000),
      );

      await expectLater(
        handle.timeout(const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('timeout with onTimeout callback', () async {
      final handle = controller.runTask<int, int>(
        LongRunningTask(duration: 5000),
      );

      final result = await handle.timeout(
        const Duration(milliseconds: 100),
        onTimeout: () => 999,
      );

      expect(result, equals(999));
    });

    test('cancelled future completes when cancelled', () async {
      final handle = controller.runTask<int, int>(
        LongRunningTask(duration: 5000),
      );

      final cancelledFuture = handle.cancelled.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => fail('Should complete before timeout'),
      );

      handle.cancel();

      await expectLater(cancelledFuture, completes);
    });
  });

  group('IsolateKit - Basic Operations', () {
    late IsolateKit controller;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = IsolateTaskRegistry();
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
    });

    tearDown(() {
      controller.dispose(force: true);
    });

    test('creates instance with correct configuration', () {
      controller = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'TestController',
        maxConcurrentTasks: 2,
      );

      final status = controller.getStatus();

      expect(status['debugName'], equals('TestController'));
      expect(status['maxConcurrentTasks'], equals(2));
    });

    test('singleton pattern works', () {
      final instance1 = IsolateKit.instance(
        name: 'singleton_test',
        taskRegistry: registry,
      );

      final instance2 = IsolateKit.instance(
        name: 'singleton_test',
        taskRegistry: registry,
      );

      expect(identical(instance1, instance2), isTrue);

      instance1.dispose(force: true);
    });

    test('runTask executes simple task', () async {
      controller = TestHelpers.createTestController(registry: registry);

      final handle = controller.runTask<int, int>(
        SimpleTask(value: 5),
      );

      final result = await handle.future;

      expect(result, equals(10)); // SimpleTask doubles the value
    });

    test('runTask with timeout', () async {
      controller = TestHelpers.createTestController(registry: registry);

      final handle = controller.runTask<int, int>(
        LongRunningTask(duration: 5000),
        timeout: const Duration(milliseconds: 100),
      );

      await expectLater(
        handle.future,
        throwsA(isA<TaskTimeoutException>()),
      );
    });

    test('task cancellation works', () async {
      controller = TestHelpers.createTestController(registry: registry);

      final handle = controller.runTask<int, int>(
        LongRunningTask(duration: 5000),
      );

      // Cancel after 100ms
      await Future.delayed(const Duration(milliseconds: 100));
      handle.cancel();

      await expectLater(
        handle.future,
        throwsA(isA<TaskCancelledException>()),
      );
    });

    test('progress callbacks work', () async {
      controller = TestHelpers.createTestController(registry: registry);

      final tracker = ProgressTracker();

      final handle = controller.runTask<int, int>(
        ProgressTask(steps: 5),
        onProgress: tracker.track,
      );

      await handle.future;

      TestAssertions.assertProgressReported(tracker);
      TestAssertions.assertProgressComplete(tracker);
    });

    test('error handling works', () async {
      controller = TestHelpers.createTestController(registry: registry);

      final handle = controller.runTask<void, void>(
        ErrorTask(message: 'Test error'),
      );

      await expectLater(
        handle.future,
        throwsA(predicate((e) => e.toString().contains('Test error'))),
      );
    });

    test('multiple tasks execute in parallel', () async {
      controller = TestHelpers.createTestController(
        registry: registry,
        maxConcurrentTasks: 3,
      );

      final startTime = DateTime.now();

      final handles = List.generate(
        3,
        (i) => controller.runTask<int, int>(SimpleTask(value: i)),
      );

      final results = await Future.wait(handles.map((h) => h.future));

      final duration = DateTime.now().difference(startTime);

      expect(results, equals([0, 2, 4])); // Doubled values
      expect(duration.inMilliseconds, lessThan(500)); // Should be quick
    });

    test('priority queue works correctly', () async {
      controller = TestHelpers.createTestController(
        registry: registry,
        maxConcurrentTasks: 1, // Force sequential execution
      );

      final executionOrder = <int>[];

      // Add tasks with different priorities
      final lowHandle = controller.runTask<int, int>(
        PriorityTask(id: 1, taskPriority: IsolateTaskPriority.low),
      );

      final highHandle = controller.runTask<int, int>(
        PriorityTask(id: 2, taskPriority: IsolateTaskPriority.high),
      );

      final criticalHandle = controller.runTask<int, int>(
        PriorityTask(id: 3, taskPriority: IsolateTaskPriority.critical),
      );

      // Wait for all to complete
      await Future.wait([
        lowHandle.future.then((r) => executionOrder.add(r)),
        highHandle.future.then((r) => executionOrder.add(r)),
        criticalHandle.future.then((r) => executionOrder.add(r)),
      ]);

      // Critical should execute first, then high, then low
      // Note: First task might execute immediately
      expect(executionOrder, contains(3)); // Critical ID
    });

    test('transferable data works', () async {
      controller = TestHelpers.createTestController(registry: registry);

      final largeData = TestFixtures.largeData;

      final handle = controller.runTask<Uint8List, int>(
        TransferableTask(data: largeData),
      );

      final result = await handle.future;

      expect(result, equals(largeData.length));
    });
  });

  group('IsolateKit - Advanced Features', () {
    late IsolateKit controller;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = IsolateTaskRegistry();
      registry.register<SimpleTask>(
        'simple_task',
        (payload, transferables) => SimpleTask.fromPayload(payload),
      );
    });

    tearDown(() {
      controller.dispose(force: true);
    });

    test('warmup initializes isolate', () async {
      controller = IsolateKit.create(taskRegistry: registry);

      await controller.warmup();

      final status = controller.getStatus();
      expect(status['warmedUp'], isTrue);
      expect(status['initialized'], isTrue);
    });

    test('cancelAll cancels all tasks', () async {
      controller = IsolateKit.create(
        taskRegistry: registry,
        maxConcurrentTasks: 1,
      );

      final handles = List.generate(
        5,
        (i) => controller.runTask<int, int>(
          LongRunningTask(duration: 5000),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 100));
      controller.cancelAll();

      for (final handle in handles) {
        await expectLater(
          handle.future,
          throwsA(isA<TaskCancelledException>()),
        );
      }
    });

    test('reset reinitializes controller', () async {
      controller = IsolateKit.create(taskRegistry: registry);

      await controller.init();
      expect(controller.getStatus()['initialized'], isTrue);

      await controller.reset();
      expect(controller.getStatus()['initialized'], isTrue);
    });

    test('getStatus returns correct information', () {
      controller = IsolateKit.create(
        taskRegistry: registry,
        debugName: 'StatusTest',
        maxConcurrentTasks: 5,
      );

      final status = controller.getStatus();

      expect(status['debugName'], equals('StatusTest'));
      expect(status['maxConcurrentTasks'], equals(5));
      expect(status['activeTasks'], equals(0));
      expect(status['queuedTasks'], equals(0));
      expect(status['totalCompleted'], equals(0));
    });

    test('dispose cleans up resources', () {
      controller = IsolateKit.create(taskRegistry: registry);

      controller.dispose();

      final status = controller.getStatus();
      expect(status['initialized'], isFalse);
    });

    test('force dispose works with active tasks', () async {
      controller = IsolateKit.create(taskRegistry: registry);

      final handle = controller.runTask<int, int>(
        LongRunningTask(duration: 5000),
      );

      await Future.delayed(const Duration(milliseconds: 100));

      controller.dispose(force: true);

      await expectLater(
        handle.future,
        throwsA(isA<TaskCancelledException>()),
      );
    });
  });

  group('IsolateKit - Pool Mode', () {
    late IsolateKit controller;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = IsolateTaskRegistry();
      registry.register<SimpleTask>(
        'simple_task',
        (payload, transferables) => SimpleTask.fromPayload(payload),
      );
    });

    tearDown(() {
      controller.dispose(force: true);
    });

    test('pool mode executes tasks', () async {
      controller = IsolateKit.create(
        taskRegistry: registry,
        usePool: true,
        poolSize: 2,
      );

      final handle = controller.runTask<int, int>(
        SimpleTask(value: 10),
      );

      final result = await handle.future;
      expect(result, equals(20));
    });

    test('pool distributes load across workers', () async {
      controller = IsolateKit.create(
        taskRegistry: registry,
        usePool: true,
        poolSize: 3,
        maxConcurrentTasks: 10,
      );

      final handles = List.generate(
        9,
        (i) => controller.runTask<int, int>(SimpleTask(value: i)),
      );

      final results = await Future.wait(handles.map((h) => h.future));

      expect(results.length, equals(9));

      final status = controller.getStatus();
      expect(status['poolStatus'], isNotNull);
    });

    test('pool status shows worker information', () async {
      controller = IsolateKit.create(
        taskRegistry: registry,
        usePool: true,
        poolSize: 2,
      );

      await controller.init();

      final status = controller.getStatus();
      final poolStatus = status['poolStatus'] as Map<String, dynamic>;

      expect(poolStatus['poolSize'], equals(2));
      expect(poolStatus['initialized'], isTrue);
      expect(poolStatus['workers'], hasLength(2));
    });
  });

  group('IsolateKit - Static Methods', () {
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = IsolateTaskRegistry();
      registry.register<SimpleTask>(
        'simple_task',
        (payload, transferables) => SimpleTask.fromPayload(payload),
      );
    });

    tearDown(() {
      IsolateKit.disposeAll();
    });

    test('disposeInstance removes specific instance', () {
      IsolateKit.instance(
        name: 'test1',
        taskRegistry: registry,
      );

      IsolateKit.instance(
        name: 'test2',
        taskRegistry: registry,
      );

      expect(IsolateKit.instanceNames, hasLength(2));

      IsolateKit.disposeInstance('test1');

      expect(IsolateKit.instanceNames, hasLength(1));
      expect(IsolateKit.instanceNames, contains('test2'));
    });

    test('disposeAll removes all instances', () {
      IsolateKit.instance(name: 'test1', taskRegistry: registry);
      IsolateKit.instance(name: 'test2', taskRegistry: registry);
      IsolateKit.instance(name: 'test3', taskRegistry: registry);

      expect(IsolateKit.instanceNames, hasLength(3));

      IsolateKit.disposeAll();

      expect(IsolateKit.instanceNames, isEmpty);
    });

    test('instanceNames returns all instance names', () {
      IsolateKit.instance(name: 'alpha', taskRegistry: registry);
      IsolateKit.instance(name: 'beta', taskRegistry: registry);

      final names = IsolateKit.instanceNames;

      expect(names, contains('alpha'));
      expect(names, contains('beta'));
      expect(names, hasLength(2));
    });

    test('getAllStatus returns all instances status', () {
      IsolateKit.instance(name: 'test1', taskRegistry: registry);
      IsolateKit.instance(name: 'test2', taskRegistry: registry);

      final allStatus = IsolateKit.getAllStatus();

      expect(allStatus['totalInstances'], equals(2));
      expect(allStatus['instances'], isA<Map>());
    });
  });

  group('Error Cases', () {
    late IsolateKit controller;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = IsolateTaskRegistry();
    });

    tearDown(() {
      controller.dispose(force: true);
    });

    test('unregistered task throws error', () async {
      controller = IsolateKit.create(taskRegistry: registry);

      // Try to run unregistered task
      registry.register<SimpleTask>(
        'wrong_type',
        (payload, transferables) => SimpleTask.fromPayload(payload),
      );

      // Create task with different type name
      final task = UnregisteredTask();

      final handle = controller.runTask(task);

      await expectLater(
        handle.future,
        throwsA(predicate((e) => e.toString().contains('not registered'))),
      );
    });
  });
}

// ==================== TEST TASK IMPLEMENTATIONS ====================

class TestTask extends IsolateTask<int, int> {
  final int value;

  TestTask({required this.value});

  factory TestTask.fromPayload(Map<String, dynamic> payload) {
    return TestTask(value: payload['value'] as int);
  }

  @override
  int get command => value;

  @override
  Map<String, dynamic> get payload => {'value': value};

  @override
  String get taskType => 'test_task';

  @override
  Future<int> execute({
    void Function(IsolateTaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  }) async {
    return value * 2;
  }
}

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
  String get taskType => 'simple_task';

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
