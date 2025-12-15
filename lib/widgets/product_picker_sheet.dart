import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/product_models.dart';
import '../services/product_service.dart';

class ProductPickerSheet extends StatefulWidget {
  const ProductPickerSheet({super.key});

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  late ProductService _productService;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  final Set<String> _selectedIds = {};
  bool _isLoading = true;
  String _searchQuery = '';
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
      final products = await _productService.getProducts(limit: 100);

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

  void _toggleSelection(Product product) {
    setState(() {
      if (_selectedIds.contains(product.id)) {
        _selectedIds.remove(product.id);
      } else {
        _selectedIds.add(product.id);
      }
    });
  }

  void _confirmSelection() {
    final selected = _products
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    Navigator.pop(context, selected);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF09090B), // Zinc 950
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // DRAG HANDLE
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(LucideIcons.package, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Select Products',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  if (_selectedIds.isNotEmpty)
                    ShadBadge(
                      child: Text('${_selectedIds.length}'),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Colors.white10),

            // SEARCH BAR
            Padding(
              padding: const EdgeInsets.all(16),
              child: ShadInput(
                controller: _searchController,
                placeholder: const Text('Search products...'),
                leading: const Padding(
                  padding: EdgeInsets.only(right: 8.0),
                  child: Icon(LucideIcons.search, size: 16, color: Colors.grey),
                ),
                onChanged: _filterProducts,
              ),
            ),

            // LIST
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredProducts.isEmpty
                  ? Center(
                child: Text(
                  'No products found',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
                  : ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filteredProducts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final product = _filteredProducts[index];
                  final isSelected = _selectedIds.contains(product.id);

                  return GestureDetector(
                    onTap: () => _toggleSelection(product),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF27272A) : const Color(0xFF18181B), // Zinc 800/900
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Colors.blue.withOpacity(0.5) : Colors.white10,
                        ),
                      ),
                      child: Row(
                        children: [
                          ShadCheckbox(
                            value: isSelected,
                            onChanged: (_) => _toggleSelection(product),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      product.category,
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                    ),
                                    if (product.typicalPrice != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '•  \u20B1${product.typicalPrice!.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade400,
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (product.isPredictedNeeded())
                            const Tooltip(
                              message: "Recommended",
                              child: Icon(LucideIcons.sparkles, size: 16, color: Colors.amber),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // BOTTOM ACTION BAR
            if (_selectedIds.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF09090B),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: SafeArea(
                  child: ShadButton(
                    width: double.infinity,
                    size: ShadButtonSize.lg,
                    onPressed: _confirmSelection,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.shoppingCart, size: 18),
                        const SizedBox(width: 8),
                        Text('Add ${_selectedIds.length} Items to List'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}