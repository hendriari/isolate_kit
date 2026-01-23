import 'package:isolate_kit/isolate_kit.dart';

/// Public task handle with cancellation support
class TaskHandle<T> {
  final String taskId;
  final Future<T> future;
  final CancellationToken _token;
  final DateTime createdAt;

  bool get isCancelled => _token.isCancelled;

  Future<void> get cancelled => _token.cancelled;

  TaskHandle.internal({
    required this.taskId,
    required this.future,
    required CancellationToken token,
  })  : _token = token,
        createdAt = DateTime.now();

  Future<bool> cancel() => _token.cancel();

  /// Wait with timeout
  Future<T> timeout(Duration duration, {T Function()? onTimeout}) {
    return future.timeout(
      duration,
      onTimeout: onTimeout != null ? () => onTimeout() : null,
    );
  }
}
