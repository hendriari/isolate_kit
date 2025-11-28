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
