import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'transferable_helper.dart';

export 'transferable_helper.dart';

void main() {
  group('TransferableHelper', () {
    test('fromUint8List and toUint8List', () {
      final original = Uint8List.fromList([1, 2, 3, 4, 5]);
      final transferable = TransferableHelper.fromUint8List(original);
      final result = TransferableHelper.toUint8List(transferable);

      expect(result.length, equals(5));
      expect(result, equals([1, 2, 3, 4, 5]));
    });

    test('fromInt8List and toInt8List', () {
      final original = Int8List.fromList([-1, 0, 1, 2, 3]);
      final transferable = TransferableHelper.fromInt8List(original);
      final result = TransferableHelper.toInt8List(transferable);

      expect(result.length, equals(5));
      expect(result, equals([-1, 0, 1, 2, 3]));
    });

    test('fromFloat32List and toFloat32List', () {
      final original = Float32List.fromList([1.5, 2.5, 3.5]);
      final transferable = TransferableHelper.fromFloat32List(original);
      final result = TransferableHelper.toFloat32List(transferable);

      expect(result.length, equals(3));
      expect(result[0], closeTo(1.5, 0.001));
      expect(result[1], closeTo(2.5, 0.001));
      expect(result[2], closeTo(3.5, 0.001));
    });

    test('fromTypedLists with multiple arrays', () {
      final list1 = Uint8List.fromList([1, 2, 3]);
      final list2 = Uint8List.fromList([4, 5, 6]);

      final transferable = TransferableHelper.fromTypedLists([list1, list2]);
      final buffer = transferable.materialize();

      expect(buffer.lengthInBytes, greaterThan(0));
    });

    test('materializeAs with different types', () {
      final original = Uint8List.fromList([1, 2, 3, 4]);
      final transferable = TransferableHelper.fromUint8List(original);

      final result = TransferableHelper.materializeAs<Uint8List>(transferable);
      expect(result, isA<Uint8List>());
      expect(result.length, equals(4));
    });

    test('shouldUseTransferable with default threshold', () {
      expect(TransferableHelper.shouldUseTransferable(50 * 1024), isFalse);
      expect(TransferableHelper.shouldUseTransferable(150 * 1024), isTrue);
    });

    test('shouldUseTransferable with custom threshold', () {
      expect(
        TransferableHelper.shouldUseTransferable(10 * 1024,
            threshold: 5 * 1024),
        isTrue,
      );
      expect(
        TransferableHelper.shouldUseTransferable(3 * 1024, threshold: 5 * 1024),
        isFalse,
      );
    });

    test('getSizeInBytes', () {
      final data = Uint8List(1024);
      expect(TransferableHelper.getSizeInBytes(data), equals(1024));
    });

    test('formatSize', () {
      expect(TransferableHelper.formatSize(512), equals('512 B'));
      expect(TransferableHelper.formatSize(1024), equals('1.00 KB'));
      expect(TransferableHelper.formatSize(1024 * 1024), equals('1.00 MB'));
      expect(
          TransferableHelper.formatSize(1024 * 1024 * 1024), equals('1.00 GB'));
    });

    test('estimateMemorySavings', () {
      expect(TransferableHelper.estimateMemorySavings(50 * 1024), equals(0));
      expect(
          TransferableHelper.estimateMemorySavings(150 * 1024), equals(50.0));
    });

    test('fromByteBuffer', () {
      final original = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final transferable = TransferableHelper.fromByteBuffer(
        original.buffer,
        offset: 2,
        length: 5,
      );
      final result = TransferableHelper.toUint8List(transferable);

      expect(result.length, equals(5));
      expect(result, equals([2, 3, 4, 5, 6]));
    });

    test('isEmpty with null', () {
      expect(TransferableHelper.isEmpty(null), isTrue);
    });

    test('isEmpty with empty data', () {
      final empty = Uint8List(0);
      final transferable = TransferableHelper.fromUint8List(empty);
      expect(TransferableHelper.isEmpty(transferable), isTrue);
    });

    test('isEmpty with non-empty data', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final transferable = TransferableHelper.fromUint8List(data);
      expect(TransferableHelper.isEmpty(transferable), isFalse);
    });

    test('getTransferableSize', () {
      final data = Uint8List(500);
      final transferable = TransferableHelper.fromUint8List(data);
      expect(TransferableHelper.getTransferableSize(transferable), equals(500));
    });
  });

  group('TypedDataTransferableExtension', () {
    test('toTransferable on Uint8List', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final transferable = data.toTransferable();
      final result = TransferableHelper.toUint8List(transferable);

      expect(result, equals([1, 2, 3]));
    });

    test('toTransferable on Float32List', () {
      final data = Float32List.fromList([1.5, 2.5]);
      final transferable = data.toTransferable();
      final result = TransferableHelper.toFloat32List(transferable);

      expect(result[0], closeTo(1.5, 0.001));
      expect(result[1], closeTo(2.5, 0.001));
    });

    test('shouldUseTransferable extension', () {
      final small = Uint8List(50 * 1024);
      final large = Uint8List(150 * 1024);

      expect(small.shouldUseTransferable(), isFalse);
      expect(large.shouldUseTransferable(), isTrue);
    });

    test('formattedSize extension', () {
      final data = Uint8List(2048);
      expect(data.formattedSize, equals('2.00 KB'));
    });
  });

  group('TypedDataListTransferableExtension', () {
    test('toTransferable on list', () {
      final list = [
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3, 4]),
      ];
      final transferable = list.toTransferable();
      expect(transferable, isNotNull);
    });

    test('totalSizeInBytes', () {
      final list = [
        Uint8List(100),
        Uint8List(200),
        Uint8List(300),
      ];
      expect(list.totalSizeInBytes, equals(600));
    });

    test('shouldUseTransferable on list', () {
      final smallList = [Uint8List(1000), Uint8List(2000)];
      final largeList = [Uint8List(100 * 1024), Uint8List(200 * 1024)];

      expect(smallList.shouldUseTransferable, isFalse);
      expect(largeList.shouldUseTransferable, isTrue);
    });
  });

  group('Large Data Transfer', () {
    test('transfer 1MB data', () {
      final original = Uint8List(1024 * 1024);
      for (int i = 0; i < original.length; i++) {
        original[i] = i % 256;
      }

      final transferable = TransferableHelper.fromUint8List(original);
      final result = TransferableHelper.toUint8List(transferable);

      expect(result.length, equals(original.length));
      expect(result[0], equals(0));
      expect(result[1000], equals(1000 % 256));
    });

    test('transfer 10MB data', () {
      final original = Uint8List(10 * 1024 * 1024);
      for (int i = 0; i < 1000; i++) {
        original[i] = i % 256;
      }

      final transferable = TransferableHelper.fromUint8List(original);
      final result = TransferableHelper.toUint8List(transferable);

      expect(result.length, equals(original.length));
      expect(
        TransferableHelper.shouldUseTransferable(original.length),
        isTrue,
      );
    });
  });

  group('Edge Cases', () {
    test('empty Uint8List', () {
      final empty = Uint8List(0);
      final transferable = TransferableHelper.fromUint8List(empty);
      final result = TransferableHelper.toUint8List(transferable);

      expect(result.length, equals(0));
    });

    test('single byte', () {
      final single = Uint8List.fromList([42]);
      final transferable = TransferableHelper.fromUint8List(single);
      final result = TransferableHelper.toUint8List(transferable);

      expect(result.length, equals(1));
      expect(result[0], equals(42));
    });

    test('max byte value', () {
      final data = Uint8List.fromList([255, 255, 255]);
      final transferable = TransferableHelper.fromUint8List(data);
      final result = TransferableHelper.toUint8List(transferable);

      expect(result, equals([255, 255, 255]));
    });
  });
}
