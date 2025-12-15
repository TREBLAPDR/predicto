import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shopping_list_models.dart'; // ItemCategory is inside here
import '../models/receipt_models.dart';

class ShoppingListService {
  static const String _keyLists = 'shopping_lists';
  static const String _keyCurrentList = 'current_list_id';

  static ShoppingListService? _instance;
  late SharedPreferences _prefs;

  ShoppingListService._();

  static Future<ShoppingListService> getInstance() async {
    if (_instance == null) {
      _instance = ShoppingListService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// Get all shopping lists
  Future<List<ShoppingList>> getAllLists() async {
    final String? listsJson = _prefs.getString(_keyLists);
    if (listsJson == null) return [];

    final List<dynamic> listData = jsonDecode(listsJson);
    return listData.map((json) => ShoppingList.fromJson(json)).toList();
  }

  /// Get active lists only
  Future<List<ShoppingList>> getActiveLists() async {
    final all = await getAllLists();
    return all.where((list) => list.status == ListStatus.active).toList();
  }

  /// Get completed/history lists
  Future<List<ShoppingList>> getHistoryLists() async {
    final all = await getAllLists();
    return all.where((list) => list.status == ListStatus.completed).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // Most recent first
  }

  /// Save all lists
  Future<void> _saveLists(List<ShoppingList> lists) async {
    final String listsJson = jsonEncode(lists.map((l) => l.toJson()).toList());
    await _prefs.setString(_keyLists, listsJson);
  }

  /// Create new shopping list with optional target date
  Future<ShoppingList> createList(
      String name, {
        String? storeName,
        DateTime? targetDate,
      }) async {
    final lists = await getAllLists();

    final newList = ShoppingList(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      items: [],
      storeName: storeName,
      status: ListStatus.active,
    );

    lists.add(newList);
    await _saveLists(lists);
    await setCurrentList(newList.id);

    return newList;
  }

  /// Predict list name based on date and time
  static String predictListName(DateTime? targetDate) {
    final date = targetDate ?? DateTime.now();
    final dayOfWeek = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ][date.weekday - 1];
    final now = DateTime.now();

    // If target date is today
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      if (now.hour < 12) {
        return 'Morning Shopping';
      } else if (now.hour < 18) {
        return 'Afternoon Shopping';
      } else {
        return 'Evening Shopping';
      }
    }

    // If tomorrow
    final tomorrow = now.add(const Duration(days: 1));
    if (date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day) {
      return 'Tomorrow\'s Shopping';
    }

    // If this week
    final daysUntil = date.difference(now).inDays;
    if (daysUntil > 0 && daysUntil <= 7) {
      return '$dayOfWeek Shopping';
    }

    // If next week
    if (daysUntil > 7 && daysUntil <= 14) {
      return 'Next $dayOfWeek Shopping';
    }

    // Default
    return 'Shopping ${date.month}/${date.day}';
  }

  /// Get current active list
  Future<ShoppingList?> getCurrentList() async {
    final currentId = _prefs.getString(_keyCurrentList);
    if (currentId == null) return null;

    final lists = await getAllLists();
    try {
      return lists.firstWhere((list) => list.id == currentId);
    } catch (e) {
      return null;
    }
  }

  /// Get list by ID
  Future<ShoppingList?> getListById(String id) async {
    final lists = await getAllLists();
    try {
      return lists.firstWhere((list) => list.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Set current active list
  Future<void> setCurrentList(String listId) async {
    await _prefs.setString(_keyCurrentList, listId);
  }

  /// Add items from parsed receipt
  Future<ShoppingList> addItemsFromReceipt(
      ParsedReceipt receipt,
      List<bool> itemsToAdd,
      ) async {
    var currentList = await getCurrentList();

    if (currentList == null) {
      final listName = receipt.storeName != null
          ? '${receipt.storeName} - ${receipt.date ?? "Today"}'
          : 'Shopping List ${DateTime.now().toString().substring(0, 10)}';

      currentList = await createList(listName, storeName: receipt.storeName);
    }

    int addedCount = 0;
    for (int i = 0; i < receipt.items.length; i++) {
      if (i < itemsToAdd.length && itemsToAdd[i]) {
        final receiptItem = receipt.items[i];

        // ItemCategory is available via shopping_list_models.dart
        final category = ItemCategory.categorizeItem(receiptItem.name);

        // Generate truly unique ID using timestamp + index
        final timestamp = DateTime.now().microsecondsSinceEpoch;
        final uniqueId = '${timestamp}_$i';

        currentList.items.add(ShoppingListItem(
          id: uniqueId,
          name: receiptItem.name,
          price: receiptItem.price,
          qty: receiptItem.qty ?? 1.0,
          category: category,
        ));

        addedCount++;
        // Small delay to ensure unique timestamps if called rapidly in loop
        await Future.delayed(const Duration(milliseconds: 1));
      }
    }

    currentList.updatedAt = DateTime.now();
    await _updateList(currentList);

    return currentList;
  }

  /// Add single item manually
  Future<void> addItem(String listId, ShoppingListItem item) async {
    final lists = await getAllLists();
    final listIndex = lists.indexWhere((l) => l.id == listId);

    if (listIndex != -1) {
      // Ensure item has unique ID
      if (lists[listIndex].items.any((existing) => existing.id == item.id)) {
        // Regenerate ID if duplicate found
        item = ShoppingListItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${item.name.hashCode}',
          name: item.name,
          price: item.price,
          qty: item.qty,
          category: item.category,
          isPurchased: item.isPurchased,
          notes: item.notes,
        );
      }

      lists[listIndex].items.add(item);
      lists[listIndex].updatedAt = DateTime.now();
      await _saveLists(lists);
    }
  }

  /// Update item
  Future<void> updateItem(String listId, ShoppingListItem item) async {
    final lists = await getAllLists();
    final listIndex = lists.indexWhere((l) => l.id == listId);

    if (listIndex != -1) {
      final itemIndex = lists[listIndex].items.indexWhere((i) => i.id == item.id);
      if (itemIndex != -1) {
        lists[listIndex].items[itemIndex] = item;
        lists[listIndex].updatedAt = DateTime.now();
        await _saveLists(lists);
      }
    }
  }

  /// Delete item
  Future<void> deleteItem(String listId, String itemId) async {
    final lists = await getAllLists();
    final listIndex = lists.indexWhere((l) => l.id == listId);

    if (listIndex != -1) {
      lists[listIndex].items.removeWhere((i) => i.id == itemId);
      lists[listIndex].updatedAt = DateTime.now();
      await _saveLists(lists);
    }
  }

  /// Toggle item purchased status
  Future<void> toggleItemPurchased(String listId, String itemId) async {
    final lists = await getAllLists();
    final listIndex = lists.indexWhere((l) => l.id == listId);

    if (listIndex != -1) {
      final itemIndex = lists[listIndex].items.indexWhere((i) => i.id == itemId);
      if (itemIndex != -1) {
        lists[listIndex].items[itemIndex].isPurchased =
        !lists[listIndex].items[itemIndex].isPurchased;
        lists[listIndex].updatedAt = DateTime.now();
        await _saveLists(lists);
      }
    }
  }

  /// Update entire list
  Future<void> _updateList(ShoppingList list) async {
    final lists = await getAllLists();
    final index = lists.indexWhere((l) => l.id == list.id);

    if (index != -1) {
      lists[index] = list;
      await _saveLists(lists);
    }
  }

  /// Mark list as completed and move to history
  Future<void> completeList(String listId) async {
    final lists = await getAllLists();
    final index = lists.indexWhere((l) => l.id == listId);

    if (index != -1) {
      lists[index].status = ListStatus.completed;
      lists[index].isCompleted = true;
      lists[index].updatedAt = DateTime.now();
      await _saveLists(lists);

      // Clear current list if it was this one
      if (_prefs.getString(_keyCurrentList) == listId) {
        await _prefs.remove(_keyCurrentList);
      }
    }
  }

  /// Rename list
  Future<void> renameList(String listId, String newName) async {
    final lists = await getAllLists();
    final index = lists.indexWhere((l) => l.id == listId);

    if (index != -1) {
      lists[index].name = newName;
      lists[index].updatedAt = DateTime.now();
      await _saveLists(lists);
    }
  }

  /// Delete list permanently
  Future<void> deleteList(String listId) async {
    final lists = await getAllLists();
    lists.removeWhere((l) => l.id == listId);
    await _saveLists(lists);

    if (_prefs.getString(_keyCurrentList) == listId) {
      await _prefs.remove(_keyCurrentList);
    }
  }

  /// Archive list
  Future<void> archiveList(String listId) async {
    final lists = await getAllLists();
    final index = lists.indexWhere((l) => l.id == listId);

    if (index != -1) {
      lists[index].status = ListStatus.archived;
      lists[index].updatedAt = DateTime.now();
      await _saveLists(lists);
    }
  }

  /// Get items by category for a list
  Map<String, List<ShoppingListItem>> getItemsByCategory(ShoppingList list) {
    final Map<String, List<ShoppingListItem>> categorized = {};

    for (final item in list.items) {
      if (!categorized.containsKey(item.category)) {
        categorized[item.category] = [];
      }
      categorized[item.category]!.add(item);
    }

    return categorized;
  }

  /// Calculate list statistics
  Map<String, dynamic> getListStatistics(ShoppingList list) {
    final totalItems = list.items.length;
    final purchasedItems = list.items.where((i) => i.isPurchased).length;
    final totalCost = list.items.fold<double>(
      0.0,
          (sum, item) => sum + ((item.price ?? 0) * item.qty),
    );
    final purchasedCost = list.items
        .where((i) => i.isPurchased)
        .fold<double>(0.0, (sum, item) => sum + ((item.price ?? 0) * item.qty));

    return {
      'totalItems': totalItems,
      'purchasedItems': purchasedItems,
      'remainingItems': totalItems - purchasedItems,
      'totalCost': totalCost,
      'purchasedCost': purchasedCost,
      'remainingCost': totalCost - purchasedCost,
      'completionPercent':
      totalItems > 0 ? (purchasedItems / totalItems * 100) : 0.0,
    };
  }
}