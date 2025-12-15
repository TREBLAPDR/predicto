class Product {
  final String id;
  String name;
  String category;
  double? typicalPrice;
  int purchaseCount;
  DateTime? lastPurchasedDate;
  double? averageDaysBetweenPurchases;
  DateTime createdAt;
  DateTime updatedAt;

  Product({
    required this.id,
    required this.name,
    required this.category,
    this.typicalPrice,
    required this.purchaseCount,
    this.lastPurchasedDate,
    this.averageDaysBetweenPurchases,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      category: json['category'],
      typicalPrice: json['typical_price']?.toDouble(),
      purchaseCount: json['purchase_count'] ?? 0,
      lastPurchasedDate: json['last_purchased_date'] != null
          ? DateTime.parse(json['last_purchased_date'])
          : null,
      averageDaysBetweenPurchases: json['average_days_between_purchases']?.toDouble(),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'typical_price': typicalPrice,
    'purchase_count': purchaseCount,
    'last_purchased_date': lastPurchasedDate?.toIso8601String(),
    'average_days_between_purchases': averageDaysBetweenPurchases,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  // Helper: Check if product might be needed soon
  bool isPredictedNeeded({double threshold = 0.8}) {
    if (lastPurchasedDate == null || averageDaysBetweenPurchases == null) {
      return false;
    }

    final daysSince = DateTime.now().difference(lastPurchasedDate!).inDays;
    return daysSince >= (averageDaysBetweenPurchases! * threshold);
  }

  // Helper: Get prediction confidence
  double getPredictionConfidence() {
    if (lastPurchasedDate == null || averageDaysBetweenPurchases == null) {
      return 0.0;
    }

    final daysSince = DateTime.now().difference(lastPurchasedDate!).inDays;
    if (averageDaysBetweenPurchases! <= 0) return 0.0;

    return (daysSince / averageDaysBetweenPurchases!).clamp(0.0, 1.0);
  }
}

class AssociatedProduct {
  final Product product;
  final double confidence;
  final int coPurchaseCount;

  AssociatedProduct({
    required this.product,
    required this.confidence,
    required this.coPurchaseCount,
  });

  factory AssociatedProduct.fromJson(Map<String, dynamic> json) {
    return AssociatedProduct(
      product: Product.fromJson(json['product']),
      confidence: json['confidence'].toDouble(),
      coPurchaseCount: json['co_purchase_count'],
    );
  }
}

class ProductPrediction {
  final Product product;
  final double confidence;
  final int daysSincePurchase;
  final double expectedDays;

  ProductPrediction({
    required this.product,
    required this.confidence,
    required this.daysSincePurchase,
    required this.expectedDays,
  });

  factory ProductPrediction.fromJson(Map<String, dynamic> json) {
    return ProductPrediction(
      product: Product.fromJson(json['product']),
      confidence: json['confidence'].toDouble(),
      daysSincePurchase: json['days_since_purchase'],
      expectedDays: json['expected_days'].toDouble(),
    );
  }
}