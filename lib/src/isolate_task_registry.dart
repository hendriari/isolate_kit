import 'dart:isolate';

import 'package:isolate_kit/isolate_kit.dart';

class IsolateTaskRegistry {
  final Map<
      String,
      IsolateTask Function(
          Map<String, dynamic>, List<TransferableTypedData>?)> _factories = {};
  final Map<Type, String> _typeToString = {};

  void register<T extends IsolateTask>(
    String taskType,
    T Function(Map<String, dynamic>, List<TransferableTypedData>?) factory,
  ) {
    _factories[taskType] = factory;
    _typeToString[T] = taskType;
  }

  /// Unregister a task type
  void unregister(String taskType) {
    _factories.remove(taskType);
    _typeToString.removeWhere((key, value) => value == taskType);
  }

  IsolateTask? create(
    String taskType,
    Map<String, dynamic> payload, {
    List<TransferableTypedData>? transferables,
  }) {
    final factory = _factories[taskType];
    return factory?.call(payload, transferables);
  }

  List<String> get registeredTypes => _factories.keys.toList();

  bool isRegistered(String taskType) => _factories.containsKey(taskType);

  void clear() {
    _factories.clear();
    _typeToString.clear();
  }

  /// Create a copy of registry for isolate
  IsolateTaskRegistry clone() {
    final cloned = IsolateTaskRegistry();
    cloned._factories.addAll(_factories);
    cloned._typeToString.addAll(_typeToString);
    return cloned;
  }
}
