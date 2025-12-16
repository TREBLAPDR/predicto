import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/suggestion_models.dart';
import '../models/shopping_list_models.dart';
import '../models/product_models.dart';
import 'settings_service.dart';

class SuggestionService {
  static const String _keyPurchaseHistory = 'purchase_history';
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

  // =========================================================
  // 1. RECORD PURCHASES (Syncs to Backend for AI)
  // =========================================================

  /// Records purchased items to the Backend Database so the AI can learn.
  Future<void> recordPurchases(List<ShoppingListItem> items) async {
    try {
      final settings = await SettingsService.getInstance();
      final baseUrl = settings.backendUrl;

      // Filter only purchased items
      final purchasedItems = items.where((i) => i.isPurchased).toList();

      for (final item in purchasedItems) {
        // 1. Save to local history (fast fallback)
        await _saveToLocalHistory(item);

        // 2. Send to Backend (For AI Analysis)
        if (baseUrl.isNotEmpty) {
          try {
            await http.post(
              Uri.parse('$baseUrl/api/products/purchase'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'product_id': 'unknown', // Backend will match by name
                'name': item.name, // Important: Send name so backend can find/create product
                'purchase_date': DateTime.now().toIso8601String(),
                'price': item.price,
                'quantity': item.qty,
                'store_name': 'Unknown', // You can pass store name if available
              }),
            );
          } catch (e) {
            print("Failed to sync item ${item.name} to backend: $e");
          }
        }
      }
    } catch (e) {
      print("Error recording purchases: $e");
    }
  }

  // =========================================================
  // 2. GET AI SUGGESTIONS (From Backend/Gemini)
  // =========================================================

  Future<List<ItemSuggestion>> getAISuggestions() async {
    try {
      final settings = await SettingsService.getInstance();

      // If no backend URL is set, return empty
      if (settings.backendUrl.isEmpty) {
        print("No backend URL configured");
        return [];
      }

      final url = Uri.parse('${settings.backendUrl}/api/suggestions/ai');

      // 25s timeout because AI reasoning takes time
      final response = await http.get(url).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Safety check: ensure 'suggestions' exists
        if (data['suggestions'] == null) return [];

        final List<dynamic> suggestionsJson = data['suggestions'];

        return suggestionsJson.map((json) {
          return ItemSuggestion(
            itemName: json['name'],
            category: json['category'] ?? 'Other',
            estimatedPrice: json['estimatedPrice']?.toDouble(),
            confidence: json['confidence']?.toDouble() ?? 0.0,
            reason: _mapReason(json['reason']),
            relatedItems: [],
          );
        }).toList();
      } else {
        print('AI Error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('AI Connection Error: $e');
      return [];
    }
  }

  // =========================================================
  // 3. STANDARD / LOCAL SUGGESTIONS (Fallback)
  // =========================================================

  Future<List<ItemSuggestion>> generateSuggestions({
    required List<ShoppingListItem> currentList,
    int maxSuggestions = 10,
  }) async {
    // Simple local logic: suggest items from history not currently in list
    final history = await _getLocalHistory();
    final currentNames = currentList.map((i) => i.name.toLowerCase()).toSet();

    final suggestions = <ItemSuggestion>[];

    // Sort history by frequency (simple mock logic)
    // In a real app, you'd group by name and count
    final uniqueItems = <String>{};

    for (final item in history.reversed) {
      if (suggestions.length >= maxSuggestions) break;
      if (currentNames.contains(item.itemName.toLowerCase())) continue;
      if (uniqueItems.contains(item.itemName.toLowerCase())) continue;

      uniqueItems.add(item.itemName.toLowerCase());
      suggestions.add(ItemSuggestion(
        itemName: item.itemName,
        category: item.category,
        confidence: 0.5, // Default low confidence for local
        reason: SuggestionReason.frequentlyPurchased,
      ));
    }

    return suggestions;
  }

  // =========================================================
  // PRIVATE HELPERS
  // =========================================================

  Future<void> _saveToLocalHistory(ShoppingListItem item) async {
    final history = await _getLocalHistory();
    history.add(PurchaseHistory(
      itemName: item.name,
      purchaseDate: DateTime.now(),
      category: item.category,
      price: item.price,
    ));

    // Limit local history size
    if (history.length > 500) {
      history.removeRange(0, history.length - 500);
    }

    final jsonList = history.map((e) => e.toJson()).toList();
    await _prefs.setString(_keyPurchaseHistory, jsonEncode(jsonList));
  }

  Future<List<PurchaseHistory>> _getLocalHistory() async {
    final String? json = _prefs.getString(_keyPurchaseHistory);
    if (json == null) return [];
    try {
      final List<dynamic> data = jsonDecode(json);
      return data.map((e) => PurchaseHistory.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  SuggestionReason _mapReason(String? reasonText) {
    if (reasonText == null) return SuggestionReason.frequentlyPurchased;
    if (reasonText.toLowerCase().contains("season")) return SuggestionReason.seasonalTrend;
    if (reasonText.toLowerCase().contains("low")) return SuggestionReason.runningLow;
    return SuggestionReason.frequentlyPurchased;
  }
}