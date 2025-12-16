import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/suggestion_models.dart';
import '../models/shopping_list_models.dart';
import '../models/product_models.dart';
import 'settings_service.dart';

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

    await _savePurchaseHistory(history);
  }

  /// Get full purchase history
  Future<List<PurchaseHistory>> getPurchaseHistory() async {
    final String? json = _prefs.getString(_keyPurchaseHistory);
    if (json == null) return [];

    try {
      final List<dynamic> data = jsonDecode(json);
      return data.map((e) => PurchaseHistory.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _savePurchaseHistory(List<PurchaseHistory> history) async {
    final String json = jsonEncode(history.map((e) => e.toJson()).toList());
    await _prefs.setString(_keyPurchaseHistory, json);
  }

  // =========================================================
  // NEW: AI SUGGESTION METHODS
  // =========================================================

  /// Call the backend to get AI-generated suggestions
  Future<List<ItemSuggestion>> getAISuggestions() async {
    try {
      final settings = await SettingsService.getInstance();
      final url = Uri.parse('${settings.backendUrl}/api/suggestions/ai');

      // Use a longer timeout for AI generation (25 seconds)
      final response = await http.get(url).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> suggestionsJson = data['suggestions'];

        return suggestionsJson.map((json) {
          return ItemSuggestion(
            itemName: json['name'],
            category: json['category'] ?? 'Other',
            estimatedPrice: json['estimatedPrice']?.toDouble(),
            confidence: json['confidence']?.toDouble() ?? 0.0,
            // Map the reason to your enum, or default to frequentlyPurchased
            reason: SuggestionReason.frequentlyPurchased,
            relatedItems: [],
          );
        }).toList();
      } else {
        print('Failed to load AI suggestions: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('AI Suggestion Error: $e');
      return [];
    }
  }

  /// Local logic fallback (existing functionality)
  Future<List<ItemSuggestion>> generateSuggestions({
    required List<ShoppingListItem> currentList,
    int maxSuggestions = 10,
  }) async {
    // Return dummy data or implement local logic here
    // This allows the "Standard" tab to still work
    return [
      ItemSuggestion(
        itemName: 'Rice',
        category: 'Pantry',
        confidence: 0.8,
        reason: SuggestionReason.frequentlyPurchased,
      ),
      ItemSuggestion(
        itemName: 'Eggs',
        category: 'Dairy',
        confidence: 0.75,
        reason: SuggestionReason.runningLow,
      ),
    ];
  }
}