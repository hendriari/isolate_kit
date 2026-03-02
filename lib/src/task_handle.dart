import 'package:isolate_kit/isolate_kit.dart';

/// A handle for a task that has been submitted to [IsolateKit].
///
/// It provides access to the task's result via [future], and allows
/// for cancelling the task through [cancel].
class TaskHandle<T> {
  /// Unique identifier assigned to the task.
  final String taskId;

  /// A future that will complete with the task's result or an error.
  final Future<T> future;

  final CancellationToken _token;

  /// Timestamp when the task handle was created.
  final DateTime createdAt;

  /// Returns true if the task has been cancelled.
  bool get isCancelled => _token.isCancelled;

  /// A future that completes when the task is cancelled.
  Future<void> get cancelled => _token.cancelled;

  /// Internal constructor for creating a [TaskHandle].
  TaskHandle.internal({
    required this.taskId,
    required this.future,
    required CancellationToken token,
  })  : _token = token,
        createdAt = DateTime.now();

  /// Signals that the task should be cancelled.
  /// Returns true if the cancellation signal was sent successfully.
  Future<bool> cancel() => _token.cancel();

  /// Waits for the task to complete, but throws a [TimeoutException] if it
  /// takes longer than the specified [duration].
  Future<T> timeout(Duration duration, {T Function()? onTimeout}) {
    return future.timeout(
      duration,
      onTimeout: onTimeout != null ? () => onTimeout() : null,
    );
  }
}
