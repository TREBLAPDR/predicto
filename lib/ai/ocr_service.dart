import 'dart:io';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../models/ocr_result.dart' as models;

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer();

  /// Perform local OCR using ML Kit
  Future<models.OCRResult> performOCR(String imagePath) async {
    final startTime = DateTime.now();

    try {
      final InputImage inputImage = InputImage.fromFile(File(imagePath));
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      // Convert ML Kit results to our model
      final List<models.TextBlock> blocks = [];
      int totalLines = 0;
      double totalConfidence = 0.0;
      int confidenceCount = 0;

      for (final textBlock in recognizedText.blocks) {
        final List<models.TextLine> lines = [];

        for (final textLine in textBlock.lines) {
          // ML Kit doesn't provide per-line confidence, estimate from block
          final lineConfidence = 0.85; // Default confidence for ML Kit

          lines.add(models.TextLine(
            text: textLine.text,
            boundingBox: _convertBoundingBox(textLine.boundingBox),
            confidence: lineConfidence,
          ));

          totalLines++;
          totalConfidence += lineConfidence;
          confidenceCount++;
        }

        blocks.add(models.TextBlock(
          text: textBlock.text,
          lines: lines,
          boundingBox: _convertBoundingBox(textBlock.boundingBox),
          confidence: 0.85, // ML Kit doesn't provide confidence scores
        ));
      }

      final avgConfidence = confidenceCount > 0 ? totalConfidence / confidenceCount : 0.0;
      final processingTime = DateTime.now().difference(startTime);

      return models.OCRResult(
        fullText: recognizedText.text,
        blocks: blocks,
        blockCount: blocks.length,
        lineCount: totalLines,
        confidence: avgConfidence,
        processingTime: processingTime,
      );
    } catch (e) {
      throw Exception('OCR failed: $e');
    }
  }

  models.BoundingBox _convertBoundingBox(Rect rect) {
    return models.BoundingBox(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
    );
  }

  /// Extract potential line items from OCR text
  /// Simple heuristic: lines containing numbers (prices)
  List<String> extractPotentialItems(models.OCRResult ocrResult) {
    final List<String> items = [];
    final pricePattern = RegExp(r'\d+\.\d{2}|\d+,\d{2}');

    for (final block in ocrResult.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        // Look for lines with prices
        if (pricePattern.hasMatch(text) && text.length > 3) {
          items.add(text);
        }
      }
    }

    return items;
  }

  void dispose() {
    _textRecognizer.close();
  }
}