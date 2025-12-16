import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ItemSuggestion {
  final String itemName;
  final String category;
  final double? estimatedPrice;
  final double confidence;
  final String reason; // Changed to String to handle custom AI reasons easily
  final List<String> relatedItems;

  ItemSuggestion({
    required this.itemName,
    required this.category,
    this.estimatedPrice,
    required this.confidence,
    required this.reason,
    this.relatedItems = const [],
  });

  factory ItemSuggestion.fromJson(Map<String, dynamic> json) {
    return ItemSuggestion(
      itemName: json['name'] ?? 'Unknown',
      category: json['category'] ?? 'General',
      estimatedPrice: json['estimatedPrice']?.toDouble(),
      confidence: json['confidence']?.toDouble() ?? 0.0,
      reason: json['reason'] ?? 'Suggested by AI',
      relatedItems: List<String>.from(json['relatedItems'] ?? []),
    );
  }
}

class PurchaseHistory {
  final String itemName;
  final DateTime purchaseDate;
  final String category;
  final double? price;

  PurchaseHistory({
    required this.itemName,
    required this.purchaseDate,
    required this.category,
    this.price,
  });

  Map<String, dynamic> toJson() => {
    'itemName': itemName,
    'purchaseDate': purchaseDate.toIso8601String(),
    'category': category,
    'price': price,
  };

  factory PurchaseHistory.fromJson(Map<String, dynamic> json) {
    return PurchaseHistory(
      itemName: json['itemName'],
      purchaseDate: DateTime.parse(json['purchaseDate']),
      category: json['category'],
      price: json['price']?.toDouble(),
    );
  }
}