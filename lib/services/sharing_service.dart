import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shared_list_models.dart';
import '../models/shopping_list_models.dart';
import 'settings_service.dart';

class SharingService {
  static const String _keySharedLists = 'shared_lists';

  static SharingService? _instance;
  late SharedPreferences _prefs;
  late SettingsService _settings;

  SharingService._();

  static Future<SharingService> getInstance() async {
    if (_instance == null) {
      _instance = SharingService._();
      _instance!._prefs = await SharedPreferences.getInstance();
      _instance!._settings = await SettingsService.getInstance();
    }
    return _instance!;
  }

  /// Create a shareable link for a list
  Future<SharedListInfo> createShareLink({
    required ShoppingList list,
    required SharePermission permission,
    int daysValid = 7,
  }) async {
    final baseUrl = _settings.backendUrl;
    final endpoint = Uri.parse('$baseUrl/api/share/create');

    try {
      final response = await http.post(
        endpoint,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'listId': list.id,
          'listName': list.name,
          'items': list.items.map((item) => item.toJson()).toList(),
          'permission': permission.name,
          'daysValid': daysValid,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return SharedListInfo.fromJson(data['shareInfo']);
      } else {
        throw Exception('Failed to create share link: ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Access a shared list via share ID
  Future<ShoppingList> accessSharedList(String shareId) async {
    final baseUrl = _settings.backendUrl;
    final endpoint = Uri.parse('$baseUrl/api/share/$shareId');

    try {
      final response = await http.get(endpoint)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['expired'] == true) {
          throw Exception('This share link has expired');
        }

        final sharedInfo = SharedListInfo.fromJson(data['shareInfo']);
        final listData = data['list'];

        // Convert to ShoppingList
        return ShoppingList(
          id: shareId, // Use shareId as temporary ID
          name: '${listData['listName']} (Shared)',
          createdAt: DateTime.parse(listData['createdAt']),
          updatedAt: DateTime.now(),
          items: (listData['items'] as List)
              .map((item) => ShoppingListItem.fromJson(item))
              .toList(),
          storeName: listData['storeName'],
        );
      } else if (response.statusCode == 404) {
        throw Exception('Share link not found');
      } else {
        throw Exception('Failed to access shared list: ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  /// Get share URL for displaying to user
  String getShareUrl(String shareId) {
    // For a web app, this would be your app's URL
    // For mobile, use a deep link or just the share code
    return 'shopping-list://share/$shareId';
  }

  /// Save accessed shared lists locally
  Future<void> saveAccessedShareList(SharedListInfo shareInfo) async {
    final accessed = await getAccessedShareLists();

    // Remove if already exists (update)
    accessed.removeWhere((s) => s.shareId == shareInfo.shareId);

    // Add to beginning
    accessed.insert(0, shareInfo);

    // Keep only last 10
    if (accessed.length > 10) {
      accessed.removeRange(10, accessed.length);
    }

    await _saveAccessedLists(accessed);
  }

  /// Get list of previously accessed shared lists
  Future<List<SharedListInfo>> getAccessedShareLists() async {
    final String? listsJson = _prefs.getString(_keySharedLists);
    if (listsJson == null) return [];

    final List<dynamic> listData = jsonDecode(listsJson);
    return listData
        .map((json) => SharedListInfo.fromJson(json))
        .where((s) => !s.isExpired) // Filter out expired
        .toList();
  }

  Future<void> _saveAccessedLists(List<SharedListInfo> lists) async {
    final String listsJson = jsonEncode(lists.map((l) => l.toJson()).toList());
    await _prefs.setString(_keySharedLists, listsJson);
  }

  /// Delete a share link (owner only)
  Future<void> deleteShareLink(String shareId) async {
    final baseUrl = _settings.backendUrl;
    final endpoint = Uri.parse('$baseUrl/api/share/$shareId');

    try {
      final response = await http.delete(endpoint)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to delete share link');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
}