part of 'isolate_kit_main.dart';

class _QueuedTask implements Comparable<_QueuedTask> {
  bool _done = false;

  final String taskId;
  final IsolateTask task;
  final Duration timeout;
  final Completer<dynamic> completer;
  final void Function(TaskProgress)? onProgress;
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
