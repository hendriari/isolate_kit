import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:isolate_kit/isolate_kit.dart';

class PoolWorker {
  final int workerId;
  final IsolateTaskRegistry taskRegistry;
  final String debugName;
  Isolate? _isolate;
  SendPort? sendPort;
  int activeTasks = 0;
  int totalCompleted = 0;
  final Map<String, SendPort> _cancelPorts = {};
  DateTime? _lastUsed;

  // Mechanism to prevent double initialization
  bool _isInitializing = false;
  Completer<void>? _initCompleter;

  PoolWorker({
    required this.workerId,
    required this.taskRegistry,
    required this.debugName,
  });

  Future<void> init() async {
    if (_isInitializing) return _initCompleter?.future;

    _isInitializing = true;
    _initCompleter = Completer<void>();

    try {
      final rp = ReceivePort();
      _isolate = await Isolate.spawn(
        workerEntry,
        IsolateInitData(
            sendPort: rp.sendPort, taskRegistry: taskRegistry.clone()),
        debugName: debugName,
        errorsAreFatal: false,
      );

      sendPort = await rp.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Worker init timeout'),
      ) as SendPort;
      rp.close();
      debugPrint('[$debugName] ✅ Worker initialized and ready');
    } catch (e) {
      debugPrint('[$debugName] ❌ Worker init failed: $e');
      dispose();
      rethrow;
    } finally {
      _isInitializing = false;
      _initCompleter?.complete();
    }
  }

  /// Ensure Isolate is ready to use before submitting the assignment.
  Future<void> _ensureReady() async {
    if (_isolate == null || sendPort == null) {
      await init();
    }
  }

  Future<T> runTask<T>(
    String taskId,
    IsolateTask task, {
    required Duration timeout,
    void Function(TaskProgress)? onProgress,
    required CancellationToken token,
  }) async {
    await _ensureReady();

    activeTasks++;
    _lastUsed = DateTime.now();

    final response = ReceivePort();
    final progress = onProgress != null ? ReceivePort() : null;
    final cancelCtrl = ReceivePort();

    VoidCallback? onCancel;
    bool completedSuccessfully = false;
    bool poisoned = false; // Flag if isolate crashes

    try {
      if (sendPort == null) throw Exception('Worker sendPort is null');

      sendPort!.send(IsolateMessage(
        taskId: taskId,
        taskType: task.taskType,
        command: task.command,
        payload: task.payload,
        replyPort: response.sendPort,
        progressPort: progress?.sendPort,
        cancelControlPort: cancelCtrl.sendPort,
        transferables: task.transferables,
      ));

      // 1. Handshake for cancellation
      SendPort? cancelPort;
      try {
        cancelPort = await cancelCtrl.first.timeout(
          const Duration(seconds: 5),
        ) as SendPort;
      } on TimeoutException {
        debugPrint(
            '[$debugName] 🚨 Handshake timeout - Isolate unresponsive. Marking as poisoned.');
        poisoned = true;
        throw TimeoutException('Cancel handshake timeout');
      }

      _cancelPorts[taskId] = cancelPort;

      onCancel = () {
        try {
          cancelPort?.send('cancel');
          debugPrint('[$debugName] 🚫 Sent cancel signal for task $taskId');
        } catch (e) {
          debugPrint('[$debugName] Failed to send cancel signal: $e');
        }
      };

      token.addListener(onCancel);

      // 2. Listener for progress
      progress?.listen((msg) {
        if (msg is Map && !token.isCancelled) {
          onProgress?.call(TaskProgress(
            percentage: (msg['percentage'] as num?)?.toDouble() ?? 0.0,
            message: msg['message'] as String?,
            data: msg['data'] as Map<String, dynamic>?,
          ));
        }
      });

      // 3. Waiting for the results of the assignment
      final result = await response.first.timeout(
        timeout,
        onTimeout: () {
          debugPrint(
              '[$debugName] ⏱️ Task $taskId timed out. Isolate might be stuck. Marking as poisoned.');
          poisoned = true;
          throw TaskTimeoutException(taskId, timeout);
        },
      );

      if (result is Map && result.containsKey('error')) {
        final err = result['error'].toString();
        if (err.contains('cancelled')) {
          throw TaskCancelledException(taskId);
        }
        throw Exception('Task error: $err');
      }

      totalCompleted++;
      completedSuccessfully = true;
      return result as T;
    } finally {
      // Resource cleanup
      if (onCancel != null) {
        token.removeListener(onCancel);
      }
      _cancelPorts.remove(taskId);
      response.close();
      progress?.close();
      cancelCtrl.close();

      activeTasks = math.max(0, activeTasks - 1);

      // If Isolate is stuck/poisoned, we kill it now so the next task can trigger a fresh init().
      if (poisoned) {
        debugPrint('[$debugName] 🧹 Killing poisoned worker to recover...');
        dispose();
      }

      if (completedSuccessfully) {
        debugPrint(
            '[$debugName] ✅ Task $taskId completed (Total: $totalCompleted)');
      }
    }
  }

  void dispose() {
    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _isolate = null;
    sendPort = null;
    _cancelPorts.clear();
    debugPrint('[$debugName] 🧹 Worker disposed');
  }

  Map<String, dynamic> getStatus() => {
        'workerId': workerId,
        'activeTasks': activeTasks,
        'totalCompleted': totalCompleted,
        'lastUsed': _lastUsed?.toIso8601String(),
        'isAlive': _isolate != null,
      };

  static void workerEntry(IsolateInitData init) => isolateWorker(init);

  static void isolateWorker(IsolateInitData init) {
    final mainPort = ReceivePort();
    init.sendPort.send(mainPort.sendPort);

    final registry = init.taskRegistry.clone();

    mainPort.listen((msg) async {
      if (msg is Map && msg['type'] == 'cancel_all') return;
      if (msg is! IsolateMessage) return;

      final token = CancellationToken();
      ReceivePort? cancelRp;

      try {
        if (msg.cancelControlPort != null) {
          cancelRp = ReceivePort();
          msg.cancelControlPort!.send(cancelRp.sendPort);
          cancelRp.listen((_) => token.cancel());
        }

        final task = registry.create(
          msg.taskType,
          msg.payload,
          transferables: msg.transferables,
        );

        if (task == null) {
          throw Exception('Task "${msg.taskType}" not registered');
        }

        // Give the event loop a little breather before heavy execution
        await Future.delayed(Duration.zero);

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
