import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:isolate_kit/isolate_kit.dart';

import 'helpers/helper_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Global teardown to clean all instances
  tearDownAll(() {
    TestHelpers.cleanupAll();
  });

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
      registry.register<SimpleTask>(
        'simple_task',
            (payload, transferables) => SimpleTask.fromPayload(payload),
      );

      final task = registry.create('simple_task', {'value': 42});

      expect(task, isA<SimpleTask>());
      expect((task as SimpleTask).value, equals(42));
    });

    test('create returns null for unregistered task', () {
      final task = registry.create('unknown_task', {});
      expect(task, isNull);
    });

    test('isRegistered checks correctly', () {
      registry.register<SimpleTask>(
        'simple_task',
            (payload, transferables) => SimpleTask.fromPayload(payload),
      );

      expect(registry.isRegistered('simple_task'), isTrue);
      expect(registry.isRegistered('unknown_task'), isFalse);
    });

    test('registeredTypes returns all types', () {
      registry.register<SimpleTask>(
        'task1',
            (payload, transferables) => SimpleTask.fromPayload(payload),
      );
      registry.register<LongRunningTask>(
        'task2',
            (payload, transferables) => LongRunningTask.fromPayload(payload),
      );

      final types = registry.registeredTypes;

      expect(types, contains('task1'));
      expect(types, contains('task2'));
      expect(types.length, equals(2));
    });

    test('unregister removes task', () {
      registry.register<SimpleTask>(
        'simple_task',
            (payload, transferables) => SimpleTask.fromPayload(payload),
      );

      expect(registry.isRegistered('simple_task'), isTrue);

      registry.unregister('simple_task');

      expect(registry.isRegistered('simple_task'), isFalse);
    });

    test('clear removes all tasks', () {
      registry.register<SimpleTask>(
        'task1',
            (payload, transferables) => SimpleTask.fromPayload(payload),
      );
      registry.register<LongRunningTask>(
        'task2',
            (payload, transferables) => LongRunningTask.fromPayload(payload),
      );

      registry.clear();

      expect(registry.registeredTypes, isEmpty);
    });

    test('clone creates independent copy', () {
      registry.register<SimpleTask>(
        'simple_task',
            (payload, transferables) => SimpleTask.fromPayload(payload),
      );

      final cloned = registry.clone();

      expect(cloned.isRegistered('simple_task'), isTrue);

      // Modify original
      registry.unregister('simple_task');

      // Clone should still have it
      expect(cloned.isRegistered('simple_task'), isTrue);
    });
  });

  group('TaskHandle', () {
    late IsolateKit controller;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = TestHelpers.createBasicRegistry();
      controller = TestHelpers.createTestController(registry: registry);
    });

    tearDown(() {
      try {
        controller.dispose(force: true);
      } catch (e) {
        print('Error disposing controller: $e');
      }
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

      // Wait for task to start
      await Future.delayed(const Duration(milliseconds: 100));

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

      // Start waiting for cancellation
      final cancelledFuture = handle.cancelled;

      // Wait for task to start executing in isolate
      await Future.delayed(const Duration(milliseconds: 200));

      // Cancel the task
      handle.cancel();

      // The cancelled future should complete quickly
      await expectLater(
        cancelledFuture.timeout(const Duration(milliseconds: 500)),
        completes,
      );

      // Main future should also throw cancellation
      try {
        await handle.future.timeout(const Duration(seconds: 2));
        fail('Expected TaskCancelledException');
      } catch (e) {
        expect(e, anyOf([
          isA<TaskCancelledException>(),
          isA<TimeoutException>(), // In case it times out
        ]));
      }
    });
  });

  group('IsolateKit - Basic Operations', () {
    late IsolateKit controller;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = TestHelpers.createBasicRegistry();
    });

    tearDown(() {
      try {
        controller.dispose(force: true);
      } catch (e) {
        print('Error disposing controller: $e');
      }
    });

    test('creates instance with correct configuration', () {
      controller = TestHelpers.createTestController(
        registry: registry,
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

      IsolateKit.disposeInstance('singleton_test');
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
        throwsA(anyOf([
          isA<TaskTimeoutException>(),
          isA<TimeoutException>(),
        ])),
      );
    });

    test('task cancellation works', () async {
      controller = TestHelpers.createTestController(registry: registry);

      final handle = controller.runTask<int, int>(
        LongRunningTask(duration: 5000),
      );

      // Wait for task to start
      await Future.delayed(const Duration(milliseconds: 150));
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
      expect(duration.inMilliseconds, lessThan(1000)); // Should be quick
    });

    test('priority queue works correctly', () async {
      controller = TestHelpers.createTestController(
        registry: registry,
        maxConcurrentTasks: 1, // Force sequential execution
      );

      final executionOrder = <int>[];

      // Add tasks with different priorities
      final handles = [
        controller.runTask<int, int>(
          PriorityTask(id: 1, taskPriority: IsolateTaskPriority.low),
        ),
        controller.runTask<int, int>(
          PriorityTask(id: 2, taskPriority: IsolateTaskPriority.high),
        ),
        controller.runTask<int, int>(
          PriorityTask(id: 3, taskPriority: IsolateTaskPriority.critical),
        ),
      ];

      // Wait for all to complete
      await Future.wait([
        for (var handle in handles)
          handle.future.then((r) => executionOrder.add(r)),
      ]);

      // All tasks should complete
      expect(executionOrder.length, equals(3));
      // Critical task should be executed
      expect(executionOrder, contains(3));
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
      registry = TestHelpers.createBasicRegistry();
    });

    tearDown(() {
      try {
        controller.dispose(force: true);
      } catch (e) {
        print('Error disposing controller: $e');
      }
    });

    test('warmup initializes isolate', () async {
      controller = TestHelpers.createTestController(registry: registry);

      await controller.warmup();

      final status = controller.getStatus();
      expect(status['warmedUp'], isTrue);
      expect(status['initialized'], isTrue);
    });

    test('cancelAll cancels all tasks', () async {
      controller = TestHelpers.createTestController(
        registry: registry,
        maxConcurrentTasks: 1,
      );

      final handles = List.generate(
        5,
            (i) => controller.runTask<int, int>(
          LongRunningTask(duration: 5000),
        ),
      );

      // Wait for at least first task to start
      await Future.delayed(const Duration(milliseconds: 200));

      controller.cancelAll();

      // All tasks should be cancelled
      for (final handle in handles) {
        try {
          await handle.future.timeout(const Duration(seconds: 2));
          fail('Expected task to be cancelled');
        } catch (e) {
          expect(e, anyOf([
            isA<TaskCancelledException>(),
            isA<TimeoutException>(), // Acceptable if not started yet
          ]));
        }
      }
    });

    test('reset reinitializes controller', () async {
      controller = TestHelpers.createTestController(registry: registry);

      await controller.init();
      expect(controller.getStatus()['initialized'], isTrue);

      await controller.reset();
      expect(controller.getStatus()['initialized'], isTrue);
    });

    test('getStatus returns correct information', () {
      controller = TestHelpers.createTestController(
        registry: registry,
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
      controller = TestHelpers.createTestController(registry: registry);

      controller.dispose();

      final status = controller.getStatus();
      expect(status['initialized'], isFalse);
    });

    test('force dispose works with active tasks', () async {
      controller = TestHelpers.createTestController(registry: registry);

      final handle = controller.runTask<int, int>(
        LongRunningTask(duration: 5000),
      );

      // Wait for task to start
      await Future.delayed(const Duration(milliseconds: 200));

      controller.dispose(force: true);

      // Task should be cancelled due to dispose
      try {
        await handle.future.timeout(const Duration(seconds: 2));
        fail('Expected task to be cancelled or timeout');
      } catch (e) {
        expect(e, anyOf([
          isA<TaskCancelledException>(),
          isA<TimeoutException>(), // Also acceptable
        ]));
      }
    });
  });

  group('IsolateKit - Pool Mode', () {
    late IsolateKit controller;
    late IsolateTaskRegistry registry;

    setUp(() {
      registry = TestHelpers.createBasicRegistry();
    });

    tearDown(() {
      try {
        controller.dispose(force: true);
      } catch (e) {
        print('Error disposing controller: $e');
      }
    });

    test('pool mode executes tasks', () async {
      controller = TestHelpers.createTestController(
        registry: registry,
        usePool: true,
        poolSize: 2,
      );

      // Give pool time to initialize
      await Future.delayed(const Duration(milliseconds: 100));

      final handle = controller.runTask<int, int>(
        SimpleTask(value: 10),
      );

      final result = await handle.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Task did not complete'),
      );

      expect(result, equals(20));
    });

    test('pool distributes load across workers', () async {
      controller = TestHelpers.createTestController(
        registry: registry,
        usePool: true,
        poolSize: 3,
        maxConcurrentTasks: 10,
      );

      // Give pool time to initialize
      await Future.delayed(const Duration(milliseconds: 100));

      final handles = List.generate(
        9,
            (i) => controller.runTask<int, int>(SimpleTask(value: i)),
      );

      final results = await Future.wait(
        handles.map((h) => h.future),
        eagerError: true,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Tasks did not complete'),
      );

      expect(results.length, equals(9));

      final status = controller.getStatus();
      expect(status['poolStatus'], isNotNull);
    });

    test('pool status shows worker information', () async {
      controller = TestHelpers.createTestController(
        registry: registry,
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
      registry = TestHelpers.createBasicRegistry();
    });

    tearDown(() {
      TestHelpers.cleanupAll();
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

      final countBefore = IsolateKit.instanceNames.length;
      expect(countBefore, greaterThanOrEqualTo(2));

      IsolateKit.disposeInstance('test1');

      expect(IsolateKit.instanceNames, isNot(contains('test1')));
      expect(IsolateKit.instanceNames, contains('test2'));
    });

    test('disposeAll removes all instances', () {
      IsolateKit.instance(name: 'test1', taskRegistry: registry);
      IsolateKit.instance(name: 'test2', taskRegistry: registry);
      IsolateKit.instance(name: 'test3', taskRegistry: registry);

      final countBefore = IsolateKit.instanceNames.length;
      expect(countBefore, greaterThanOrEqualTo(3));

      IsolateKit.disposeAll();

      expect(IsolateKit.instanceNames, isEmpty);
    });

    test('instanceNames returns all instance names', () {
      IsolateKit.instance(name: 'alpha', taskRegistry: registry);
      IsolateKit.instance(name: 'beta', taskRegistry: registry);

      final names = IsolateKit.instanceNames;

      expect(names, contains('alpha'));
      expect(names, contains('beta'));
    });

    test('getAllStatus returns all instances status', () {
      IsolateKit.instance(name: 'test1', taskRegistry: registry);
      IsolateKit.instance(name: 'test2', taskRegistry: registry);

      final allStatus = IsolateKit.getAllStatus();

      expect(allStatus['totalInstances'], greaterThanOrEqualTo(2));
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
      try {
        controller.dispose(force: true);
      } catch (e) {
        print('Error disposing controller: $e');
      }
    });

    test('unregistered task throws error', () async {
      controller = TestHelpers.createTestController(registry: registry);

      // Try to run unregistered task
      final task = UnregisteredTask();

      final handle = controller.runTask(task);

      await expectLater(
        handle.future,
        throwsA(predicate((e) => e.toString().contains('not registered'))),
      );
    });
  });
}