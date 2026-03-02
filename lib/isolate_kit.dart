import 'dart:async';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:isolate_kit/isolate_kit.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

export 'src/cancellation_token.dart';
export 'src/isolate_init_data.dart';
export 'src/isolate_message.dart';
export 'src/isolate_pool.dart';
export 'src/isolate_task.dart';
export 'src/isolate_task_registry.dart';
export 'src/pool_worker.dart';
export 'src/task_exception.dart';
export 'src/task_handle.dart';
export 'src/task_priority.dart';
export 'src/task_progress.dart';

part 'src/queue_task.dart';

/// IsolateKit is a powerful utility for managing background tasks using Dart Isolates.
/// It supports both single isolate execution and isolate pooling for high-concurrency workloads.
/// Features include task prioritization, progress reporting, cancellation, and automatic lifecycle management.
class IsolateKit with WidgetsBindingObserver {
  static final Map<String, IsolateKit> _instances = {};

  /// Retrieves a named instance of [IsolateKit] following the singleton pattern.
  /// If an instance with the given [name] already exists, it is returned.
  /// Otherwise, a new instance is created and cached.
  ///
  /// Parameters:
  /// - [name]: A unique identifier for this instance.
  /// - [taskRegistry]: Registry containing task definitions this instance can execute.
  /// - [debugName]: Name used for logging and debugging purposes.
  /// - [idleTimeout]: Duration of inactivity after which the isolate/pool is automatically disposed.
  /// - [idleCheckInterval]: How often to check for idle status.
  /// - [maxConcurrentTasks]: Maximum number of tasks to run simultaneously.
  /// - [usePool]: Whether to use an [IsolatePool] instead of a single isolate.
  /// - [poolSize]: The number of workers in the pool (only used if [usePool] is true).
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

  /// Creates a new, non-cached instance of [IsolateKit].
  /// Use this when you need an isolated controller that isn't managed globally.
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

  /// The registry containing tasks that this controller can perform.
  final IsolateTaskRegistry taskRegistry;

  /// A name used for identification in logs.
  final String debugName;

  /// Inactivity period before the isolate is automatically shut down.
  final Duration idleTimeout;

  /// Frequency of checks for idle state.
  final Duration idleCheckInterval;

  /// Maximum number of tasks allowed to run concurrently.
  final int maxConcurrentTasks;

  /// If true, uses a pool of multiple isolates to process tasks.
  final bool usePool;

  /// Number of isolate workers when [usePool] is enabled.
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

  /// Pre-warms the isolate or pool to eliminate latency on the first task execution.
  Future<void> warmup() async {
    if (_warmedUp) return;
    await init();
    _warmedUp = true;
    debugPrint('[$debugName:$_id] 🔥 Warmup complete');
  }

  /// Explicitly initializes the isolate or pool.
  /// Usually called automatically when running the first task.
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

  /// Schedules a task for execution.
  ///
  /// Returns a [TaskHandle] which allows tracking progress, getting the result, or cancelling the task.
  ///
  /// Parameters:
  /// - [task]: The [IsolateTask] to be executed.
  /// - [timeout]: Maximum time allowed for the task to complete.
  /// - [onProgress]: Optional callback for receiving progress updates.
  TaskHandle<TResult> runTask<TCommand, TResult>(
    IsolateTask<TCommand, TResult> task, {
    Duration timeout = const Duration(seconds: 60),
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
    debugPrint(
        '[$debugName:$_id] 🚀 Executing task ${qt.taskId} (${qt.task.taskType})');

    final VoidCallback? onCancel;

    try {
      _markUsed();

      if (qt.cancellationToken.isCancelled) {
        throw TaskCancelledException(qt.taskId);
      }

      dynamic result;

      if (usePool && _pool != null) {
        onCancel = () {};
        qt.cancellationToken.addListener(onCancel);

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

        // Handshake pembatalan
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
          // DISINI TIMEOUT TERJADI
          final raw = await rp.first.timeout(qt.timeout);

          if (raw is Map && raw.containsKey('error')) {
            final err = raw['error'].toString();
            if (err.contains('cancelled')) {
              throw TaskCancelledException(qt.taskId);
            }
            throw Exception(err);
          }
          result = raw;
        } on TimeoutException {
          // JIKA NON-POOL TIMEOUT, KITA HARUS BUNUH ISOLATE-NYA
          debugPrint(
              '[$debugName:$_id] 🚨 Non-pool isolate timeout. Killing isolate to recover.');
          _isolate?.kill(priority: Isolate.immediate);
          _isolate = null;
          _sendPort = null;
          throw TaskTimeoutException(qt.taskId, qt.timeout);
        } finally {
          if (onCancel case final cb) {
            qt.cancellationToken.removeListener(cb);
          }
          pp?.close();
          rp.close();
          cp.close();
        }
      }

      // Berhasil
      if (!qt.cancellationToken.isCancelled && !qt.completer.isCompleted) {
        await _queueLock.synchronized(() {
          if (!qt._done) {
            qt._done = true;
            qt.completer.complete(result);
            _totalCompleted++;
          }
        });
        debugPrint('[$debugName:$_id] ✅ Task ${qt.taskId} completed');
      }
    } catch (e, s) {
      // Penanganan Error (Cancel, Timeout, atau General Error)
      await _queueLock.synchronized(() {
        if (!qt._done) {
          qt._done = true;
          qt.completer.completeError(e, s);
        }
      });

      if (e is TaskCancelledException) {
        debugPrint('[$debugName:$_id] 🚫 Task ${qt.taskId} cancelled');
      } else {
        debugPrint('[$debugName:$_id] ❌ Task ${qt.taskId} failed: $e');
      }

      // Jika error handshake timeout (bukan dari rp.first.timeout),
      // juga sebaiknya reset isolate
      if (e is TimeoutException &&
          e.message?.contains('handshake') == true &&
          !usePool) {
        _isolate?.kill(priority: Isolate.immediate);
        _isolate = null;
        _sendPort = null;
      }

      debugPrint('[$debugName:$_id] ❌ Task ${qt.taskId} failed: $e');
    } finally {
      await _queueLock.synchronized(() {
        _activeTasks--;
        _running.remove(qt.taskId);
      });
      _processQueue(); // Jalankan antrean berikutnya
    }
  }

  /// Returns a future that completes when the controller is initialized and ready to accept tasks.
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

  /// Cancels all currently queued and running tasks.
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

  /// Resets the controller by disposing of the current isolate/pool and re-initializing it.
  Future<void> reset() async {
    debugPrint('[$debugName:$_id] 🔄 Resetting...');
    dispose(force: true);
    _setupLifecycle();
    await init();
    debugPrint('[$debugName:$_id] ✅ Reset complete');
  }

  /// Shuts down the controller, kills active isolates, and clears the task queue.
  ///
  /// If [force] is false (default), it will skip disposal if there are active tasks.
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

  /// Returns a comprehensive map representing the current state of the controller,
  /// including active tasks, queue status, and uptime.
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

  /// Disposes of a specific named instance.
  static void disposeInstance(String name) {
    final instance = _instances.remove(name);
    instance?.dispose(force: true);
  }

  /// Disposes of all named instances currently tracked by [IsolateKit].
  static void disposeAll() {
    final instancesToDispose = List<IsolateKit>.from(_instances.values);
    _instances.clear();

    for (var instance in instancesToDispose) {
      instance.dispose(force: true);
    }

    debugPrint('IsolateController: 🧹 All instances disposed');
  }

  /// Lists all registered instance names.
  static List<String> get instanceNames => _instances.keys.toList();

  /// Returns a summary of the status of all managed instances.
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
