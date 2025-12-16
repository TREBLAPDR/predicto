import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/suggestion_models.dart';
import '../models/shopping_list_models.dart';
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
  // 1. RECORD PURCHASES
  // =========================================================

  Future<void> recordPurchases(List<ShoppingListItem> items) async {
    try {
      final settings = await SettingsService.getInstance();
      final baseUrl = settings.backendUrl;

      final purchasedItems = items.where((i) => i.isPurchased).toList();

      for (final item in purchasedItems) {
        // Save Local
        await _saveToLocalHistory(item);

        // Sync to Backend
        if (baseUrl.isNotEmpty) {
          try {
            await http.post(
              Uri.parse('$baseUrl/api/products/purchase'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'product_id': 'unknown',
                'name': item.name,
                'purchase_date': DateTime.now().toIso8601String(),
                'price': item.price,
                'quantity': item.qty,
              }),
            );
          } catch (e) {
            print("Sync failed for ${item.name}: $e");
          }
        }
      }
    } catch (e) {
      print("Error recording: $e");
    }
  }

  // =========================================================
  // 2. GET AI SUGGESTIONS
  // =========================================================

  Future<List<ItemSuggestion>> getAISuggestions() async {
    try {
      final settings = await SettingsService.getInstance();
      if (settings.backendUrl.isEmpty) return [];

      final url = Uri.parse('${settings.backendUrl}/api/suggestions/ai');

      // 25s timeout for AI thinking
      final response = await http.get(url).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['suggestions'] == null) return [];

        final List<dynamic> list = data['suggestions'];
        return list.map((json) => ItemSuggestion.fromJson(json)).toList();
      } else {
        print('Backend Error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('AI Connection Error: $e');
      return [];
    }
  }

  // =========================================================
  // 3. HELPERS
  // =========================================================

  Future<void> _saveToLocalHistory(ShoppingListItem item) async {
    final history = await getLocalHistory();
    history.add(PurchaseHistory(
      itemName: item.name,
      purchaseDate: DateTime.now(),
      category: item.category,
      price: item.price,
    ));
    if (history.length > 500) history.removeRange(0, history.length - 500);

    final jsonList = history.map((e) => e.toJson()).toList();
    await _prefs.setString(_keyPurchaseHistory, jsonEncode(jsonList));
  }

  Future<List<PurchaseHistory>> getLocalHistory() async {
    final String? json = _prefs.getString(_keyPurchaseHistory);
    if (json == null) return [];
    try {
      final List<dynamic> data = jsonDecode(json);
      return data.map((e) => PurchaseHistory.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }
}