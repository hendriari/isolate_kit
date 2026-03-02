import 'dart:isolate';

import 'package:isolate_kit/isolate_kit.dart';

/// Data passed from the main isolate to a newly spawned worker isolate during initialization.
class IsolateInitData {
  /// The [SendPort] for sending communication back to the main isolate.
  final SendPort sendPort;

  /// The [IsolateTaskRegistry] containing the task definitions the worker can execute.
  final IsolateTaskRegistry taskRegistry;

  /// Creates initialization data for a new isolate.
  IsolateInitData({required this.sendPort, required this.taskRegistry});
}
