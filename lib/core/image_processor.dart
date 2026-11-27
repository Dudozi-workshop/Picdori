import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Output pixel dimensions are strict; byte limits must not change them.
enum GeometryMode { crop, fit }
enum OutputFormat { jpg, png }

class ImageJob {
  const ImageJob({
    required this.source,
    required this.width,
    required this.height,
    required this.mode,
    required this.format,
    this.maximumBytes,
  });

  final Uint8List source;
  final int width;
  final int height;
  final GeometryMode mode;
  final OutputFormat format;
  final int? maximumBytes;
}

class ImageResult {
  const ImageResult({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    this.jpegQuality,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final OutputFormat format;
  final int? jpegQuality;
  int get size => bytes.length;
  String get extension => format == OutputFormat.jpg ? 'jpg' : 'png';
}

class ImageProcessingException implements Exception {
  const ImageProcessingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Decode the image on an isolate (call through compute).
List<int>? inspectImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  return [oriented.width, oriented.height];
}

/// Exact geometry + best feasible JPEG quality, then re-verify the result.
ImageResult runImageProcessing(ImageJob job) {
  if (job.width < 1 || job.height < 1 ||
      job.width > 10000 || job.height > 10000 ||
      job.width * job.height > 20000000) {
    throw const ImageProcessingException('가로·세로는 각각 1~10000px, 전체는 2000만 픽셀 이하여야 해요.');
  }
  if (job.maximumBytes != null && job.maximumBytes! < 2000) {
    throw const ImageProcessingException('용량 제한은 2KB 이상이어야 해요.');
  }
  final decoded = img.decodeImage(job.source);
  if (decoded == null) {
    throw const ImageProcessingException('JPG·PNG 사진을 불러와 주세요.');
  }
  final oriented = img.bakeOrientation(decoded);
  // Keep the original binary intact when no conversion was requested.
  // This preserves metadata, alpha and avoids unnecessary quality loss.
  if (job.mode == GeometryMode.fit &&
      (job.maximumBytes == null || job.source.length <= job.maximumBytes!) &&
      oriented.width == job.width &&
      oriented.height == job.height &&
      decoded.width == job.width &&
      decoded.height == job.height &&
      _matchesFormat(job.source, job.format)) {
    return ImageResult(
      bytes: job.source,
      width: job.width,
      height: job.height,
      format: job.format,
    );
  }
  img.Image working = oriented;
  if (job.mode == GeometryMode.crop) {
    final sourceRatio = oriented.width / oriented.height;
    final wantedRatio = job.width / job.height;
    if (sourceRatio > wantedRatio) {
      final cw = math.min(oriented.width,
          math.max(1, (oriented.height * wantedRatio).round()));
      working = img.copyCrop(oriented,
          x: (oriented.width - cw) ~/ 2, y: 0,
          width: cw, height: oriented.height);
    } else {
      final ch = math.min(oriented.height,
          math.max(1, (oriented.width / wantedRatio).round()));
      working = img.copyCrop(oriented,
          x: 0, y: (oriented.height - ch) ~/ 2,
          width: oriented.width, height: ch);
    }
  }
  final canvas = img.Image(width: job.width, height: job.height,
      numChannels: 4);
  if (job.format == OutputFormat.png) {
    // Preserve image transparency and use transparent padding for PNG.
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  } else {
    // JPG has no alpha channel; composite over white.
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
  }
  if (job.mode == GeometryMode.crop) {
    final scaled = img.copyResize(working,
        width: job.width, height: job.height,
        interpolation: img.Interpolation.cubic);
    img.compositeImage(canvas, scaled);
  } else {
    final factor = math.min(
        job.width / working.width, job.height / working.height);
    final fw = math.max(1, math.min(job.width, (working.width * factor).round()));
    final fh = math.max(1, math.min(job.height, (working.height * factor).round()));
    final scaled = img.copyResize(working,
        width: fw, height: fh, interpolation: img.Interpolation.cubic);
    img.compositeImage(canvas, scaled,
        dstX: (job.width - fw) ~/ 2, dstY: (job.height - fh) ~/ 2);
  }
  Uint8List bytes;
  int? quality;
  if (job.format == OutputFormat.png) {
    bytes = Uint8List.fromList(img.encodePng(canvas, level: 9));
    if (job.maximumBytes != null && bytes.length > job.maximumBytes!) {
      throw const ImageProcessingException(
          '지정 픽셀과 PNG 형식으로는 이 용량을 맞추기 어려워요. JPG로 바꾸거나 픽셀을 줄여 주세요.');
    }
  } else if (job.maximumBytes == null) {
    quality = 90;
    bytes = Uint8List.fromList(img.encodeJpg(canvas, quality: quality));
  } else {
    Uint8List? best;
    var low = 1;
    var high = 95;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final encoded = Uint8List.fromList(img.encodeJpg(canvas, quality: mid));
      if (encoded.length <= job.maximumBytes!) {
        best = encoded;
        quality = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (best == null) {
      throw const ImageProcessingException(
          '이 픽셀 크기로는 요청한 용량을 맞출 수 없어요. 픽셀을 줄이거나 용량을 늘려 주세요.');
    }
    bytes = best;
  }
  final checked = img.decodeImage(bytes);
  if (checked == null || checked.width != job.width || checked.height != job.height) {
    throw const ImageProcessingException('출력 픽셀 검증에 실패했어요.');
  }
  if (job.maximumBytes != null && bytes.length > job.maximumBytes!) {
    throw const ImageProcessingException('출력 용량 검증에 실패했어요.');
  }
  if (!_matchesFormat(bytes, job.format)) {
    throw const ImageProcessingException('출력 파일 형식 검증에 실패했어요.');
  }
  return ImageResult(bytes: bytes, width: checked.width,
      height: checked.height, format: job.format, jpegQuality: quality);
}

bool _matchesFormat(Uint8List bytes, OutputFormat format) {
  if (format == OutputFormat.jpg) {
    return bytes.length >= 3 &&
        bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
  }
  return bytes.length >= 8 &&
      bytes[0] == 0x89 && bytes[1] == 0x50 &&
      bytes[2] == 0x4e && bytes[3] == 0x47 &&
      bytes[4] == 0x0d && bytes[5] == 0x0a;
}
