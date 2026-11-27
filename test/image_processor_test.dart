import 'dart:typed_data';

import 'package:picdori/core/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List samplePng({int width = 400, int height = 200}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(18, 110, 200));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('Exact image specification', () {
    test('center crop uses the center region, not the edges', () {
      final photo = img.Image(width: 300, height: 100);
      img.fill(photo, color: img.ColorRgb8(230, 30, 30));
      img.fillRect(photo, x1: 100, y1: 0, x2: 199, y2: 99,
          color: img.ColorRgb8(25, 190, 60));
      final result = runImageProcessing(ImageJob(
        source: Uint8List.fromList(img.encodePng(photo)),
        width: 100, height: 100,
        mode: GeometryMode.crop, format: OutputFormat.png,
      ));
      final checked = img.decodePng(result.bytes)!;
      final middle = checked.getPixel(50, 50);
      expect(middle.g, greaterThan(150));
      expect(middle.r, lessThan(90));
    });

    test('crop returns exact square JPEG', () {
      final result = runImageProcessing(ImageJob(
        source: samplePng(), width: 300, height: 300,
        mode: GeometryMode.crop, format: OutputFormat.jpg,
      ));
      expect(result.width, 300);
      expect(result.height, 300);
      expect(result.bytes[0], 0xff);
      expect(result.bytes[1], 0xd8);
    });

    test('PNG fit preserves the whole photo with transparent bars', () {
      final result = runImageProcessing(ImageJob(
        source: samplePng(), width: 200, height: 200,
        mode: GeometryMode.fit, format: OutputFormat.png,
      ));
      final image = img.decodePng(result.bytes)!;
      expect(image.getPixel(0, 0).a, 0);
      expect(image.getPixel(100, 100).r, 18);
      expect(image.getPixel(100, 100).a, 255);
    });

    test('JPEG fit uses a white solid background', () {
      final result = runImageProcessing(ImageJob(
        source: samplePng(), width: 200, height: 200,
        mode: GeometryMode.fit, format: OutputFormat.jpg,
      ));
      final image = img.decodeJpg(result.bytes)!;
      final corner = image.getPixel(0, 0);
      expect(corner.r, greaterThan(245));
      expect(corner.g, greaterThan(245));
      expect(corner.b, greaterThan(245));
    });

    test('file size limit never changes requested pixels', () {
      final result = runImageProcessing(ImageJob(
        source: samplePng(width: 700, height: 500),
        width: 350, height: 250, mode: GeometryMode.fit,
        format: OutputFormat.jpg, maximumBytes: 20000,
      ));
      expect(result.size, lessThanOrEqualTo(20000));
      expect(result.width, 350);
      expect(result.height, 250);
    });

    test('PNG result is dimension-checked without file-size constraint', () {
      final result = runImageProcessing(ImageJob(
        source: samplePng(),
        width: 120, height: 80,
        mode: GeometryMode.fit, format: OutputFormat.png,
      ));
      expect(result.width, 120);
      expect(result.height, 80);
      expect(result.bytes.take(4).toList(), [0x89, 0x50, 0x4e, 0x47]);
    });

    test('impossible JPEG limit must fail rather than shrink pixels', () {
      expect(() => runImageProcessing(ImageJob(
        source: samplePng(), width: 1200, height: 1200,
        mode: GeometryMode.fit, format: OutputFormat.jpg,
        maximumBytes: 2000,
      )), throwsA(isA<ImageProcessingException>()));
    });

    test('invalid file data is rejected before processing', () {
      expect(() => runImageProcessing(ImageJob(
        source: Uint8List.fromList([1, 2, 3, 4]),
        width: 100, height: 100, mode: GeometryMode.fit,
        format: OutputFormat.jpg,
      )), throwsA(isA<ImageProcessingException>()));
    });

    test('pixel count above safety limit is rejected', () {
      expect(() => runImageProcessing(ImageJob(
        source: samplePng(), width: 10000, height: 10000,
        mode: GeometryMode.fit, format: OutputFormat.jpg,
      )), throwsA(isA<ImageProcessingException>()));
    });

    test('transparent PNG remains transparent after resize', () {
      final source = img.Image(width: 20, height: 20, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 0));
      img.fillRect(source, x1: 5, y1: 5, x2: 15, y2: 15,
        color: img.ColorRgba8(255, 0, 0, 255));
      final result = runImageProcessing(ImageJob(
        source: Uint8List.fromList(img.encodePng(source)),
        width: 40, height: 40,
        mode: GeometryMode.fit, format: OutputFormat.png,
      ));
      final checked = img.decodePng(result.bytes)!;
      expect(checked.getPixel(0, 0).a, 0);
      expect(checked.getPixel(20, 20).a, 255);
    });

    test('original PNG under byte cap is preserved without reencoding', () {
      final source = samplePng(width: 75, height: 50);
      final result = runImageProcessing(ImageJob(
        source: source,
        width: 75,
        height: 50,
        mode: GeometryMode.fit,
        format: OutputFormat.png,
        maximumBytes: source.length + 2100,
      ));
      expect(result.bytes, orderedEquals(source));
      expect(result.size, source.length);
    });

    test('original PNG bytes are preserved for unchanged specification', () {
      final source = samplePng();
      final result = runImageProcessing(ImageJob(
        source: source, width: 400, height: 200,
        mode: GeometryMode.fit, format: OutputFormat.png,
      ));
      expect(result.bytes, orderedEquals(source));
    });

    test('invalid target pixels are rejected', () {
      expect(() => runImageProcessing(ImageJob(
        source: samplePng(), width: 0, height: 500,
        mode: GeometryMode.fit, format: OutputFormat.jpg,
      )), throwsA(isA<ImageProcessingException>()));
    });
  });
}
