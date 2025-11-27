import 'dart:isolate';

import 'package:isolate_kit/isolate_kit.dart';

class IsolateInitData {
  final SendPort sendPort;
  final IsolateTaskRegistry taskRegistry;

  IsolateInitData({required this.sendPort, required this.taskRegistry});
}
