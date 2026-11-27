import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../core/image_processor.dart';

/// Import at native/original resolution without silently imposing an output
/// specification. HEIC fallback runs on the platform thread, never in compute.
class ImportedPhoto {
  const ImportedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
    required this.originalFileBytes,
    required this.originalFormat,
    required this.preconverted,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final int originalFileBytes;
  final String originalFormat;
  final bool preconverted;
}

class PhotoImportException implements Exception {
  const PhotoImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PhotoImporter {
  static bool isHeicFilename(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.heic') || lower.endsWith('.heif');
  }

  static Future<ImportedPhoto> fromPicked(XFile picked) async {
    final original = await picked.readAsBytes();
    var source = original;
    var dimensions = await compute(inspectImage, source);
    var wasConverted = false;
    final fromHeic = isHeicFilename(picked.name);

    // The pure-Dart decoder doesn't decode HEIC. Use the OS image codec
    // only for recognized HEIC/HEIF sources. The original is never modified.
    if (dimensions == null && fromHeic) {
      try {
        final native = await FlutterImageCompress.compressWithFile(
          picked.path,
          minWidth: 10000,
          minHeight: 10000,
          quality: 96,
          format: CompressFormat.jpeg,
          keepExif: false,
          autoCorrectionAngle: true,
        );
        if (native == null || native.isEmpty) {
          throw const PhotoImportException(
            '이 기기에서는 HEIC 사진 변환을 지원하지 않아요.',
          );
        }
        source = native;
        dimensions = await compute(inspectImage, source);
        wasConverted = true;
      } on PhotoImportException {
        rethrow;
      } catch (_) {
        throw const PhotoImportException(
          'HEIC 사진을 읽지 못했어요. 기기 지원 여부를 확인해 주세요.',
        );
      }
    }
    if (dimensions == null) {
      throw const PhotoImportException(
        'JPG·PNG·HEIC 사진을 선택해 주세요.',
      );
    }
    final label = fromHeic
        ? 'HEIC'
        : picked.name.toLowerCase().endsWith('.png')
            ? 'PNG' : 'JPG';

    return ImportedPhoto(
      bytes: source,
      width: dimensions[0],
      height: dimensions[1],
      originalFileBytes: original.length,
      originalFormat: label,
      preconverted: wasConverted,
    );
  }
}
