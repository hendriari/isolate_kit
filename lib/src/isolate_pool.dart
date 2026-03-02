import 'dart:async';

import 'package:flutter/material.dart';
import 'package:isolate_kit/isolate_kit.dart';
import 'package:synchronized/synchronized.dart';

/// A pool of isolate workers that can process tasks in parallel.
///
/// The pool manages a fixed number of isolates, distributing tasks among them
/// based on their current load to achieve efficient multi-threading.
class IsolatePool {
  /// Number of isolate workers in the pool.
  final int poolSize;

  /// The registry of tasks that the pool's workers can execute.
  final IsolateTaskRegistry taskRegistry;

  /// Name of the pool for logging and debugging.
  final String debugName;

  /// List of [PoolWorker] instances managed by this pool.
  final List<PoolWorker> workers = [];

  final Completer<void> _ready = Completer<void>();
  bool initialized = false;
  final Lock _initLock = Lock();

  /// Creates an [IsolatePool] with the specified configuration.
  IsolatePool({
    required this.poolSize,
    required this.taskRegistry,
    this.debugName = 'Pool',
  });

  /// A future that completes when all workers in the pool are initialized and ready.
  Future<void> get whenReady => _ready.future;

  /// Initializes the pool by spawning the requested number of workers.
  Future<void> init() async {
    await _initLock.synchronized(() async {
      if (initialized) return;

      debugPrint('[$debugName] Initializing pool with $poolSize workers...');

      final List<Future<void>> initFutures = [];

      for (int i = 0; i < poolSize; i++) {
        final w = PoolWorker(
          workerId: i,
          taskRegistry: taskRegistry,
          debugName: '$debugName-Worker$i',
        );
        workers.add(w);

        initFutures.add(w.init().then((_) {
          debugPrint('[$debugName-Worker$i] Worker ready');
        }));
      }

      await Future.wait(initFutures);

      initialized = true;
      if (!_ready.isCompleted) {
        _ready.complete();
      }

      debugPrint('[$debugName] Pool ready with $poolSize workers');
    });
  }

  /// Selects the [PoolWorker] with the fewest number of active tasks.
  PoolWorker _leastBusy() {
    if (workers.isEmpty) {
      throw StateError('No workers available in pool');
    }
    return workers.reduce((a, b) => a.activeTasks < b.activeTasks ? a : b);
  }

  /// Dispatches a task to the least busy worker in the pool.
  ///
  /// Parameters:
  /// - [taskId]: Unique identifier for the task.
  /// - [task]: The [IsolateTask] to execute.
  /// - [timeout]: Maximum time for the task to complete.
  /// - [onProgress]: Callback for receiving progress updates.
  /// - [token]: Token to monitor for cancellation.
  Future<T> runTask<T>(
    String taskId,
    IsolateTask task, {
    Duration timeout = const Duration(seconds: 30),
    void Function(TaskProgress)? onProgress,
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

  /// Shuts down all workers in the pool and releases resources.
  void dispose() {
    // If there are active tasks, we still allow forceful dispose from controller.
    for (final w in workers) {
      w.dispose();
    }
    workers.clear();
    initialized = false;
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

  /// Returns a status summary of the pool and its individual workers.
  Map<String, dynamic> getStatus() => {
        'poolSize': poolSize,
        'initialized': initialized,
        'workers': workers.map((w) => w.getStatus()).toList(),
        'totalActive': workers.fold(0, (sum, w) => sum + w.activeTasks),
        'totalCompleted': workers.fold(0, (sum, w) => sum + w.totalCompleted),
      };
}
