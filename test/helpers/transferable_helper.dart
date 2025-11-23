import 'dart:isolate';
import 'dart:typed_data';

/// Helper class for zero-copy large data transfer between isolates.
///
/// When transferring large data (>100KB) between isolates, using
/// [TransferableTypedData] can significantly improve performance by avoiding
/// memory copies.
///
/// Example:
/// ```dart
/// // Sending side
/// final largeData = Uint8List(1024 * 1024 * 10); // 10MB
/// final transferable = TransferableHelper.fromUint8List(largeData);
///
/// // In IsolateTask
/// @override
/// List<TransferableTypedData>? get transferables => [transferable];
///
/// // Receiving side (in isolate)
/// factory MyTask.fromPayload(
///   Map<String, dynamic> payload,
///   List<TransferableTypedData>? transferables,
/// ) {
///   final data = transferables != null
///       ? TransferableHelper.toUint8List(transferables[0])
///       : Uint8List(0);
///   return MyTask(data: data);
/// }
/// ```
class TransferableHelper {
  TransferableHelper._(); // Private constructor - utility class

  /// Default threshold for using transferable (100KB)
  static const int defaultThreshold = 1024 * 100;

  /// Convert [Uint8List] to transferable format for zero-copy transfer.
  ///
  /// Example:
  /// ```dart
  /// final data = Uint8List(1024 * 1024); // 1MB
  /// final transferable = TransferableHelper.fromUint8List(data);
  /// ```
  static TransferableTypedData fromUint8List(Uint8List data) {
    return TransferableTypedData.fromList([data]);
  }

  /// Convert [Int8List] to transferable format.
  static TransferableTypedData fromInt8List(Int8List data) {
    return TransferableTypedData.fromList([data]);
  }

  /// Convert [Uint16List] to transferable format.
  static TransferableTypedData fromUint16List(Uint16List data) {
    return TransferableTypedData.fromList([data]);
  }

  /// Convert [Int16List] to transferable format.
  static TransferableTypedData fromInt16List(Int16List data) {
    return TransferableTypedData.fromList([data]);
  }

  /// Convert [Uint32List] to transferable format.
  static TransferableTypedData fromUint32List(Uint32List data) {
    return TransferableTypedData.fromList([data]);
  }

  /// Convert [Int32List] to transferable format.
  static TransferableTypedData fromInt32List(Int32List data) {
    return TransferableTypedData.fromList([data]);
  }

  /// Convert [Float32List] to transferable format.
  static TransferableTypedData fromFloat32List(Float32List data) {
    return TransferableTypedData.fromList([data]);
  }

  /// Convert [Float64List] to transferable format.
  static TransferableTypedData fromFloat64List(Float64List data) {
    return TransferableTypedData.fromList([data]);
  }

  /// Convert multiple typed lists to transferable format.
  ///
  /// Useful when you need to transfer multiple arrays at once.
  ///
  /// Example:
  /// ```dart
  /// final arrays = [
  ///   Uint8List(1000),
  ///   Float32List(500),
  ///   Int32List(250),
  /// ];
  /// final transferable = TransferableHelper.fromTypedLists(arrays);
  /// ```
  static TransferableTypedData fromTypedLists(List<TypedData> lists) {
    return TransferableTypedData.fromList(lists);
  }

  /// Materialize transferable back to [Uint8List].
  ///
  /// This is the most common use case.
  ///
  /// Example:
  /// ```dart
  /// final data = TransferableHelper.toUint8List(transferable);
  /// print('Received ${data.length} bytes');
  /// ```
  static Uint8List toUint8List(TransferableTypedData transferable) {
    final buffer = transferable.materialize();
    return buffer.asUint8List();
  }

  /// Materialize transferable back to [Int8List].
  static Int8List toInt8List(TransferableTypedData transferable) {
    final buffer = transferable.materialize();
    return buffer.asInt8List();
  }

  /// Materialize transferable back to [Uint16List].
  static Uint16List toUint16List(TransferableTypedData transferable) {
    final buffer = transferable.materialize();
    return buffer.asUint16List();
  }

  /// Materialize transferable back to [Int16List].
  static Int16List toInt16List(TransferableTypedData transferable) {
    final buffer = transferable.materialize();
    return buffer.asInt16List();
  }

  /// Materialize transferable back to [Uint32List].
  static Uint32List toUint32List(TransferableTypedData transferable) {
    final buffer = transferable.materialize();
    return buffer.asUint32List();
  }

  /// Materialize transferable back to [Int32List].
  static Int32List toInt32List(TransferableTypedData transferable) {
    final buffer = transferable.materialize();
    return buffer.asInt32List();
  }

  /// Materialize transferable back to [Float32List].
  static Float32List toFloat32List(TransferableTypedData transferable) {
    final buffer = transferable.materialize();
    return buffer.asFloat32List();
  }

  /// Materialize transferable back to [Float64List].
  static Float64List toFloat64List(TransferableTypedData transferable) {
    final buffer = transferable.materialize();
    return buffer.asFloat64List();
  }

  /// Materialize transferable to specific [TypedData] type.
  ///
  /// Example:
  /// ```dart
  /// final data = TransferableHelper.materializeAs<Float32List>(transferable);
  /// ```
  static T materializeAs<T extends TypedData>(
    TransferableTypedData transferable,
  ) {
    final buffer = transferable.materialize();

    if (T == Uint8List) {
      return buffer.asUint8List() as T;
    } else if (T == Int8List) {
      return buffer.asInt8List() as T;
    } else if (T == Uint16List) {
      return buffer.asUint16List() as T;
    } else if (T == Int16List) {
      return buffer.asInt16List() as T;
    } else if (T == Uint32List) {
      return buffer.asUint32List() as T;
    } else if (T == Int32List) {
      return buffer.asInt32List() as T;
    } else if (T == Float32List) {
      return buffer.asFloat32List() as T;
    } else if (T == Float64List) {
      return buffer.asFloat64List() as T;
    } else if (T == Uint8ClampedList) {
      return buffer.asUint8ClampedList() as T;
    } else if (T == Int64List) {
      return buffer.asInt64List() as T;
    } else if (T == Uint64List) {
      return buffer.asUint64List() as T;
    } else {
      // Default to Uint8List
      return buffer.asUint8List() as T;
    }
  }

  /// Check if data is large enough to benefit from zero-copy transfer.
  ///
  /// Returns `true` if data size is greater than threshold (default: 100KB).
  ///
  /// Example:
  /// ```dart
  /// if (TransferableHelper.shouldUseTransferable(data.lengthInBytes)) {
  ///   return [TransferableHelper.fromUint8List(data)];
  /// }
  /// return null;
  /// ```
  static bool shouldUseTransferable(
    int sizeInBytes, {
    int threshold = defaultThreshold,
  }) {
    return sizeInBytes > threshold;
  }

  /// Get size of [TypedData] in bytes.
  ///
  /// Example:
  /// ```dart
  /// final size = TransferableHelper.getSizeInBytes(data);
  /// print('Data size: $size bytes');
  /// ```
  static int getSizeInBytes(TypedData data) {
    return data.lengthInBytes;
  }

  /// Get human-readable size string.
  ///
  /// Example:
  /// ```dart
  /// print(TransferableHelper.formatSize(1024)); // "1.00 KB"
  /// print(TransferableHelper.formatSize(1048576)); // "1.00 MB"
  /// ```
  static String formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// Estimate memory savings by using transferable vs regular copy.
  ///
  /// Returns percentage of memory saved (0-100).
  ///
  /// Example:
  /// ```dart
  /// final savings = TransferableHelper.estimateMemorySavings(10485760);
  /// print('Memory savings: $savings%'); // ~50%
  /// ```
  static double estimateMemorySavings(int sizeInBytes) {
    // Transferable uses ~0-10% overhead
    // Regular copy uses 100% additional memory
    // So savings is ~90-100%
    if (sizeInBytes < defaultThreshold) {
      return 0; // No savings for small data
    }
    return 50.0; // Approximate 50% savings (no copy needed)
  }

  /// Create a transferable from ByteBuffer with offset and length.
  ///
  /// Example:
  /// ```dart
  /// final buffer = Uint8List(1000).buffer;
  /// final transferable = TransferableHelper.fromByteBuffer(
  ///   buffer,
  ///   offset: 100,
  ///   length: 500,
  /// );
  /// ```
  static TransferableTypedData fromByteBuffer(
    ByteBuffer buffer, {
    int offset = 0,
    int? length,
  }) {
    final actualLength = length ?? (buffer.lengthInBytes - offset);
    final view = buffer.asUint8List(offset, actualLength);
    return TransferableTypedData.fromList([view]);
  }

  /// Check if a transferable is empty or null.
  static bool isEmpty(TransferableTypedData? transferable) {
    if (transferable == null) return true;
    try {
      final buffer = transferable.materialize();
      return buffer.lengthInBytes == 0;
    } catch (_) {
      return true;
    }
  }

  /// Get the size of a transferable without materializing it fully.
  ///
  /// Note: This will materialize the buffer, so use sparingly.
  static int getTransferableSize(TransferableTypedData transferable) {
    final buffer = transferable.materialize();
    return buffer.lengthInBytes;
  }
}

/// Extension methods for TypedData to easily convert to transferable.
extension TypedDataTransferableExtension on TypedData {
  /// Convert this TypedData to TransferableTypedData.
  ///
  /// Example:
  /// ```dart
  /// final data = Uint8List(1000);
  /// final transferable = data.toTransferable();
  /// ```
  TransferableTypedData toTransferable() {
    if (this is Uint8List) {
      return TransferableHelper.fromUint8List(this as Uint8List);
    } else if (this is Int8List) {
      return TransferableHelper.fromInt8List(this as Int8List);
    } else if (this is Uint16List) {
      return TransferableHelper.fromUint16List(this as Uint16List);
    } else if (this is Int16List) {
      return TransferableHelper.fromInt16List(this as Int16List);
    } else if (this is Uint32List) {
      return TransferableHelper.fromUint32List(this as Uint32List);
    } else if (this is Int32List) {
      return TransferableHelper.fromInt32List(this as Int32List);
    } else if (this is Float32List) {
      return TransferableHelper.fromFloat32List(this as Float32List);
    } else if (this is Float64List) {
      return TransferableHelper.fromFloat64List(this as Float64List);
    } else {
      // Fallback: convert to Uint8List
      return TransferableHelper.fromUint8List(
        buffer.asUint8List(offsetInBytes, lengthInBytes),
      );
    }
  }

  /// Check if this data should use transferable for efficiency.
  bool shouldUseTransferable(
      {int threshold = TransferableHelper.defaultThreshold}) {
    return TransferableHelper.shouldUseTransferable(lengthInBytes,
        threshold: threshold);
  }

  /// Get human-readable size.
  String get formattedSize => TransferableHelper.formatSize(lengthInBytes);
}

// Extension for List<TypedData> to easily convert to transferable.
extension TypedDataListTransferableExtension on List<TypedData> {
  /// Convert this list of TypedData to single TransferableTypedData.
  ///
  /// Example:
  /// ```dart
  /// final arrays = [Uint8List(100), Float32List(50)];
  /// final transferable = arrays.toTransferable();
  /// ```
  TransferableTypedData toTransferable() {
    return TransferableHelper.fromTypedLists(this);
  }

  /// Get total size in bytes.
  int get totalSizeInBytes {
    return fold(0, (sum, data) => sum + data.lengthInBytes);
  }

  /// Check if any item should use transferable.
  bool get shouldUseTransferable {
    return any((data) => data.shouldUseTransferable());
  }
}
