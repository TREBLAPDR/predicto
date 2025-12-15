import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product_models.dart';
import '../models/shopping_list_models.dart';
import 'settings_service.dart';

class ProductService {
  static ProductService? _instance;
  late SettingsService _settings;

  ProductService._();

  static Future<ProductService> getInstance() async {
    if (_instance == null) {
      _instance = ProductService._();
      _instance!._settings = await SettingsService.getInstance();
    }
    return _instance!;
  }

  String get _baseUrl => '${_settings.backendUrl}/api';

  // ==================== CRUD OPERATIONS ====================

  /// Create a new product
  Future<Product> createProduct({
    required String name,
    required String category,
    double? typicalPrice,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/products'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'category': category,
        'typical_price': typicalPrice,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return Product.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create product: ${response.body}');
    }
  }

  /// Get all products with optional filters
  Future<List<Product>> getProducts({
    String? category,
    String? search,
    int limit = 100,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
    };

    if (category != null) queryParams['category'] = category;
    if (search != null) queryParams['search'] = search;

    final uri = Uri.parse('$_baseUrl/products').replace(queryParameters: queryParams);

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['products'] as List)
          .map((json) => Product.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to get products');
    }
  }

  /// Get product by ID
  Future<Product> getProduct(String productId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/products/$productId'),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return Product.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Product not found');
    }
  }

  /// Update product
  Future<Product> updateProduct({
    required String productId,
    String? name,
    String? category,
    double? typicalPrice,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (category != null) updates['category'] = category;
    if (typicalPrice != null) updates['typical_price'] = typicalPrice;

    final response = await http.put(
      Uri.parse('$_baseUrl/products/$productId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(updates),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return Product.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update product');
    }
  }

  /// Delete product
  Future<void> deleteProduct(String productId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/products/$productId'),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to delete product');
    }
  }

  // ==================== PURCHASE TRACKING ====================

  /// Record a purchase
  Future<void> recordPurchase({
    required String productId,
    DateTime? purchaseDate,
    double? price,
    double quantity = 1.0,
    String? storeName,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/products/purchase'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'product_id': productId,
        'purchase_date': (purchaseDate ?? DateTime.now()).toIso8601String(),
        'price': price,
        'quantity': quantity,
        'store_name': storeName,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to record purchase');
    }
  }

  /// Record purchases for multiple items (from shopping list)
  Future<void> recordPurchases({
    required List<ShoppingListItem> items,
    DateTime? purchaseDate,
    String? storeName,
  }) async {
    for (final item in items.where((i) => i.isPurchased)) {
      try {
        // Try to find or create product
        final products = await getProducts(search: item.name);

        Product? product;
        if (products.isNotEmpty) {
          product = products.first;
        } else {
          // Create new product
          product = await createProduct(
            name: item.name,
            category: item.category,
            typicalPrice: item.price,
          );
        }

        // Record purchase
        await recordPurchase(
          productId: product.id,
          purchaseDate: purchaseDate,
          price: item.price,
          quantity: item.qty,
          storeName: storeName,
        );
      } catch (e) {
        print('Failed to record purchase for ${item.name}: $e');
        // Continue with other items
      }
    }
  }

  // ==================== ASSOCIATIONS ====================

  /// Get products frequently bought with this product
  Future<List<AssociatedProduct>> getAssociations(
      String productId, {
        double minConfidence = 0.3,
      }) async {
    final uri = Uri.parse('$_baseUrl/products/$productId/associations')
        .replace(queryParameters: {'min_confidence': minConfidence.toString()});

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List)
          .map((json) => AssociatedProduct.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to get associations');
    }
  }

  // ==================== PREDICTIONS ====================

  /// Get predicted products that might be needed soon
  Future<List<ProductPrediction>> getPredictions({
    int daysAhead = 7,
    double minConfidence = 0.5,
  }) async {
    final uri = Uri.parse('$_baseUrl/products/predictions/needed').replace(
      queryParameters: {
        'days_ahead': daysAhead.toString(),
        'min_confidence': minConfidence.toString(),
      },
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List)
          .map((json) => ProductPrediction.fromJson(json))
          .toList();
    } else {
      throw Exception('Failed to get predictions');
    }
  }

  // ==================== HELPERS ====================

  /// Search for product by name (fuzzy match)
  Future<List<Product>> searchProducts(String query) async {
    if (query.isEmpty) return [];
    return getProducts(search: query, limit: 20);
  }

  /// Get products by category
  Future<List<Product>> getProductsByCategory(String category) async {
    return getProducts(category: category);
  }
}