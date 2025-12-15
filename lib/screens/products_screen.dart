import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/product_models.dart';
import '../models/shopping_list_models.dart';
import '../services/product_service.dart';
import '../services/shopping_list_service.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late ProductService _productService;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);

    try {
      _productService = await ProductService.getInstance();
      final products = await _productService.getProducts(
        category: _selectedCategory,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );

      if (mounted) {
        setState(() {
          _products = products;
          _filteredProducts = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Error'),
            description: Text('Error loading products: $e'),
          ),
        );
      }
    }
  }

  void _filterProducts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products
            .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _addProduct() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    String selectedCategory = ItemCategory.other;

    final created = await showShadDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ShadDialog(
          title: const Text('Add Product'),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text('Product Name', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ShadInput(
                    controller: nameController,
                    placeholder: const Text('e.g., Milk 2% Gallon'),
                  ),
                  const SizedBox(height: 12),
                  // Removed const because of custom font 'Roboto'
                  const Text('Typical Price (\u20B1)', style: TextStyle(fontSize: 13, fontFamily: 'Roboto')),
                  const SizedBox(height: 4),
                  ShadInput(
                    controller: priceController,
                    placeholder: const Text('0.00'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  const Text('Category', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ShadSelect<String>(
                    placeholder: const Text('Select Category'),
                    initialValue: selectedCategory,
                    options: ItemCategory.all.map((cat) =>
                        ShadOption(value: cat, child: Text(cat))
                    ).toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => selectedCategory = value);
                    },
                    selectedOptionBuilder: (context, value) => Text(value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (created == true && nameController.text.isNotEmpty) {
      try {
        await _productService.createProduct(
          name: nameController.text,
          category: selectedCategory,
          typicalPrice: double.tryParse(priceController.text),
        );

        if (!mounted) return;
        ShadToaster.of(context).show(
          const ShadToast(description: Text('Product added')),
        );

        await _loadProducts();
      } catch (e) {
        if (!mounted) return;
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Error'),
            description: Text(e.toString()),
          ),
        );
      }
    }
  }

  Future<void> _editProduct(Product product) async {
    final nameController = TextEditingController(text: product.name);
    final priceController = TextEditingController(
      text: product.typicalPrice?.toStringAsFixed(2) ?? '',
    );
    String selectedCategory = product.category;

    final updated = await showShadDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ShadDialog(
          title: const Text('Edit Product'),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text('Product Name', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ShadInput(controller: nameController),
                  const SizedBox(height: 12),
                  const Text('Typical Price (\u20B1)', style: TextStyle(fontSize: 13, fontFamily: 'Roboto')),
                  const SizedBox(height: 4),
                  ShadInput(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  const Text('Category', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ShadSelect<String>(
                    initialValue: selectedCategory,
                    options: ItemCategory.all.map((cat) =>
                        ShadOption(value: cat, child: Text(cat))
                    ).toList(),
                    onChanged: (value) {
                      if (value != null) setDialogState(() => selectedCategory = value);
                    },
                    selectedOptionBuilder: (context, value) => Text(value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (updated == true) {
      try {
        await _productService.updateProduct(
          productId: product.id,
          name: nameController.text,
          category: selectedCategory,
          typicalPrice: double.tryParse(priceController.text),
        );

        if (!mounted) return;
        ShadToaster.of(context).show(
          const ShadToast(description: Text('Product updated')),
        );

        await _loadProducts();
      } catch (e) {
        if (!mounted) return;
        ShadToaster.of(context).show(
          ShadToast.destructive(title: const Text('Error'), description: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Delete Product?'),
        description: Text('Delete "${product.name}"? This cannot be undone.'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _productService.deleteProduct(product.id);

        if (!mounted) return;
        ShadToaster.of(context).show(
          const ShadToast(description: Text('Product deleted')),
        );

        await _loadProducts();
      } catch (e) {
        if (!mounted) return;
        ShadToaster.of(context).show(
          ShadToast.destructive(title: const Text('Error'), description: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _addToShoppingList(Product product) async {
    try {
      final listService = await ShoppingListService.getInstance();
      var currentList = await listService.getCurrentList();

      if (currentList == null) {
        currentList = await listService.createList('My Shopping List');
      }

      final newItem = ShoppingListItem(
        id: '${DateTime.now().microsecondsSinceEpoch}_${product.id}',
        name: product.name,
        price: product.typicalPrice,
        qty: 1.0,
        category: product.category,
      );

      await listService.addItem(currentList.id, newItem);

      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          title: const Text('Added'),
          description: Text('Added "${product.name}" to shopping list'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast.destructive(title: const Text('Error'), description: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Zinc 950
      appBar: AppBar(
        title: const Text('Products', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            // FIXED: Changed filter to listFilter
            icon: const Icon(LucideIcons.listFilter, color: Colors.white70),
            color: const Color(0xFF18181B),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('All Categories', style: TextStyle(color: Colors.white))),
              ...ItemCategory.all.map((cat) =>
                  PopupMenuItem(value: cat, child: Text(cat, style: const TextStyle(color: Colors.white)))
              ),
            ],
            onSelected: (value) {
              setState(() {
                _selectedCategory = value == 'all' ? null : value;
              });
              _loadProducts();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ShadInput(
              controller: _searchController,
              placeholder: const Text('Search products...'),
              // FIXED: Correctly using leading instead of prefix
              leading: const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Icon(LucideIcons.search, size: 16, color: Colors.grey),
              ),
              onChanged: _filterProducts,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredProducts.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Removed const
            Icon(LucideIcons.packageOpen, size: 64, color: Colors.grey.shade800),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isEmpty ? 'No products yet' : 'No products found',
              // Removed const
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? 'Add products to track purchases'
                  : 'Try a different search term',
              // Removed const
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadProducts,
        color: Colors.white,
        backgroundColor: const Color(0xFF27272A),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _filteredProducts.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final product = _filteredProducts[index];
            final isPredicted = product.isPredictedNeeded();

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF18181B), // Zinc 900
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  // Removed const
                  color: isPredicted ? Colors.orange.withOpacity(0.3) : Colors.white10,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    // Removed const
                    color: isPredicted ? Colors.orange.withOpacity(0.2) : Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      product.purchaseCount.toString(),
                      style: TextStyle(
                        color: isPredicted ? Colors.orange : Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 16),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Removed const
                        Text(product.category, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        const SizedBox(width: 8),
                        if (product.lastPurchasedDate != null)
                          Text(
                            '•  Last: ${_formatDate(product.lastPurchasedDate!)}',
                            // Removed const
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                      ],
                    ),
                    if (isPredicted) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          // Removed const
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // FIXED: Renamed alertTriangle -> triangleAlert
                            const Icon(LucideIcons.triangleAlert, size: 12, color: Colors.orange),
                            const SizedBox(width: 6),
                            Text(
                              'Likely needed soon (${product.getPredictionConfidence().toStringAsFixed(0)}%)',
                              style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (product.typicalPrice != null)
                      Text(
                        '\u20B1${product.typicalPrice!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: const Icon(LucideIcons.ellipsisVertical, size: 18, color: Colors.grey),
                      color: const Color(0xFF27272A),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'add',
                          child: Row(
                            children: [
                              Icon(LucideIcons.plus, size: 16, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Add to List', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(LucideIcons.pencil, size: 16, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Edit', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'add') {
                          _addToShoppingList(product);
                        } else if (value == 'edit') {
                          _editProduct(product);
                        } else if (value == 'delete') {
                          _deleteProduct(product);
                        }
                      },
                    ),
                  ],
                ),
                onTap: () => _addToShoppingList(product),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProduct,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        child: const Icon(LucideIcons.plus),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}