import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ImagePreprocessor {
  /// Preprocess a receipt image for optimal OCR accuracy
  /// Returns path to the preprocessed image
  static Future<String> preprocessImage(String originalPath) async {
    // Load the original image
    final File imageFile = File(originalPath);
    final Uint8List bytes = await imageFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Step 1: Resize FIRST if image is too large (max 2000px on longest side)
    // This reduces processing time while maintaining OCR quality
    final int maxDimension = 2000;
    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        image = img.copyResize(image, width: maxDimension);
      } else {
        image = img.copyResize(image, height: maxDimension);
      }
    }

    // Step 2: Convert to grayscale for better text detection
    image = img.grayscale(image);

    // Step 3: Increase contrast to make text sharper
    // Contrast value >100 increases contrast
    image = img.contrast(image, contrast: 140);

    // Step 4: Slightly increase brightness if image is too dark
    image = img.adjustColor(image, brightness: 1.1);

    // Step 5: Save preprocessed image
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String fileName = 'preprocessed_$timestamp.jpg';
    final String savePath = path.join(appDir.path, 'preprocessed', fileName);

    final Directory preprocessedDir = Directory(path.join(appDir.path, 'preprocessed'));
    if (!await preprocessedDir.exists()) {
      await preprocessedDir.create(recursive: true);
    }

    // Encode and save with high quality
    final List<int> jpg = img.encodeJpg(image, quality: 95);
    await File(savePath).writeAsBytes(jpg);

    return savePath;
  }

  /// Get preprocessing quality metrics
  static Future<Map<String, dynamic>> analyzeImage(String imagePath) async {
    final File imageFile = File(imagePath);
    final Uint8List bytes = await imageFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      return {'error': 'Could not decode image'};
    }

    // Calculate basic image metrics
    final int pixelCount = image.width * image.height;
    final double megapixels = pixelCount / 1000000;

    // Simple brightness estimation (average pixel value)
    int totalBrightness = 0;
    int sampleCount = 0;
    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixel(x, y);
        totalBrightness += pixel.r.toInt();
        sampleCount++;
      }
    }
    final double avgBrightness = totalBrightness / sampleCount;

    return {
      'width': image.width,
      'height': image.height,
      'megapixels': megapixels.toStringAsFixed(2),
      'avgBrightness': avgBrightness.toInt(),
      'aspectRatio': (image.width / image.height).toStringAsFixed(2),
      'fileSize': '${(bytes.length / 1024).toStringAsFixed(0)} KB',
    };
  }

  /// Clean up old preprocessed images (keep only last 10)
  static Future<void> cleanupOldImages() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory preprocessedDir = Directory(path.join(appDir.path, 'preprocessed'));

      if (!await preprocessedDir.exists()) return;

      final List<FileSystemEntity> files = preprocessedDir.listSync()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      // Keep only the 10 most recent files
      if (files.length > 10) {
        for (int i = 10; i < files.length; i++) {
          await files[i].delete();
        }
      }
    } catch (e) {
      // Silently fail cleanup
    }
  }
}