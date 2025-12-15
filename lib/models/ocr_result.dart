class OCRResult {
  final String fullText;
  final List<TextBlock> blocks;
  final int blockCount;
  final int lineCount;
  final double confidence;
  final Duration processingTime;

  OCRResult({
    required this.fullText,
    required this.blocks,
    required this.blockCount,
    required this.lineCount,
    required this.confidence,
    required this.processingTime,
  });

  Map<String, dynamic> toJson() => {
    'fullText': fullText,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'blockCount': blockCount,
    'lineCount': lineCount,
    'confidence': confidence,
    'processingTimeMs': processingTime.inMilliseconds,
  };
}

class TextBlock {
  final String text;
  final List<TextLine> lines;
  final BoundingBox boundingBox;
  final double confidence;

  TextBlock({
    required this.text,
    required this.lines,
    required this.boundingBox,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'lines': lines.map((l) => l.toJson()).toList(),
    'boundingBox': boundingBox.toJson(),
    'confidence': confidence,
  };
}

class TextLine {
  final String text;
  final BoundingBox boundingBox;
  final double confidence;

  TextLine({
    required this.text,
    required this.boundingBox,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'boundingBox': boundingBox.toJson(),
    'confidence': confidence,
  };
}

class BoundingBox {
  final double left;
  final double top;
  final double width;
  final double height;

  BoundingBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };
}