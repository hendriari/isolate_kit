import 'dart:isolate';

import 'package:isolate_kit/isolate_kit.dart';

/// A registry for [IsolateTask] types.
///
/// This registry is used to map task type strings to factory functions that
/// can create task instances. This is essential for rebuilding tasks
/// in the worker isolate based on the type information sent from the main isolate.
class IsolateTaskRegistry {
  final Map<
      String,
      IsolateTask Function(
          Map<String, dynamic>, List<TransferableTypedData>?)> _factories = {};
  final Map<Type, String> _typeToString = {};

  /// Registers a task type with a factory function.
  ///
  /// Parameters:
  /// - [taskType]: A unique string identifying the task.
  /// - [factory]: A function that takes a payload and an optional list of transferables to create an [IsolateTask].
  void register<T extends IsolateTask>(
    String taskType,
    T Function(Map<String, dynamic>, List<TransferableTypedData>?) factory,
  ) {
    _factories[taskType] = factory;
    _typeToString[T] = taskType;
  }

  /// Unregisters a previously registered task type.
  void unregister(String taskType) {
    _factories.remove(taskType);
    _typeToString.removeWhere((key, value) => value == taskType);
  }

  /// Creates a task instance from a type string and payload.
  /// Returns null if the type is not registered.
  IsolateTask? create(
    String taskType,
    Map<String, dynamic> payload, {
    List<TransferableTypedData>? transferables,
  }) {
    final factory = _factories[taskType];
    return factory?.call(payload, transferables);
  }

  /// Returns a list of all currently registered task type strings.
  List<String> get registeredTypes => _factories.keys.toList();

  /// Returns true if a task type is already registered.
  bool isRegistered(String taskType) => _factories.containsKey(taskType);

  /// Clears all registrations from the registry.
  void clear() {
    _factories.clear();
    _typeToString.clear();
  }

  /// Creates a clone of the registry.
  /// This is used internally to pass the task registry to new isolates.
  IsolateTaskRegistry clone() {
    final cloned = IsolateTaskRegistry();
    cloned._factories.addAll(_factories);
    cloned._typeToString.addAll(_typeToString);
    return cloned;
  }
}
