import 'dart:isolate';

/// Represents a message sent from the main isolate to a worker isolate to request task execution.
class IsolateMessage {
  /// Unique identifier for the task.
  final String taskId;

  /// String identifier for the task type, used by [IsolateTaskRegistry].
  final String taskType;

  /// Command or instruction for the task.
  final dynamic command;

  /// Arbitrary payload data for the task.
  final Map<String, dynamic> payload;

  /// The [SendPort] where the task result will be sent.
  final SendPort replyPort;

  /// Optional [SendPort] for sending progress updates.
  final SendPort? progressPort;

  /// Optional [SendPort] for managing task cancellation.
  final SendPort? cancelControlPort;

  /// Optional list of [TransferableTypedData] to be passed to the isolate efficiently.
  final List<TransferableTypedData>? transferables;

  /// Creates a message to be sent to a worker isolate.
  IsolateMessage({
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
