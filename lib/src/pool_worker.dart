import 'dart:async';
import 'dart:isolate';

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

  PoolWorker({
    required this.workerId,
    required this.taskRegistry,
    required this.debugName,
  });

  Future<void> init() async {
    final rp = ReceivePort();
    _isolate = await Isolate.spawn(
      workerEntry,
      IsolateInitData(
          sendPort: rp.sendPort, taskRegistry: taskRegistry.clone()),
      debugName: debugName,
      errorsAreFatal: false,
    );
    try {
      sendPort = await rp.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Worker init timeout'),
      ) as SendPort;
    } finally {
      rp.close();
    }
    debugPrint('[$debugName] ✅ Worker initialized');
  }

  Future<T> runTask<T>(
    String taskId,
    IsolateTask task, {
    required Duration timeout,
    void Function(TaskProgress)? onProgress,
    required CancellationToken token,
  }) async {
    activeTasks++;
    _lastUsed = DateTime.now();

    final response = ReceivePort();
    final progress = onProgress != null ? ReceivePort() : null;
    final cancelCtrl = ReceivePort();

    // store reference for the onCancel callback so we can remove it later
    VoidCallback? onCancel;
    bool completedSuccessfully = false;

    try {
      // _sendPort must not be null here; caller should await whenReady
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
          onProgress?.call(TaskProgress(
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

      // Task completed successfully
      totalCompleted++;
      completedSuccessfully = true;
      return result as T;
    } finally {
      // Clean up resources
      if (onCancel != null) {
        token.removeListener(onCancel);
      }
      _cancelPorts.remove(taskId);
      response.close();
      progress?.close();
      cancelCtrl.close();
      activeTasks--;

      // Only log success if task actually completed
      if (completedSuccessfully) {
        debugPrint(
            '[$debugName] ✅ Worker completed task $taskId (total: $totalCompleted)');
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
      };

  static void workerEntry(IsolateInitData init) => isolateWorker(init);

  static void isolateWorker(IsolateInitData init) {
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

      if (msg is! IsolateMessage) return;

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
