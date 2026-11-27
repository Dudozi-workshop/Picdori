import 'package:file_saver/file_saver.dart';
import 'package:gal/gal.dart';

import '../core/image_processor.dart';

/// Saves verified outputs without altering the original image.
/// A user chooses gallery, Files, or the OS sharing sheet separately.
class OutputSaver {
  static MimeType _mime(ImageResult image) =>
      image.format == OutputFormat.jpg ? MimeType.jpeg : MimeType.png;

  static String _name() =>
      'picdori_${DateTime.now().millisecondsSinceEpoch}';

  static Future<void> saveToGallery(ImageResult image) =>
      Gal.putImageBytes(image.bytes, name: _name());

  /// Returns null when the native save dialog is cancelled.
  static Future<String?> saveAsFile(ImageResult image) =>
      FileSaver.instance.saveAs(
        name: _name(),
        bytes: image.bytes,
        fileExtension: image.extension,
        mimeType: _mime(image),
      );
}
