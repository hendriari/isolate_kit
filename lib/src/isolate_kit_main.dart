import 'dart:async';
import 'dart:isolate';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

// ======================= TASK PRIORITY =============================

class TaskPriority {
  static const int low = 0;
  static const int normal = 5;
  static const int high = 10;
  static const int critical = 15;
  static const int realtime = 20;
}

// ==================== EXCEPTIONS ====================

/// Proper cancellation exception
class TaskCancelledException implements Exception {
  final String taskId;

  TaskCancelledException([this.taskId = '']);

  @override
  String toString() => 'Task $taskId was cancelled';
}

/// Timeout exception with details
class TaskTimeoutException implements Exception {
  final String taskId;
  final Duration timeout;

  TaskTimeoutException(this.taskId, this.timeout);

  @override
  String toString() => 'Task $taskId timed out after ${timeout.inSeconds}s';
}

// ==================== CANCELLATION TOKEN ====================

/// True cancellation token with listener support
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];
  final Completer<void> _cancelledCompleter = Completer<void>();

  bool get isCancelled => _isCancelled;

  Future<void> get cancelled => _cancelledCompleter.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;

    if (!_cancelledCompleter.isCompleted) {
      _cancelledCompleter.complete();
    }

    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('CancellationToken listener error: $e');
      }
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (_isCancelled) throw TaskCancelledException();
  }

  void addListener(VoidCallback listener) {
    if (_isCancelled) {
      try {
        listener();
      } catch (e) {
        debugPrint('CancellationToken listener error on immediate call: $e');
      }
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Combine multiple tokens - cancelled if ANY token is cancelled
  static CancellationToken combine(List<CancellationToken> tokens) {
    final combined = CancellationToken();
    final List<VoidCallback> added = [];
    for (final token in tokens) {
      void cb() => combined.cancel();
      token.addListener(cb);
      added.add(cb);
    }
    // Note: no removal API for combined listeners in this simple implementation.
    return combined;
  }
}

// ==================== TASK PROGRESS ====================

class IsolateTaskProgress {
  final double percentage;
  final String? message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  IsolateTaskProgress({
    required this.percentage,
    this.message,
    this.data,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'Progress: ${(percentage * 100).toStringAsFixed(1)}%${message != null ? ' - $message' : ''}';

  Map<String, dynamic> toJson() => {
        'percentage': percentage,
        'message': message,
        'data': data,
        'timestamp': timestamp.toIso8601String(),
      };
}

// ==================== BASE TASK ====================

/// Base class for all background tasks
abstract class IsolateTask<TCommand, TResult> {
  TCommand get command;

  Map<String, dynamic> get payload;

  String get taskType => runtimeType.toString();

  int get priority => TaskPriority.normal;

  List<TransferableTypedData>? get transferables => null;

  /// Execute task with cancellation and progress support
  Future<TResult> execute({
    void Function(IsolateTaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  });

  /// Optional: Estimate task duration for better scheduling
  Duration? get estimatedDuration => null;

  /// Optional: Task metadata for debugging
  Map<String, dynamic> get metadata => {};
}

// ==================== TASK REGISTRY ====================

class IsolateTaskRegistry {
  final Map<
      String,
      IsolateTask Function(
          Map<String, dynamic>, List<TransferableTypedData>?)> _factories = {};
  final Map<Type, String> _typeToString = {};

  void register<T extends IsolateTask>(
    String taskType,
    T Function(Map<String, dynamic>, List<TransferableTypedData>?) factory,
  ) {
    _factories[taskType] = factory;
    _typeToString[T] = taskType;
  }

  /// Unregister a task type
  void unregister(String taskType) {
    _factories.remove(taskType);
    _typeToString.removeWhere((key, value) => value == taskType);
  }

  IsolateTask? create(
    String taskType,
    Map<String, dynamic> payload, {
    List<TransferableTypedData>? transferables,
  }) {
    final factory = _factories[taskType];
    return factory?.call(payload, transferables);
  }

  List<String> get registeredTypes => _factories.keys.toList();

  bool isRegistered(String taskType) => _factories.containsKey(taskType);

  void clear() {
    _factories.clear();
    _typeToString.clear();
  }

  /// Create a copy of registry for isolate
  IsolateTaskRegistry clone() {
    final cloned = IsolateTaskRegistry();
    cloned._factories.addAll(_factories);
    cloned._typeToString.addAll(_typeToString);
    return cloned;
  }
}

// ==================== TASK HANDLE ====================

/// Public task handle with cancellation support
class TaskHandle<T> {
  final String taskId;
  final Future<T> future;
  final CancellationToken _token;
  final DateTime createdAt;

  bool get isCancelled => _token.isCancelled;

  Future<void> get cancelled => _token.cancelled;

  TaskHandle._({
    required this.taskId,
    required this.future,
    required CancellationToken token,
  })  : _token = token,
        createdAt = DateTime.now();

  void cancel() => _token.cancel();

  /// Wait with timeout
  Future<T> timeout(Duration duration, {T Function()? onTimeout}) {
    return future.timeout(
      duration,
      onTimeout: onTimeout != null ? () => onTimeout() : null,
    );
  }
}

// ==================== INTERNAL CLASSES ====================

class _IsolateInitData {
  final SendPort sendPort;
  final IsolateTaskRegistry taskRegistry;

  _IsolateInitData({required this.sendPort, required this.taskRegistry});
}

class _IsolateMessage {
  final String taskId;
  final String taskType;
  final dynamic command;
  final Map<String, dynamic> payload;
  final SendPort replyPort;
  final SendPort? progressPort;
  final SendPort? cancelControlPort;
  final List<TransferableTypedData>? transferables;

  _IsolateMessage({
    required this.taskId,
    required this.taskType,
    required this.command,
    required this.payload,
    required this.replyPort,
    this.progressPort,
    this.cancelControlPort,
    this.transferables,
  });
}

class _QueuedTask implements Comparable<_QueuedTask> {
  bool _done = false;

  final String taskId;
  final IsolateTask task;
  final Duration timeout;
  final Completer<dynamic> completer;
  final void Function(IsolateTaskProgress)? onProgress;
  final DateTime queuedAt;
  final CancellationToken cancellationToken;

  _QueuedTask({
    required this.taskId,
    required this.task,
    required this.timeout,
    required this.completer,
    required this.cancellationToken,
    this.onProgress,
  }) : queuedAt = DateTime.now();

  @override
  int compareTo(_QueuedTask other) {
    // Priority first (higher = first)
    final p = other.task.priority - task.priority;
    if (p != 0) return p;
    // Then FIFO
    return queuedAt.compareTo(other.queuedAt);
  }

  Duration get waitingTime => DateTime.now().difference(queuedAt);
}

// ==================== POOL WORKER ====================

class _PoolWorker {
  final int workerId;
  final IsolateTaskRegistry taskRegistry;
  final String debugName;
  Isolate? _isolate;
  SendPort? _sendPort;
  int activeTasks = 0;
  int totalCompleted = 0;
  final Map<String, SendPort> _cancelPorts = {};
  DateTime? _lastUsed;

  _PoolWorker({
    required this.workerId,
    required this.taskRegistry,
    required this.debugName,
  });

  Future<void> init() async {
    final rp = ReceivePort();
    _isolate = await Isolate.spawn(
      _workerEntry,
      _IsolateInitData(
          sendPort: rp.sendPort, taskRegistry: taskRegistry.clone()),
      debugName: debugName,
      errorsAreFatal: false,
    );
    _sendPort = await rp.first.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Worker init timeout'),
    ) as SendPort;
    rp.close();
    debugPrint('[$debugName] ✅ Worker initialized');
  }

  Future<T> runTask<T>(
    String taskId,
    IsolateTask task, {
    required Duration timeout,
    void Function(IsolateTaskProgress)? onProgress,
    required CancellationToken token,
  }) async {
    activeTasks++;
    _lastUsed = DateTime.now();

    final response = ReceivePort();
    final progress = onProgress != null ? ReceivePort() : null;
    final cancelCtrl = ReceivePort();

    // store reference for the onCancel callback so we can remove it later
    VoidCallback? onCancel;

    try {
      // _sendPort must not be null here; caller should await whenReady
      _sendPort!.send(_IsolateMessage(
        taskId: taskId,
        taskType: task.taskType,
        command: task.command,
        payload: task.payload,
        replyPort: response.sendPort,
        progressPort: progress?.sendPort,
        cancelControlPort: cancelCtrl.sendPort,
        transferables: task.transferables,
      ));

      // Handshake for cancellation
      final cancelPort = await cancelCtrl.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Cancel handshake timeout'),
      ) as SendPort;
      _cancelPorts[taskId] = cancelPort;

      onCancel = () {
        try {
          cancelPort.send('cancel');
          debugPrint('[$debugName] 🚫 Sent cancel signal for task $taskId');
        } catch (e) {
          debugPrint('[$debugName] Failed to send cancel to worker: $e');
        }
      };

      token.addListener(onCancel);

      // Progress listener
      progress?.listen((msg) {
        if (msg is Map && !token.isCancelled) {
          onProgress?.call(IsolateTaskProgress(
            percentage: (msg['percentage'] as num?)?.toDouble() ?? 0.0,
            message: msg['message'] as String?,
            data: msg['data'] as Map<String, dynamic>?,
          ));
        }
      });

      // Wait for result
      final result = await response.first.timeout(
        timeout,
        onTimeout: () => throw TaskTimeoutException(taskId, timeout),
      );

      if (result is Map && result.containsKey('error')) {
        final err = result['error'].toString();
        if (err.contains('cancelled')) {
          throw TaskCancelledException(taskId);
        }
        throw Exception('Task error: $err');
      }

      totalCompleted++;
      return result as T;
    } finally {
      // remove the exact listener that was added (avoid removeListener(() {}))
      if (onCancel != null) token.removeListener(onCancel);
      _cancelPorts.remove(taskId);
      response.close();
      progress?.close();
      cancelCtrl.close();
      activeTasks--;
    }
  }

  void dispose() {
    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _isolate = null;
    _sendPort = null;
    _cancelPorts.clear();
    debugPrint('[$debugName] 🧹 Worker disposed');
  }

  Map<String, dynamic> getStatus() => {
        'workerId': workerId,
        'activeTasks': activeTasks,
        'totalCompleted': totalCompleted,
        'lastUsed': _lastUsed?.toIso8601String(),
      };

  static void _workerEntry(_IsolateInitData init) => _isolateWorker(init);

  static void _isolateWorker(_IsolateInitData init) {
    final mainPort = ReceivePort();
    init.sendPort.send(mainPort.sendPort);

    // Keep a small per-isolate registry (clone)
    final registry = init.taskRegistry.clone();

    mainPort.listen((msg) async {
      // Allow a cancel_all message — the worker will cancel currently running tasks only
      if (msg is Map && msg['type'] == 'cancel_all') {
        // nothing to do here for this simple implementation; main isolate cancels tokens
        return;
      }

      if (msg is! _IsolateMessage) return;

      final token = CancellationToken();
      ReceivePort? cancelRp;

      try {
        // Setup cancellation
        if (msg.cancelControlPort != null) {
          cancelRp = ReceivePort();
          msg.cancelControlPort!.send(cancelRp.sendPort);
          cancelRp.listen((_) {
            token.cancel();
          });
        }

        // Create task from local clone of registry
        final task = registry.create(
          msg.taskType,
          msg.payload,
          transferables: msg.transferables,
        );

        if (task == null) {
          throw Exception('Task "${msg.taskType}" not registered');
        }

        // Execute task
        final result = await task.execute(
          sendProgress: msg.progressPort != null
              ? (p) {
                  token.throwIfCancelled();
                  msg.progressPort!.send({
                    'percentage': p.percentage,
                    'message': p.message,
                    'data': p.data,
                  });
                }
              : null,
          cancellationToken: token,
        );

        msg.replyPort.send(result);
      } on TaskCancelledException {
        msg.replyPort.send({'error': 'Task ${msg.taskId} cancelled'});
      } catch (e, s) {
        msg.replyPort.send({
          'error': e.toString(),
          'stack': s.toString(),
          'taskId': msg.taskId,
        });
      } finally {
        cancelRp?.close();
      }
    });
  }
}

// ==================== ISOLATE POOL ====================

class IsolatePool {
  final int poolSize;
  final IsolateTaskRegistry taskRegistry;
  final String debugName;
  final List<_PoolWorker> _workers = [];
  final Completer<void> _ready = Completer<void>();
  bool _initialized = false;
  final Lock _initLock = Lock();

  IsolatePool({
    required this.poolSize,
    required this.taskRegistry,
    this.debugName = 'Pool',
  });

  Future<void> get whenReady => _ready.future;

  Future<void> init() async {
    await _initLock.synchronized(() async {
      if (_initialized) return;

      debugPrint('[$debugName] Initializing pool with $poolSize workers...');

      final List<Future<void>> initFutures = [];

      for (int i = 0; i < poolSize; i++) {
        final w = _PoolWorker(
          workerId: i,
          taskRegistry: taskRegistry,
          debugName: '$debugName-Worker$i',
        );
        _workers.add(w);

        initFutures.add(w.init().then((_) {
          debugPrint('[$debugName-Worker$i] Worker ready');
        }));
      }

      await Future.wait(initFutures);

      _initialized = true;
      if (!_ready.isCompleted) {
        _ready.complete();
      }

      debugPrint('[$debugName] Pool ready with $poolSize workers');
    });
  }

  /// Get least busy worker (load balancing)
  _PoolWorker _leastBusy() {
    if (_workers.isEmpty) {
      throw StateError('No workers available in pool');
    }
    return _workers.reduce((a, b) => a.activeTasks < b.activeTasks ? a : b);
  }

  Future<T> runTask<T>(
    String taskId,
    IsolateTask task, {
    Duration timeout = const Duration(seconds: 30),
    void Function(IsolateTaskProgress)? onProgress,
    required CancellationToken token,
  }) async {
    // Ensure pool is fully initialized and ready before dispatching
    await whenReady;
    return _leastBusy().runTask(
      taskId,
      task,
      timeout: timeout,
      onProgress: onProgress,
      token: token,
    );
  }

  void dispose() {
    // If there are active tasks, we still allow forceful dispose from controller.
    for (final w in _workers) {
      w.dispose();
    }
    _workers.clear();
    _initialized = false;
    // reset _ready so init can be called again if needed
    // (create new completer)
    try {
      // ignore: invalid_use_of_visible_for_testing_member
      if (!_ready.isCompleted) {
        _ready.complete();
      }
    } catch (_) {}
    debugPrint('[$debugName] 🧹 Pool disposed');
  }

  Map<String, dynamic> getStatus() => {
        'poolSize': poolSize,
        'initialized': _initialized,
        'workers': _workers.map((w) => w.getStatus()).toList(),
        'totalActive': _workers.fold(0, (sum, w) => sum + w.activeTasks),
        'totalCompleted': _workers.fold(0, (sum, w) => sum + w.totalCompleted),
      };
}

// ==================== MAIN CONTROLLER ====================

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
  final _lock = Lock();
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
  Future<void> init() async => _lock.synchronized(() async {
        if (_isolate != null || (_pool != null && _pool!._initialized)) return;
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
              _PoolWorker._isolateWorker,
              _IsolateInitData(
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
    void Function(IsolateTaskProgress)? onProgress,
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

    _queue.add(queued);
    debugPrint(
        '[$debugName:$_id] 📥 Task $taskId queued (priority: ${task.priority})');
    _processQueue();

    return TaskHandle._(taskId: taskId, future: completer.future, token: token);
  }

  void _processQueue() {
    scheduleMicrotask(() {
      while (_activeTasks < maxConcurrentTasks && _queue.isNotEmpty) {
        final qt = _queue.removeFirst();

        // Skip cancelled tasks
        if (qt.cancellationToken.isCancelled) {
          if (!qt.completer.isCompleted) {
            if (!qt._done) {
              qt._done = true;
              qt.completer.completeError(TaskCancelledException(qt.taskId));
            }
          }
          debugPrint(
              '[$debugName:$_id] ⏭️  Skipped cancelled task ${qt.taskId}');
          continue;
        }

        _activeTasks++;
        _running[qt.taskId] = qt;
        _executeTask(qt);
      }
    });
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

        _sendPort!.send(_IsolateMessage(
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
            qt.onProgress?.call(IsolateTaskProgress(
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

          if (raw is Map && raw.containsKey('error')) {
            final err = raw['error'].toString();
            if (err.contains('cancelled')) {
              throw TaskCancelledException(qt.taskId);
            }
            throw Exception(err);
          }
          result = raw;
        } finally {
          // FIXED: remove onCancel exactly once and ensure ports closed
          qt.cancellationToken.removeListener(onCancel);
          pp?.close();
          rp.close();
          cp.close();
        }
      }

      if (!qt.cancellationToken.isCancelled && !qt.completer.isCompleted) {
        if (!qt._done) {
          qt._done = true;
          qt.completer.complete(result);
        }
        _totalCompleted++;

        final duration = DateTime.now().difference(startTime);
        debugPrint(
            '[$debugName:$_id] ✅ Task ${qt.taskId} completed in ${duration.inMilliseconds}ms');
      }
    } on TaskCancelledException {
      if (!qt.completer.isCompleted) {
        if (!qt._done) {
          qt._done = true;
          qt.completer.completeError(TaskCancelledException(qt.taskId));
        }
      }
      debugPrint('[$debugName:$_id] 🚫 Task ${qt.taskId} cancelled');
    } on TaskTimeoutException catch (e) {
      if (!qt.completer.isCompleted) {
        if (!qt._done) {
          qt._done = true;
          qt.completer.completeError(e);
        }
      }
      debugPrint('[$debugName:$_id] ⏱️  Task ${qt.taskId} timeout');
    } catch (e, s) {
      if (!qt.completer.isCompleted) {
        if (!qt._done) {
          qt._done = true;
          qt.completer.completeError(e, s);
        }
      }
      debugPrint('[$debugName:$_id] ❌ Task ${qt.taskId} error: $e');
    } finally {
      _activeTasks--;
      _running.remove(qt.taskId);
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
  void cancelAll() {
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
      for (final worker in _pool!._workers) {
        try {
          worker._sendPort?.send({'type': 'cancel_all'});
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
  void dispose({bool force = false}) {
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
      if (!task.completer.isCompleted) {
        task.cancellationToken.cancel();
        task.completer.completeError(TaskCancelledException(task.taskId));
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
      'initialized': _isolate != null || (_pool != null && _pool!._initialized),
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
