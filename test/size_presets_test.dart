import 'package:picdori/core/size_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ratio presets', () {
    test('square from landscape does not enlarge pixels', () {
      final pixels = SizePresets.forAspect(
        sourceWidth: 4000, sourceHeight: 3000, ratio: 1,
      );
      expect(pixels.width, 3000);
      expect(pixels.height, 3000);
    });

    test('portrait 3:4 stays inside source bounds', () {
      final pixels = SizePresets.forAspect(
        sourceWidth: 4000, sourceHeight: 3000, ratio: 3 / 4,
      );
      expect(pixels.width, 2250);
      expect(pixels.height, 3000);
    });

    test('landscape 16:9 stays inside source bounds', () {
      final pixels = SizePresets.forAspect(
        sourceWidth: 4000, sourceHeight: 3000, ratio: 16 / 9,
      );
      expect(pixels.width, 4000);
      expect(pixels.height, 2250);
    });

    test('ratio then long edge cap keeps the selected ratio', () {
      final square = SizePresets.forAspect(
        sourceWidth: 4000, sourceHeight: 3000, ratio: 1,
      );
      final result = SizePresets.capLongEdge(square, 1200);
      expect(result.width, 1200);
      expect(result.height, 1200);
    });

    test('long edge cap never enlarges a small photo', () {
      const source = TargetPixels(800, 600);
      final result = SizePresets.capLongEdge(source, 1200);
      expect(result.width, 800);
      expect(result.height, 600);
    });

    test('portrait ratio and size cap combine consistently', () {
      final target = SizePresets.forAspect(
        sourceWidth: 3000, sourceHeight: 4000, ratio: 9 / 16,
      );
      final result = SizePresets.capLongEdge(target, 1200);
      expect(result.width, 675);
      expect(result.height, 1200);
    });

    test('invalid ratio rejected', () {
      expect(
        () => SizePresets.forAspect(
          sourceWidth: 1000, sourceHeight: 800, ratio: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
