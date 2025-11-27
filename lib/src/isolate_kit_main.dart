import 'dart:async';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:isolate_kit/isolate_kit.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

export 'cancellation_token.dart';
export 'isolate_init_data.dart';
export 'isolate_message.dart';
export 'isolate_pool.dart';
export 'isolate_task.dart';
export 'isolate_task_registry.dart';
export 'pool_worker.dart';
export 'task_exception.dart';
export 'task_handle.dart';
export 'task_priority.dart';
export 'task_progress.dart';

part 'queue_task.dart';

class IsolateKit with WidgetsBindingObserver {
  static final Map<String, IsolateKit> _instances = {};

  /// Get or create named instance (singleton pattern)
  factory IsolateKit.instance({
    required String name,
    required IsolateTaskRegistry taskRegistry,
    String? debugName,
    Duration? idleTimeout,
    Duration? idleCheckInterval,
    int? maxConcurrentTasks,
    bool? usePool,
    int? poolSize,
  }) {
    return _instances.putIfAbsent(
      name,
      () => IsolateKit._internal(
        taskRegistry: taskRegistry,
        debugName: debugName ?? name,
        idleTimeout: idleTimeout ?? const Duration(minutes: 5),
        idleCheckInterval: idleCheckInterval ?? const Duration(minutes: 1),
        maxConcurrentTasks: maxConcurrentTasks ?? 3,
        usePool: usePool ?? false,
        poolSize: poolSize ?? 2,
      ),
    );
  }

  /// Create new instance (non-singleton)
  factory IsolateKit.create({
    required IsolateTaskRegistry taskRegistry,
    String debugName = 'IsolateController',
    Duration idleTimeout = const Duration(minutes: 5),
    Duration idleCheckInterval = const Duration(minutes: 1),
    int maxConcurrentTasks = 3,
    bool usePool = false,
    int poolSize = 2,
  }) {
    return IsolateKit._internal(
      taskRegistry: taskRegistry,
      debugName: debugName,
      idleTimeout: idleTimeout,
      idleCheckInterval: idleCheckInterval,
      maxConcurrentTasks: maxConcurrentTasks,
      usePool: usePool,
      poolSize: poolSize,
    );
  }

  final IsolateTaskRegistry taskRegistry;
  final String debugName;
  final Duration idleTimeout;
  final Duration idleCheckInterval;
  final int maxConcurrentTasks;
  final bool usePool;
  final int poolSize;

  Isolate? _isolate;
  SendPort? _sendPort;
  IsolatePool? _pool;
  final _queueLock = Lock();
  final _initLock = Lock();
  Timer? _idleTimer;
  DateTime? _lastUsed;
  DateTime? _spawnTime;
  int _activeTasks = 0;
  int _totalCompleted = 0;
  late final String _id;
  bool _warmedUp = false;
  final _uuid = Uuid();

  final PriorityQueue<_QueuedTask> _queue = PriorityQueue<_QueuedTask>();
  final Map<String, _QueuedTask> _running = {};

  IsolateKit._internal({
    required this.taskRegistry,
    required this.debugName,
    required this.idleTimeout,
    required this.idleCheckInterval,
    required this.maxConcurrentTasks,
    required this.usePool,
    required this.poolSize,
  }) {
    _id = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    _setupLifecycle();
  }

  // ====================== LIFECYCLE ======================

  void _setupLifecycle() {
    WidgetsBinding.instance.addObserver(this);
    _startIdleTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        debugPrint('[$debugName:$_id] 📱 App paused');
        _tryDisposeOnPause();
        break;
      case AppLifecycleState.detached:
        debugPrint('[$debugName:$_id] 🛑 App detached → force dispose');
        dispose(force: true);
        break;
      case AppLifecycleState.resumed:
        debugPrint('[$debugName:$_id] ✅ App resumed');
        break;
      default:
        break;
    }
  }

  void _tryDisposeOnPause() {
    Future.delayed(const Duration(seconds: 30), () {
      if (_activeTasks == 0 && _queue.isEmpty) {
        debugPrint('[$debugName:$_id] 💤 Disposing after pause');
        dispose();
      }
    });
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(idleCheckInterval, (_) {
      if (_lastUsed == null || _activeTasks > 0) return;
      if (DateTime.now().difference(_lastUsed!) > idleTimeout) {
        debugPrint('[$debugName:$_id] 💤 Idle timeout → dispose');
        dispose();
      }
    });
  }

  void _markUsed() => _lastUsed = DateTime.now();

  // ====================== PUBLIC API ======================

  /// Warmup isolate/pool to avoid first-call latency
  Future<void> warmup() async {
    if (_warmedUp) return;
    await init();
    _warmedUp = true;
    debugPrint('[$debugName:$_id] 🔥 Warmup complete');
  }

  /// Initialize isolate/pool
  Future<void> init() async => _initLock.synchronized(() async {
        if (_isolate != null || (_pool != null && _pool!.initialized)) return;
        _markUsed();

        try {
          if (usePool) {
            _pool = IsolatePool(
              poolSize: poolSize,
              taskRegistry: taskRegistry,
              debugName: debugName,
            );
            await _pool!.init();
            await _pool!.whenReady;
          } else {
            final rp = ReceivePort();
            _isolate = await Isolate.spawn(
              PoolWorker.isolateWorker,
              IsolateInitData(
                  sendPort: rp.sendPort, taskRegistry: taskRegistry.clone()),
              debugName: '$debugName-$_id',
              errorsAreFatal: false,
            );
            _sendPort = await rp.first.timeout(
              const Duration(seconds: 10),
              onTimeout: () => throw TimeoutException('Isolate init timeout'),
            ) as SendPort;
            rp.close();
            _spawnTime = DateTime.now();
            debugPrint('[$debugName:$_id] ✅ Isolate spawned');
          }
          _startIdleTimer();
        } catch (e) {
          _isolate?.kill(priority: Isolate.immediate);
          _isolate = null;
          _sendPort = null;
          _pool?.dispose();
          _pool = null;
          rethrow;
        }
      });

  /// Run task with full feature support
  TaskHandle<TResult> runTask<TCommand, TResult>(
    IsolateTask<TCommand, TResult> task, {
    Duration timeout = const Duration(seconds: 30),
    void Function(TaskProgress)? onProgress,
  }) {
    // If pool is requested but not yet created, start initialization in background
    if (usePool && _pool == null) {
      init();
    }

    final taskId = _uuid.v4();
    final completer = Completer<TResult>();
    final token = CancellationToken();

    final queued = _QueuedTask(
      taskId: taskId,
      task: task,
      timeout: timeout,
      completer: completer,
      onProgress: onProgress,
      cancellationToken: token,
    );

    _queueLock.synchronized(() {
      _queue.add(queued);
      debugPrint(
          '[$debugName:$_id] 📥 Task $taskId queued (priority: ${task.priority})');
      _processQueue();
    });

    return TaskHandle.internal(
        taskId: taskId, future: completer.future, token: token);
  }

  Future<void> _processQueue() async {
    final tasksToExecute = <_QueuedTask>[];

    await _queueLock.synchronized(() {
      while (_activeTasks < maxConcurrentTasks && _queue.isNotEmpty) {
        final qt = _queue.removeFirst();

        // ✅ FIX: Complete cancelled tasks immediately
        if (qt.cancellationToken.isCancelled) {
          if (!qt._done) {
            qt._done = true;
            if (!qt.completer.isCompleted) {
              qt.completer.completeError(TaskCancelledException(qt.taskId));
            }
          }
          continue; // Skip to next task
        }

        _activeTasks++;
        _running[qt.taskId] = qt;
        tasksToExecute.add(qt);
      }
    });

    // Execute outside of lock
    for (final qt in tasksToExecute) {
      _executeTask(qt);
    }
  }

  Future<void> _executeTask(_QueuedTask qt) async {
    final startTime = DateTime.now();
    debugPrint(
        '[$debugName:$_id] 🚀 Executing task ${qt.taskId} (${qt.task.taskType})');

    // keep reference to onCancel to remove it exactly later
    VoidCallback? onCancel;

    try {
      _markUsed();

      // Check if already cancelled before starting
      if (qt.cancellationToken.isCancelled) {
        throw TaskCancelledException(qt.taskId);
      }

      dynamic result;

      if (usePool && _pool != null) {
        result = await _pool!.runTask(
          qt.taskId,
          qt.task,
          timeout: qt.timeout,
          onProgress: qt.onProgress,
          token: qt.cancellationToken,
        );
      } else {
        await init();

        if (_sendPort == null) {
          throw Exception('SendPort is null after init');
        }

        final rp = ReceivePort();
        final pp = qt.onProgress != null ? ReceivePort() : null;
        final cp = ReceivePort();

        _sendPort!.send(IsolateMessage(
          taskId: qt.taskId,
          taskType: qt.task.taskType,
          command: qt.task.command,
          payload: qt.task.payload,
          replyPort: rp.sendPort,
          progressPort: pp?.sendPort,
          cancelControlPort: cp.sendPort,
          transferables: qt.task.transferables,
        ));

        final cancelPort = await cp.first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Cancel handshake timeout'),
        ) as SendPort;

        onCancel = () => cancelPort.send('cancel');
        qt.cancellationToken.addListener(onCancel);

        pp?.listen((msg) {
          if (msg is Map && !qt.cancellationToken.isCancelled) {
            qt.onProgress?.call(TaskProgress(
              percentage: (msg['percentage'] as num?)?.toDouble() ?? 0.0,
              message: msg['message'] as String?,
              data: msg['data'],
            ));
          }
        });

        try {
          final raw = await rp.first.timeout(qt.timeout);
          // remove listener once message retrieved
          qt.cancellationToken.removeListener(onCancel);
          onCancel = null; // Prevent double removal

          if (raw is Map && raw.containsKey('error')) {
            final err = raw['error'].toString();
            if (err.contains('cancelled')) {
              throw TaskCancelledException(qt.taskId);
            }
            throw Exception(err);
          }
          result = raw;
        } finally {
          // Ensure listener is removed
          if (onCancel != null) {
            qt.cancellationToken.removeListener(onCancel);
          }
          pp?.close();
          rp.close();
          cp.close();
        }
      }

      // Complete the task successfully
      if (!qt.cancellationToken.isCancelled && !qt.completer.isCompleted) {
        await _queueLock.synchronized(() {
          if (!qt._done) {
            qt._done = true;
            if (!qt.completer.isCompleted) {
              qt.completer.complete(result);
            }
            // ✅ Increment counter INSIDE the lock
            _totalCompleted++;
          }
        });

        final duration = DateTime.now().difference(startTime);
        debugPrint(
            '[$debugName:$_id] ✅ Task ${qt.taskId} completed in ${duration.inMilliseconds}ms');
      }
    } on TaskCancelledException {
      await _queueLock.synchronized(() {
        if (!qt._done) {
          qt._done = true;
          if (!qt.completer.isCompleted) {
            qt.completer.completeError(TaskCancelledException(qt.taskId));
          }
        }
      });
      debugPrint('[$debugName:$_id] 🚫 Task ${qt.taskId} cancelled');
    } on TaskTimeoutException catch (e) {
      await _queueLock.synchronized(() {
        if (!qt._done) {
          qt._done = true;
          if (!qt.completer.isCompleted) {
            qt.completer.completeError(e);
          }
        }
      });
      debugPrint('[$debugName:$_id] ⏱️  Task ${qt.taskId} timeout');
    } catch (e, s) {
      await _queueLock.synchronized(() {
        if (!qt._done) {
          qt._done = true;
          if (!qt.completer.isCompleted) {
            qt.completer.completeError(e, s);
          }
        }
      });
      debugPrint('[$debugName:$_id] ❌ Task ${qt.taskId} error: $e');
    } finally {
      // Clean up INSIDE lock to ensure consistency
      await _queueLock.synchronized(() {
        _activeTasks--;
        _running.remove(qt.taskId);
      });

      // Process queue OUTSIDE lock to avoid deadlock
      _processQueue();
    }
  }

  Future<void> whenReady() async {
    if (!usePool) {
      await init();
      return;
    }
    if (_pool != null) {
      await _pool!.whenReady;
    } else {
      // If pool not created yet, init it
      await init();
      await _pool!.whenReady;
    }
  }

  /// Cancel all tasks
  Future<void> cancelAll() async {
    await _queueLock.synchronized(() {
      debugPrint('[$debugName:$_id] 🚫 Cancelling all tasks...');

      // Cancel queued tasks - create a list copy first
      final queuedTasks = _queue.toList();
      _queue.clear();

      for (final task in queuedTasks) {
        // DO NOT complete here — let executor/processQueue handle completion to avoid races
        task.cancellationToken.cancel();
      }

      // Cancel running tasks - DON'T complete their futures here
      // Let _executeTask handle completion
      final runningTasks = _running.values.toList();
      for (final task in runningTasks) {
        task.cancellationToken.cancel();
      }

      // Inform workers (best-effort). Workers will ignore this or handle it locally.
      if (usePool && _pool != null) {
        for (final worker in _pool!.workers) {
          try {
            worker.sendPort?.send({'type': 'cancel_all'});
          } catch (e) {
            debugPrint(
                '[$debugName:$_id] Failed to send cancel_all to worker: $e');
          }
        }
      }

      try {
        _sendPort?.send({'type': 'cancel_all'});
      } catch (e) {
        // may be null or closed
      }

      debugPrint('[$debugName:$_id] ✅ All tasks cancelled');
    });
  }

  /// Reset controller (dispose and reinitialize)
  Future<void> reset() async {
    debugPrint('[$debugName:$_id] 🔄 Resetting...');
    dispose(force: true);
    _setupLifecycle();
    await init();
    debugPrint('[$debugName:$_id] ✅ Reset complete');
  }

  /// Dispose controller
  Future<void> dispose({bool force = false}) async {
    await _queueLock.synchronized(() {
      if (!force && _activeTasks > 0) {
        debugPrint(
            '[$debugName:$_id] ⚠️  Cannot dispose: $_activeTasks active tasks');
        return;
      }

      debugPrint('[$debugName:$_id] 🧹 Disposing...');

      _idleTimer?.cancel();
      _idleTimer = null;

      try {
        _isolate?.kill(priority: Isolate.immediate);
      } catch (_) {}
      _pool?.dispose();
      _isolate = null;
      _sendPort = null;
      _pool = null;
      _warmedUp = false;

      // Cancel all pending tasks - create copies first
      final queuedTasks = _queue.toList();
      _queue.clear();

      for (final task in queuedTasks) {
        task.cancellationToken.cancel();
        if (!task._done) {
          task._done = true;
          if (!task.completer.isCompleted) {
            task.completer.completeError(TaskCancelledException(task.taskId));
          }
        }
      }

      // Cancel running tasks - DON'T complete their futures here
      // Let _executeTask handle completion when it detects cancellation
      final runningTasks = _running.values.toList();
      _running.clear();

      for (final task in runningTasks) {
        task.cancellationToken.cancel();
      }

      WidgetsBinding.instance.removeObserver(this);
      _instances.removeWhere((key, value) => value == this);

      debugPrint('[$debugName:$_id] ✅ Disposed');
    });
  }

  /// Get controller status
  Map<String, dynamic> getStatus() {
    final now = DateTime.now();
    final idle =
        _lastUsed != null ? now.difference(_lastUsed!).inMinutes : null;
    final uptime =
        _spawnTime != null ? now.difference(_spawnTime!).inSeconds : null;

    return {
      'debugName': debugName,
      'id': _id,
      'initialized': _isolate != null || (_pool != null && _pool!.initialized),
      'warmedUp': _warmedUp,
      'usePool': usePool,
      'poolStatus': _pool?.getStatus(),
      'activeTasks': _activeTasks,
      'queuedTasks': _queue.length,
      'runningTasks': _running.length,
      'maxConcurrentTasks': maxConcurrentTasks,
      'totalCompleted': _totalCompleted,
      'registeredTaskTypes': taskRegistry.registeredTypes,
      'lastUsedISO': _lastUsed?.toIso8601String(),
      'spawnTimeISO': _spawnTime?.toIso8601String(),
      'uptimeSeconds': uptime,
      'idleMinutes': idle,
      'queueDetails': _queue
          .toList()
          .map((qt) => {
                'taskId': qt.taskId,
                'taskType': qt.task.taskType,
                'priority': qt.task.priority,
                'waitingMs': qt.waitingTime.inMilliseconds,
              })
          .toList(),
    };
  }

  // ====================== STATIC METHODS ======================

  /// Dispose specific instance
  static void disposeInstance(String name) {
    final instance = _instances.remove(name);
    instance?.dispose(force: true);
  }

  /// Dispose all instances - avoid concurrent modification
  static void disposeAll() {
    final instancesToDispose = List<IsolateKit>.from(_instances.values);
    _instances.clear();

    for (var instance in instancesToDispose) {
      instance.dispose(force: true);
    }

    debugPrint('IsolateController: 🧹 All instances disposed');
  }

  /// Get all instance names
  static List<String> get instanceNames => _instances.keys.toList();

  /// Get all instances status
  static Map<String, dynamic> getAllStatus() {
    return {
      'totalInstances': _instances.length,
      'instances': _instances.map((name, instance) => MapEntry(
            name,
            instance.getStatus(),
          )),
    };
  }
}
