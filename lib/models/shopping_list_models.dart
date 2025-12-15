class ShoppingList {
  String id;
  String name;
  DateTime createdAt;
  DateTime updatedAt;
  List<ShoppingListItem> items;
  String? storeName;
  bool isCompleted;
  ListStatus status; // NEW

  ShoppingList({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    this.storeName,
    this.isCompleted = false,
    this.status = ListStatus.active, // NEW
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(),
    'storeName': storeName,
    'isCompleted': isCompleted,
    'status': status.name, // NEW
  };

  factory ShoppingList.fromJson(Map<String, dynamic> json) {
    return ShoppingList(
      id: json['id'],
      name: json['name'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      items: (json['items'] as List)
          .map((item) => ShoppingListItem.fromJson(item))
          .toList(),
      storeName: json['storeName'],
      isCompleted: json['isCompleted'] ?? false,
      status: ListStatus.values.firstWhere(
            (e) => e.name == json['status'],
        orElse: () => ListStatus.active,
      ), // NEW
    );
  }
}

// NEW
enum ListStatus {
  active,      // Current shopping list
  completed,   // Finished shopping
  archived,    // Old lists
}

class ShoppingListItem {
  String id;
  String name;
  double? price;
  double qty;
  String category;
  bool isPurchased;
  String? notes;

  ShoppingListItem({
    required this.id,
    required this.name,
    this.price,
    required this.qty,
    required this.category,
    this.isPurchased = false,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'qty': qty,
    'category': category,
    'isPurchased': isPurchased,
    'notes': notes,
  };

  factory ShoppingListItem.fromJson(Map<String, dynamic> json) {
    return ShoppingListItem(
      id: json['id'],
      name: json['name'],
      price: json['price']?.toDouble(),
      qty: json['qty']?.toDouble() ?? 1.0,
      category: json['category'] ?? 'Other',
      isPurchased: json['isPurchased'] ?? false,
      notes: json['notes'],
    );
  }
}

class ItemCategory {
  static const String produce = 'Produce';
  static const String meat = 'Meat & Seafood';
  static const String dairy = 'Dairy & Eggs';
  static const String bakery = 'Bakery';
  static const String pantry = 'Pantry & Dry Goods';
  static const String frozen = 'Frozen';
  static const String beverages = 'Beverages';
  static const String snacks = 'Snacks';
  static const String household = 'Household';
  static const String personal = 'Personal Care';
  static const String other = 'Other';

  static List<String> all = [
    produce,
    meat,
    dairy,
    bakery,
    pantry,
    frozen,
    beverages,
    snacks,
    household,
    personal,
    other,
  ];

  static String categorizeItem(String itemName) {
    final name = itemName.toLowerCase();

    // Produce
    if (name.contains('apple') || name.contains('banana') ||
        name.contains('orange') || name.contains('lettuce') ||
        name.contains('tomato') || name.contains('onion') ||
        name.contains('potato') || name.contains('fruit') ||
        name.contains('vegetable') || name.contains('carrot')) {
      return produce;
    }

    // Meat & Seafood
    if (name.contains('chicken') || name.contains('beef') ||
        name.contains('pork') || name.contains('fish') ||
        name.contains('salmon') || name.contains('meat') ||
        name.contains('steak') || name.contains('turkey')) {
      return meat;
    }

    // Dairy & Eggs
    if (name.contains('milk') || name.contains('cheese') ||
        name.contains('yogurt') || name.contains('egg') ||
        name.contains('butter') || name.contains('cream')) {
      return dairy;
    }

    // Bakery
    if (name.contains('bread') || name.contains('bagel') ||
        name.contains('roll') || name.contains('muffin') ||
        name.contains('donut') || name.contains('cake')) {
      return bakery;
    }

    // Frozen
    if (name.contains('frozen') || name.contains('ice cream')) {
      return frozen;
    }

    // Beverages
    if (name.contains('juice') || name.contains('soda') ||
        name.contains('water') || name.contains('coffee') ||
        name.contains('tea') || name.contains('drink')) {
      return beverages;
    }

    // Snacks
    if (name.contains('chip') || name.contains('cookie') ||
        name.contains('candy') || name.contains('cracker') ||
        name.contains('popcorn')) {
      return snacks;
    }

    // Household
    if (name.contains('soap') || name.contains('detergent') ||
        name.contains('cleaner') || name.contains('paper towel') ||
        name.contains('tissue') || name.contains('trash bag')) {
      return household;
    }

    // Personal Care
    if (name.contains('shampoo') || name.contains('toothpaste') ||
        name.contains('deodorant') || name.contains('lotion')) {
      return personal;
    }

    return other;
  }
}