import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/suggestion_models.dart';
import '../models/shopping_list_models.dart';
import '../models/product_models.dart';
import 'product_service.dart';

class SuggestionService {
  static const String _keyPurchaseHistory = 'purchase_history';
  static const int _maxHistoryItems = 500;

  static SuggestionService? _instance;
  late SharedPreferences _prefs;

  SuggestionService._();

  static Future<SuggestionService> getInstance() async {
    if (_instance == null) {
      _instance = SuggestionService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// Record purchased items to history
  Future<void> recordPurchases(List<ShoppingListItem> items) async {
    final history = await getPurchaseHistory();
    final now = DateTime.now();

    for (final item in items.where((i) => i.isPurchased)) {
      history.add(PurchaseHistory(
        itemName: item.name.toLowerCase().trim(),
        purchaseDate: now,
        category: item.category,
        price: item.price,
      ));
    }

    // Keep only last 500 items
    if (history.length > _maxHistoryItems) {
      history.removeRange(0, history.length - _maxHistoryItems);
    }

    await _saveHistory(history);

    // Also sync to products database
    try {
      final productService = await ProductService.getInstance();
      await productService.recordPurchases(
        items: items,
        purchaseDate: now,
      );
    } catch (e) {
      print('Failed to sync to products database: $e');
    }
  }

  /// Get purchase history
  Future<List<PurchaseHistory>> getPurchaseHistory() async {
    final String? historyJson = _prefs.getString(_keyPurchaseHistory);
    if (historyJson == null) return [];

    final List<dynamic> historyData = jsonDecode(historyJson);
    return historyData.map((json) => PurchaseHistory.fromJson(json)).toList();
  }

  /// Save history
  Future<void> _saveHistory(List<PurchaseHistory> history) async {
    final String historyJson =
    jsonEncode(history.map((h) => h.toJson()).toList());
    await _prefs.setString(_keyPurchaseHistory, historyJson);
  }

  /// Generate suggestions based on products database + local history
  Future<List<ItemSuggestion>> generateSuggestions({
    required List<ShoppingListItem> currentList,
    int maxSuggestions = 10,
    DateTime? targetDate,
  }) async {
    final List<ItemSuggestion> suggestions = [];
    final currentItemNames =
    currentList.map((i) => i.name.toLowerCase()).toSet();
    final date = targetDate ?? DateTime.now();

    try {
      // Try to get suggestions from products database first
      final productService = await ProductService.getInstance();

      // 1. Get predicted products (running low) - 3 max
      final predictions = await productService.getPredictions(
        daysAhead: 7,
        minConfidence: 0.5,
      );

      for (final prediction in predictions.take(3)) {
        if (currentItemNames.contains(prediction.product.name.toLowerCase()))
          continue;

        suggestions.add(ItemSuggestion(
          itemName: prediction.product.name,
          category: prediction.product.category,
          estimatedPrice: prediction.product.typicalPrice,
          confidence: prediction.confidence,
          reason: SuggestionReason.runningLow,
        ));
      }

      // 2. Get frequently purchased products from database - 2 max
      final allProducts = await productService.getProducts(limit: 50);
      final frequentProducts = allProducts
          .where((p) => p.purchaseCount >= 3)
          .toList()
        ..sort((a, b) => b.purchaseCount.compareTo(a.purchaseCount));

      for (final product in frequentProducts.take(2)) {
        if (currentItemNames.contains(product.name.toLowerCase())) continue;
        if (suggestions.any((s) =>
        s.itemName.toLowerCase() == product.name.toLowerCase())) continue;

        // Confidence based on purchase count
        final confidence = (0.5 + (product.purchaseCount / 20.0)).clamp(0.5, 0.95);

        suggestions.add(ItemSuggestion(
          itemName: product.name,
          category: product.category,
          estimatedPrice: product.typicalPrice,
          confidence: confidence,
          reason: SuggestionReason.frequentlyPurchased,
        ));
      }

      // 3. Get associated products (bought together) - 2 max
      for (final item in currentList.take(3)) {
        try {
          final products =
          await productService.getProducts(search: item.name, limit: 1);
          if (products.isNotEmpty) {
            final associations = await productService.getAssociations(
              products.first.id,
              minConfidence: 0.5,
            );

            for (final assoc in associations.take(2)) {
              if (currentItemNames.contains(assoc.product.name.toLowerCase()))
                continue;
              if (suggestions.any((s) =>
              s.itemName.toLowerCase() == assoc.product.name.toLowerCase()))
                continue;

              suggestions.add(ItemSuggestion(
                itemName: assoc.product.name,
                category: assoc.product.category,
                estimatedPrice: assoc.product.typicalPrice,
                confidence: assoc.confidence,
                reason: SuggestionReason.usuallyBuyTogether,
                relatedItems: [item.name],
              ));
            }
          }
        } catch (e) {
          // Continue if association fetch fails
        }
      }
    } catch (e) {
      print('Failed to get suggestions from database: $e');
    }

    // Fallback to local history if database suggestions are insufficient
    if (suggestions.length < 5) {
      final history = await getPurchaseHistory();

      if (history.isNotEmpty) {
        // Add day-based suggestions
        final dayBased = await _getDayBasedSuggestions(date, currentItemNames);
        suggestions.addAll(dayBased.take(3));

        // Add frequent items from local history
        if (suggestions.length < 7) {
          final frequentItems = _getFrequentItems(history, currentItemNames);
          suggestions.addAll(frequentItems.take(3));
        }

        // Add association items from local history
        if (suggestions.length < 9) {
          final assocItems =
          _getAssociationItems(history, currentList, currentItemNames);
          suggestions.addAll(assocItems.take(2));
        }
      }
    }

    // Recipe completion (always add 1-2)
    final recipeItems =
    _getRecipeCompletionItems(currentList, currentItemNames);
    suggestions.addAll(recipeItems.take(2));

    // Remove duplicates and sort by confidence
    final uniqueSuggestions = _removeDuplicates(suggestions);
    uniqueSuggestions.sort((a, b) => b.confidence.compareTo(a.confidence));

    // If still no suggestions, return defaults
    if (uniqueSuggestions.isEmpty) {
      return _getDefaultSuggestions();
    }

    return uniqueSuggestions.take(maxSuggestions).toList();
  }

  /// Get frequently purchased items from local history
  List<ItemSuggestion> _getFrequentItems(
      List<PurchaseHistory> history,
      Set<String> excludeItems,
      ) {
    if (history.isEmpty) return [];

    final Map<String, int> itemCounts = {};
    final Map<String, String> itemCategories = {};
    final Map<String, List<double>> itemPrices = {};

    for (final purchase in history) {
      final itemName = purchase.itemName;
      if (excludeItems.contains(itemName)) continue;

      itemCounts[itemName] = (itemCounts[itemName] ?? 0) + 1;
      itemCategories[itemName] = purchase.category;

      if (purchase.price != null) {
        itemPrices.putIfAbsent(itemName, () => []);
        itemPrices[itemName]!.add(purchase.price!);
      }
    }

    final suggestions = <ItemSuggestion>[];

    // Find max count for normalization
    final maxCount = itemCounts.values.isEmpty
        ? 1
        : itemCounts.values.reduce((a, b) => a > b ? a : b);

    final sortedItems = itemCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedItems.take(10)) {
      final itemName = entry.key;
      final count = entry.value;

      // FIXED: Proper confidence calculation
      final normalizedCount = count / maxCount;
      final confidence = (0.3 + (normalizedCount * 0.7)).clamp(0.3, 1.0);

      double? avgPrice;
      if (itemPrices.containsKey(itemName)) {
        final prices = itemPrices[itemName]!;
        avgPrice = prices.reduce((a, b) => a + b) / prices.length;
      }

      suggestions.add(ItemSuggestion(
        itemName: _capitalize(itemName),
        category: itemCategories[itemName] ?? 'Other',
        estimatedPrice: avgPrice,
        confidence: confidence,
        reason: SuggestionReason.frequentlyPurchased,
      ));
    }

    return suggestions;
  }

  /// Get items bought together from local history
  List<ItemSuggestion> _getAssociationItems(
      List<PurchaseHistory> history,
      List<ShoppingListItem> currentList,
      Set<String> excludeItems,
      ) {
    if (currentList.isEmpty || history.isEmpty) return [];

    // Group purchases by date (same shopping trip)
    final Map<String, Set<String>> tripItems = {};

    for (final purchase in history) {
      final dateKey = purchase.purchaseDate.toString().substring(0, 10);
      tripItems.putIfAbsent(dateKey, () => {});
      tripItems[dateKey]!.add(purchase.itemName);
    }

    // Count how often items appear together
    final Map<String, Map<String, int>> coOccurrences = {};
    final currentItemsLower =
    currentList.map((i) => i.name.toLowerCase()).toSet();

    for (final items in tripItems.values) {
      // For each item in current list, find what was bought with it
      for (final currentItem in currentItemsLower) {
        if (!items.contains(currentItem)) continue;

        for (final otherItem in items) {
          if (otherItem == currentItem) continue;
          if (excludeItems.contains(otherItem)) continue;

          coOccurrences.putIfAbsent(currentItem, () => {});
          coOccurrences[currentItem]!.putIfAbsent(otherItem, () => 0);
          coOccurrences[currentItem]![otherItem] =
              coOccurrences[currentItem]![otherItem]! + 1;
        }
      }
    }

    final suggestions = <ItemSuggestion>[];

    // Generate suggestions from co-occurrences
    for (final entry in coOccurrences.entries) {
      final baseItem = entry.key;
      final associatedItems = entry.value;

      for (final assocEntry in associatedItems.entries) {
        final assocItem = assocEntry.key;
        final count = assocEntry.value;

        // FIXED: Only suggest if bought together 3+ times
        if (count >= 3) {
          // Confidence based on co-occurrence count
          final confidence = (0.5 + (count * 0.05)).clamp(0.6, 0.95);

          // Find the related item from current list
          final relatedItem = currentList.firstWhere(
                (item) => item.name.toLowerCase() == baseItem,
            orElse: () => currentList.first,
          );

          suggestions.add(ItemSuggestion(
            itemName: _capitalize(assocItem),
            category: _guessCategory(assocItem),
            estimatedPrice: null,
            confidence: confidence,
            reason: SuggestionReason.usuallyBuyTogether,
            relatedItems: [relatedItem.name],
          ));
        }
      }
    }

    // Remove duplicates and sort by confidence
    final uniqueSuggestions = _removeDuplicates(suggestions);
    uniqueSuggestions.sort((a, b) => b.confidence.compareTo(a.confidence));

    return uniqueSuggestions;
  }

  /// Get items based on target date's day-of-week pattern
  Future<List<ItemSuggestion>> _getDayBasedSuggestions(
      DateTime targetDate,
      Set<String> excludeItems,
      ) async {
    final history = await getPurchaseHistory();
    if (history.isEmpty) return [];

    // Get target day of week (1=Monday, 7=Sunday)
    final targetDayOfWeek = targetDate.weekday;

    // Count purchases by day of week for each item
    final Map<String, int> itemCountsOnTargetDay = {};
    final Map<String, int> itemTotalCounts = {};
    final Map<String, String> itemCategories = {};
    final Map<String, List<double>> itemPrices = {};
    final Map<String, DateTime> lastPurchaseDates = {};

    for (final purchase in history) {
      final itemName = purchase.itemName;
      if (excludeItems.contains(itemName)) continue;

      // Track total purchases
      itemTotalCounts[itemName] = (itemTotalCounts[itemName] ?? 0) + 1;
      itemCategories[itemName] = purchase.category;

      // Track last purchase date
      if (!lastPurchaseDates.containsKey(itemName) ||
          purchase.purchaseDate.isAfter(lastPurchaseDates[itemName]!)) {
        lastPurchaseDates[itemName] = purchase.purchaseDate;
      }

      // Count purchases on this specific day of week
      if (purchase.purchaseDate.weekday == targetDayOfWeek) {
        itemCountsOnTargetDay[itemName] =
            (itemCountsOnTargetDay[itemName] ?? 0) + 1;
      }

      // Track prices
      if (purchase.price != null) {
        itemPrices.putIfAbsent(itemName, () => []);
        itemPrices[itemName]!.add(purchase.price!);
      }
    }

    final suggestions = <ItemSuggestion>[];

    // Generate suggestions for items bought on this day of week
    for (final entry in itemCountsOnTargetDay.entries) {
      final itemName = entry.key;
      final dayCount = entry.value;
      final totalCount = itemTotalCounts[itemName] ?? 1;

      // FIXED: Only suggest if bought on this day at least 2 times
      if (dayCount >= 2) {
        // Calculate confidence based on day ratio
        final dayRatio = dayCount / totalCount;

        // Check how many days since last purchase
        final daysSinceLastPurchase = lastPurchaseDates.containsKey(itemName)
            ? targetDate.difference(lastPurchaseDates[itemName]!).inDays
            : 999;

        // Base confidence
        double confidence = (0.5 + (dayRatio * 0.4)).clamp(0.5, 0.95);

        // Boost confidence if it's been 7+ days since last purchase
        if (daysSinceLastPurchase >= 7) {
          confidence = (confidence + 0.1).clamp(0.6, 1.0);
        }

        double? avgPrice;
        if (itemPrices.containsKey(itemName)) {
          final prices = itemPrices[itemName]!;
          avgPrice = prices.reduce((a, b) => a + b) / prices.length;
        }

        suggestions.add(ItemSuggestion(
          itemName: _capitalize(itemName),
          category: itemCategories[itemName] ?? 'Other',
          estimatedPrice: avgPrice,
          confidence: confidence,
          reason: SuggestionReason.frequentlyPurchased,
        ));
      }
    }

    suggestions.sort((a, b) => b.confidence.compareTo(a.confidence));
    return suggestions;
  }

  /// Get recipe completion suggestions
  List<ItemSuggestion> _getRecipeCompletionItems(
      List<ShoppingListItem> currentList,
      Set<String> excludeItems,
      ) {
    final Map<String, List<String>> recipeRules = {
      'pasta': ['tomato sauce', 'parmesan cheese', 'olive oil', 'garlic'],
      'spaghetti': ['tomato sauce', 'ground beef', 'parmesan cheese'],
      'chicken': ['rice', 'vegetables', 'olive oil', 'garlic'],
      'rice': ['soy sauce', 'vegetables', 'eggs'],
      'bread': ['butter', 'jam', 'peanut butter'],
      'eggs': ['bread', 'milk', 'cheese'],
      'milk': ['cereal', 'coffee', 'cookies'],
      'flour': ['eggs', 'butter', 'sugar', 'baking powder'],
      'ground beef': ['taco shells', 'cheese', 'lettuce', 'tomato'],
      'tortilla': ['cheese', 'salsa', 'avocado', 'sour cream'],
    };

    final suggestions = <ItemSuggestion>[];

    for (final item in currentList) {
      final itemNameLower = item.name.toLowerCase();

      for (final rule in recipeRules.entries) {
        if (itemNameLower.contains(rule.key)) {
          for (final complement in rule.value) {
            if (excludeItems.contains(complement)) continue;

            suggestions.add(ItemSuggestion(
              itemName: _capitalize(complement),
              category: _guessCategory(complement),
              confidence: 0.7,
              reason: SuggestionReason.recipeCompletion,
              relatedItems: [item.name],
            ));
          }
        }
      }
    }

    return _removeDuplicates(suggestions);
  }

  /// Remove duplicate suggestions
  List<ItemSuggestion> _removeDuplicates(List<ItemSuggestion> suggestions) {
    final seen = <String>{};
    final unique = <ItemSuggestion>[];

    for (final suggestion in suggestions) {
      final key = suggestion.itemName.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        unique.add(suggestion);
      }
    }

    return unique;
  }

  /// Default suggestions for new users
  List<ItemSuggestion> _getDefaultSuggestions() {
    return [
      ItemSuggestion(
        itemName: 'Milk',
        category: 'Dairy & Eggs',
        confidence: 0.8,
        reason: SuggestionReason.frequentlyPurchased,
      ),
      ItemSuggestion(
        itemName: 'Bread',
        category: 'Bakery',
        confidence: 0.8,
        reason: SuggestionReason.frequentlyPurchased,
      ),
      ItemSuggestion(
        itemName: 'Eggs',
        category: 'Dairy & Eggs',
        confidence: 0.75,
        reason: SuggestionReason.frequentlyPurchased,
      ),
      ItemSuggestion(
        itemName: 'Rice',
        category: 'Pantry & Dry Goods',
        confidence: 0.7,
        reason: SuggestionReason.frequentlyPurchased,
      ),
      ItemSuggestion(
        itemName: 'Chicken',
        category: 'Meat & Seafood',
        confidence: 0.7,
        reason: SuggestionReason.frequentlyPurchased,
      ),
    ];
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  String _guessCategory(String itemName) {
    final name = itemName.toLowerCase();

    if (name.contains('milk') ||
        name.contains('cheese') ||
        name.contains('yogurt') ||
        name.contains('egg')) {
      return 'Dairy & Eggs';
    } else if (name.contains('bread') ||
        name.contains('bagel') ||
        name.contains('roll')) {
      return 'Bakery';
    } else if (name.contains('chicken') ||
        name.contains('beef') ||
        name.contains('pork') ||
        name.contains('fish')) {
      return 'Meat & Seafood';
    } else if (name.contains('apple') ||
        name.contains('banana') ||
        name.contains('orange') ||
        name.contains('lettuce')) {
      return 'Produce';
    } else if (name.contains('pasta') ||
        name.contains('rice') ||
        name.contains('flour') ||
        name.contains('sugar')) {
      return 'Pantry & Dry Goods';
    }

    return 'Other';
  }
}