import 'package:flutter/material.dart';
import '../models/ocr_result.dart';

class ConfidenceAnalyzer {
  /// Analyze OCR result quality and recommend processing method
  static ConfidenceAnalysis analyze(OCRResult ocrResult) {
    double qualityScore = 0.0;
    List<String> issues = [];

    // Factor 1: OCR confidence (weighted 35%)
    final ocrConfidence = ocrResult.confidence;
    qualityScore += ocrConfidence * 0.35;

    if (ocrConfidence < 0.7) {
      issues.add('Low OCR confidence (${(ocrConfidence * 100).toStringAsFixed(0)}%)');
    }

    // Factor 2: Text density (weighted 25%)
    // Good receipts have 20-100 lines
    final lineCount = ocrResult.lineCount;
    double densityScore = 0.0;

    if (lineCount < 10) {
      densityScore = 0.3;
      issues.add('Very few text lines detected ($lineCount)');
    } else if (lineCount < 20) {
      densityScore = 0.6;
      issues.add('Few text lines detected ($lineCount)');
    } else if (lineCount <= 100) {
      densityScore = 1.0;
    } else {
      densityScore = 0.7;
      issues.add('Unusually many text lines ($lineCount)');
    }

    qualityScore += densityScore * 0.25;

    // Factor 3: Price patterns (weighted 20%)
    // Receipts should have multiple price-like patterns
    final priceCount = _countPricePatterns(ocrResult.fullText);
    double priceScore = 0.0;

    if (priceCount < 3) {
      priceScore = 0.4;
      issues.add('Few price patterns found ($priceCount)');
    } else if (priceCount < 5) {
      priceScore = 0.7;
    } else {
      priceScore = 1.0;
    }

    qualityScore += priceScore * 0.20;

    // Factor 4: Text block organization (weighted 20%)
    // Well-captured receipts have 3-15 text blocks
    final blockCount = ocrResult.blockCount;
    double structureScore = 0.0;

    if (blockCount < 3) {
      structureScore = 0.5;
      issues.add('Poor text structure ($blockCount blocks)');
    } else if (blockCount <= 15) {
      structureScore = 1.0;
    } else {
      structureScore = 0.7;
      issues.add('Fragmented text structure ($blockCount blocks)');
    }

    qualityScore += structureScore * 0.20;

    // Determine recommendation
    ProcessingRecommendation recommendation;
    String reasoning;

    if (qualityScore >= 0.80) {
      recommendation = ProcessingRecommendation.localOnly;
      reasoning = 'High quality OCR - local processing should work well';
    } else if (qualityScore >= 0.65) {
      recommendation = ProcessingRecommendation.localFirst;
      reasoning = 'Good quality - try local first, use online if needed';
    } else if (qualityScore >= 0.45) {
      recommendation = ProcessingRecommendation.onlineSuggested;
      reasoning = 'Moderate quality - online AI recommended for accuracy';
    } else {
      recommendation = ProcessingRecommendation.onlineRequired;
      reasoning = 'Low quality - online AI processing strongly recommended';
    }

    return ConfidenceAnalysis(
      overallScore: qualityScore,
      ocrConfidence: ocrConfidence,
      textDensityScore: densityScore,
      pricePatternScore: priceScore,
      structureScore: structureScore,
      recommendation: recommendation,
      reasoning: reasoning,
      issues: issues,
    );
  }

  static int _countPricePatterns(String text) {
    // Match common price patterns: 12.99, $12.99, 12,99
    final pricePattern = RegExp(r'[\$]?\d+[.,]\d{2}');
    return pricePattern.allMatches(text).length;
  }
}

enum ProcessingRecommendation {
  localOnly,        // Quality good enough, no need for online
  localFirst,       // Try local, offer online as improvement
  onlineSuggested,  // Recommend online upfront
  onlineRequired,   // Quality too poor for local parsing
}

class ConfidenceAnalysis {
  final double overallScore;
  final double ocrConfidence;
  final double textDensityScore;
  final double pricePatternScore;
  final double structureScore;
  final ProcessingRecommendation recommendation;
  final String reasoning;
  final List<String> issues;

  ConfidenceAnalysis({
    required this.overallScore,
    required this.ocrConfidence,
    required this.textDensityScore,
    required this.pricePatternScore,
    required this.structureScore,
    required this.recommendation,
    required this.reasoning,
    required this.issues,
  });

  Color getScoreColor() {
    if (overallScore >= 0.80) return const Color(0xFF4CAF50); // Green
    if (overallScore >= 0.65) return const Color(0xFF8BC34A); // Light green
    if (overallScore >= 0.45) return const Color(0xFFFF9800); // Orange
    return const Color(0xFFF44336); // Red
  }

  IconData getScoreIcon() {
    if (overallScore >= 0.80) return Icons.check_circle;
    if (overallScore >= 0.65) return Icons.verified;
    if (overallScore >= 0.45) return Icons.warning;
    return Icons.error;
  }
}