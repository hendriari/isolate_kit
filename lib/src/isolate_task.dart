import 'dart:isolate';

import 'package:isolate_kit/isolate_kit.dart';

/// Base class for all background tasks that will be executed in an isolate.
///
/// Subclasses should define [TCommand] (the instruction type) and [TResult] (the return type).
abstract class IsolateTask<TCommand, TResult> {
  /// The command or instruction for the task.
  TCommand get command;

  /// Arbitrary data payload required by the task.
  Map<String, dynamic> get payload;

  /// A unique string identifying the task type, used for registration in [IsolateTaskRegistry].
  /// Defaults to the class name.
  String get taskType => runtimeType.toString();

  /// The execution priority of the task.
  /// Tasks with higher priority (lower numeric value) are processed first from the queue.
  int get priority => TaskPriority.normal;

  /// Optional list of [TransferableTypedData] to be passed to the isolate efficiently.
  List<TransferableTypedData>? get transferables => null;

  /// The actual execution logic for the task.
  ///
  /// Parameters:
  /// - [sendProgress]: A callback to report progress back to the main isolate.
  /// - [cancellationToken]: A token to monitor if the task has been cancelled.
  Future<TResult> execute({
    void Function(TaskProgress progress)? sendProgress,
    CancellationToken? cancellationToken,
  });

  /// Optional: Estimated duration of the task. Can be used for advanced scheduling.
  Duration? get estimatedDuration => null;

  /// Optional: Key-value pairs of metadata for debugging or logging.
  Map<String, dynamic> get metadata => {};
}
