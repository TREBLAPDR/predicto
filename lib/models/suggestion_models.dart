import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ItemSuggestion {
  final String itemName;
  final String category;
  final double? estimatedPrice;
  final double confidence;
  final SuggestionReason reason;
  final List<String> relatedItems;

  ItemSuggestion({
    required this.itemName,
    required this.category,
    this.estimatedPrice,
    required this.confidence,
    required this.reason,
    this.relatedItems = const [],
  });

  Map<String, dynamic> toJson() => {
    'itemName': itemName,
    'category': category,
    'estimatedPrice': estimatedPrice,
    'confidence': confidence,
    'reason': reason.toString(),
    'relatedItems': relatedItems,
  };
}

enum SuggestionReason {
  frequentlyPurchased,
  usuallyBuyTogether,
  similarToRecent,
  recipeCompletion,
  seasonalTrend,
  runningLow,
  daySpecific,
}

extension SuggestionReasonExtension on SuggestionReason {
  String get displayText {
    switch (this) {
      case SuggestionReason.frequentlyPurchased:
        return 'Frequent Purchase';
      case SuggestionReason.usuallyBuyTogether:
        return 'Often Bought Together';
      case SuggestionReason.similarToRecent:
        return 'Similar to Recent';
      case SuggestionReason.recipeCompletion:
        return 'Recipe Completion';
      case SuggestionReason.seasonalTrend:
        return 'Seasonal Trend';
      case SuggestionReason.runningLow:
        return 'Running Low';
      case SuggestionReason.daySpecific:
        return 'Day Specific Routine';
    }
  }

  // CHANGED: Returns IconData instead of String (Emoji)
  IconData get icon {
    switch (this) {
      case SuggestionReason.frequentlyPurchased:
        return LucideIcons.history; // Professional history icon
      case SuggestionReason.usuallyBuyTogether:
        return LucideIcons.link; // Link implies connection/together
      case SuggestionReason.similarToRecent:
        return LucideIcons.layers; // Layers imply similarity/stacking
      case SuggestionReason.recipeCompletion:
        return LucideIcons.utensils; // Utensils for cooking/recipes
      case SuggestionReason.seasonalTrend:
        return LucideIcons.calendar; // Calendar for seasons
      case SuggestionReason.runningLow:
        return LucideIcons.hourglass; // Hourglass implies time running out
      case SuggestionReason.daySpecific:
        return LucideIcons.calendarClock; // Calendar + Clock for specific days
    }
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

  int get dayOfWeek => purchaseDate.weekday;

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