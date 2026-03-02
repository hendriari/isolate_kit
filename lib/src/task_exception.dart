/// Exception thrown when a task is explicitly cancelled.
class TaskCancelledException implements Exception {
  /// Unique identifier for the cancelled task.
  final String taskId;

  /// Creates a [TaskCancelledException] with the given [taskId].
  TaskCancelledException([this.taskId = '']);

  @override
  String toString() => 'Task $taskId was cancelled';
}

/// Exception thrown when a task exceeds its allocated execution time.
class TaskTimeoutException implements Exception {
  /// Unique identifier for the timed-out task.
  final String taskId;

  /// The duration that was exceeded.
  final Duration timeout;

  /// Creates a [TaskTimeoutException] with the given [taskId] and [timeout].
  TaskTimeoutException(this.taskId, this.timeout);

  @override
  String toString() => 'Task $taskId timed out after ${timeout.inSeconds}s';
}
