import 'dart:async';

import 'package:flutter/material.dart';
import 'package:isolate_kit/isolate_kit.dart';
import 'package:synchronized/synchronized.dart';

class IsolatePool {
  final int poolSize;
  final IsolateTaskRegistry taskRegistry;
  final String debugName;
  final List<PoolWorker> workers = [];
  final Completer<void> _ready = Completer<void>();
  bool initialized = false;
  final Lock _initLock = Lock();

  IsolatePool({
    required this.poolSize,
    required this.taskRegistry,
    this.debugName = 'Pool',
  });

  Future<void> get whenReady => _ready.future;

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

  /// Get least busy worker (load balancing)
  PoolWorker _leastBusy() {
    if (workers.isEmpty) {
      throw StateError('No workers available in pool');
    }
    return workers.reduce((a, b) => a.activeTasks < b.activeTasks ? a : b);
  }

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

  Map<String, dynamic> getStatus() => {
        'poolSize': poolSize,
        'initialized': initialized,
        'workers': workers.map((w) => w.getStatus()).toList(),
        'totalActive': workers.fold(0, (sum, w) => sum + w.activeTasks),
        'totalCompleted': workers.fold(0, (sum, w) => sum + w.totalCompleted),
      };
}
