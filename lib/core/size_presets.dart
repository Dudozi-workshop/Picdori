/// Ratio and size policy used by both UI and tests.
///
/// Selecting an aspect ratio fits the largest rectangle within source bounds
/// without enlarging the photo. Pixels stay explicit and separately editable.
class TargetPixels {
  const TargetPixels(this.width, this.height);
  final int width;
  final int height;
}

class SizePresets {
  static TargetPixels capLongEdge(TargetPixels input, int maxPixels) {
    if (input.width < 1 || input.height < 1 || maxPixels < 1) {
      throw ArgumentError('Pixel dimensions and limit must be positive.');
    }
    final biggest = input.width > input.height ? input.width : input.height;
    if (biggest <= maxPixels) return input;
    final scale = maxPixels / biggest;
    final width = (input.width * scale).round().clamp(1, maxPixels);
    final height = (input.height * scale).round().clamp(1, maxPixels);
    return TargetPixels(width, height);
  }

  static TargetPixels forAspect({
    required int sourceWidth,
    required int sourceHeight,
    required double ratio,
  }) {
    if (sourceWidth < 1 || sourceHeight < 1 || ratio <= 0) {
      throw ArgumentError('Pixel dimensions and ratio must be positive.');
    }
    if (sourceWidth / sourceHeight > ratio) {
      final width = (sourceHeight * ratio).round().clamp(1, sourceWidth);
      return TargetPixels(width, sourceHeight);
    }
    final height = (sourceWidth / ratio).round().clamp(1, sourceHeight);
    return TargetPixels(sourceWidth, height);
  }

  static double originalAspect(int width, int height) => width / height;

  static double? aspectByPreset(String name) {
    switch (name) {
      case '1:1': return 1;
      case '4:3': return 4 / 3;
      case '3:4': return 3 / 4;
      case '16:9': return 16 / 9;
      case '9:16': return 9 / 16;
      default: return null;
    }
  }
}
