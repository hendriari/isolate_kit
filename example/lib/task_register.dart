import 'dart:isolate';
import 'dart:typed_data';

import 'package:example/task/fibonacci_task.dart';
import 'package:example/task/heavy_normalize_data_task.dart';
import 'package:example/task/heavy_csv_analytics_task.dart';
import 'package:example/task/heavy_file_crypto_task.dart';
import 'package:example/task/heavy_image_processing_task.dart';
import 'package:example/task/heavy_image_resize_task.dart';
import 'package:isolate_kit/isolate_kit.dart';

IsolateTaskRegistry getTaskRegistry() {
  final registry = IsolateTaskRegistry();

  registry.register<FibonacciTask>('FibonacciTask', _createFibonacciTask);

  registry.register<HeavyImageProcessingTask>(
    'HeavyImageProcessingTask',
    _createImageProcessingTask,
  );

  registry.register<HeavyImageResizeTask>(
    'HeavyImageResizeTask',
    _createImageResizeTask,
  );

  registry.register<HeavyCsvAnalyticsTask>(
    'HeavyCsvAnalyticsTask',
    _createCsvAnalyticsTask,
  );

  registry.register<HeavyFileCryptoTask>(
    'HeavyFileCryptoTask',
    _createFileCryptoTask,
  );

  registry.register<HeavyNormalizeDataTask>(
    'HeavyNormalizeDataTask',
    _createNormalizeDataTask,
  );

  return registry;
}

// Factory functions
FibonacciTask _createFibonacciTask(
  Map<String, dynamic> payload,
  List<TransferableTypedData>? transferables,
) {
  return FibonacciTask(payload);
}

HeavyImageProcessingTask _createImageProcessingTask(
  Map<String, dynamic> payload,
  List<TransferableTypedData>? transferables,
) {
  final imageData = transferables != null && transferables.isNotEmpty
      ? transferables[0].materialize().asUint8List()
      : Uint8List(0);
  return HeavyImageProcessingTask(payload, imageData);
}

HeavyImageResizeTask _createImageResizeTask(
  Map<String, dynamic> payload,
  List<TransferableTypedData>? transferables,
) {
  final imageData = transferables != null && transferables.isNotEmpty
      ? transferables[0].materialize().asUint8List()
      : Uint8List(0);
  return HeavyImageResizeTask(payload, imageData);
}

HeavyCsvAnalyticsTask _createCsvAnalyticsTask(
  Map<String, dynamic> payload,
  List<TransferableTypedData>? transferables,
) {
  return HeavyCsvAnalyticsTask(payload);
}

HeavyFileCryptoTask _createFileCryptoTask(
  Map<String, dynamic> payload,
  List<TransferableTypedData>? transferables,
) {
  final fileData = transferables != null && transferables.isNotEmpty
      ? transferables[0].materialize().asUint8List()
      : Uint8List(0);
  return HeavyFileCryptoTask(payload, fileData);
}

HeavyNormalizeDataTask _createNormalizeDataTask(
  Map<String, dynamic> payload,
  List<TransferableTypedData>? transferables,
) {
  return HeavyNormalizeDataTask(payload);
}
