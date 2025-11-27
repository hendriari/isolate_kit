import 'dart:isolate';

import 'package:isolate_kit/isolate_kit.dart';

/// Base class for all background tasks
abstract class IsolateTask<TCommand, TResult> {
  TCommand get command;

  Map<String, dynamic> get payload;

  String get taskType => runtimeType.toString();

  int get priority => TaskPriority.normal;

  List<TransferableTypedData>? get transferables => null;

  /// Execute task with cancellation and progress support
  Future<TResult> execute({
    void Function(TaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  });

  /// Optional: Estimate task duration for better scheduling
  Duration? get estimatedDuration => null;

  /// Optional: Task metadata for debugging
  Map<String, dynamic> get metadata => {};
}