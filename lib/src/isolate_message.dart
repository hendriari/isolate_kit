import 'dart:isolate';

class IsolateMessage {
  final String taskId;
  final String taskType;
  final dynamic command;
  final Map<String, dynamic> payload;
  final SendPort replyPort;
  final SendPort? progressPort;
  final SendPort? cancelControlPort;
  final List<TransferableTypedData>? transferables;

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
