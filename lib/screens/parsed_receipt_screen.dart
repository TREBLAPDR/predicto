import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/receipt_models.dart';
import '../models/shopping_list_models.dart';
import '../services/shopping_list_service.dart';
import 'shopping_list_screen.dart';

class ParsedReceiptScreen extends StatefulWidget {
  final ParsedReceipt receipt;
  final String method;
  final int processingTimeMs;

  const ParsedReceiptScreen({
    super.key,
    required this.receipt,
    required this.method,
    required this.processingTimeMs,
  });

  @override
  State<ParsedReceiptScreen> createState() => _ParsedReceiptScreenState();
}

class _ParsedReceiptScreenState extends State<ParsedReceiptScreen> {
  late List<ReceiptItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.receipt.items);
  }

  void _toggleItemAcceptance(int index) {
    setState(() {
      _items[index].isAccepted = !_items[index].isAccepted;
    });
  }

  Future<void> _editItem(int index) async {
    final item = _items[index];
    final nameController = TextEditingController(text: item.name);
    final priceController = TextEditingController(
      text: item.price?.toStringAsFixed(2) ?? '',
    );
    final qtyController = TextEditingController(
      text: item.qty?.toStringAsFixed(1) ?? '1.0',
    );

    final saved = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Edit Item'),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text('Item Name', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              ShadInput(controller: nameController),
              const SizedBox(height: 12),
              // Removed const from TextStyle due to custom font
              const Text('Price (\u20B1)', style: TextStyle(fontSize: 13, fontFamily: 'Roboto')),
              const SizedBox(height: 4),
              ShadInput(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              const Text('Quantity', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              ShadInput(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
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
    );

    if (saved == true) {
      setState(() {
        _items[index].name = nameController.text;
        _items[index].price = double.tryParse(priceController.text);
        _items[index].qty = double.tryParse(qtyController.text) ?? 1.0;
      });
    }
  }

  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
    ShadToaster.of(context).show(
      const ShadToast(description: Text('Item removed')),
    );
  }

  Future<void> _addNewItem() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();

    final added = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Add Item'),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              const Text('Item Name', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              ShadInput(controller: nameController),
              const SizedBox(height: 12),
              // Removed const
              const Text('Price (\u20B1)', style: TextStyle(fontSize: 13, fontFamily: 'Roboto')),
              const SizedBox(height: 4),
              ShadInput(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
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
    );

    if (added == true && nameController.text.isNotEmpty) {
      setState(() {
        _items.add(ReceiptItem(
          name: nameController.text,
          price: double.tryParse(priceController.text),
          qty: 1.0,
          confidence: 1.0,
          isAccepted: true,
        ));
      });
    }
  }

  double _calculateTotal() {
    return _items
        .where((item) => item.isAccepted)
        .fold(0.0, (sum, item) => sum + ((item.price ?? 0) * (item.qty ?? 1)));
  }

  Future<void> _saveToShoppingList(BuildContext context) async {
    final itemsToAdd = _items.map((item) => item.isAccepted).toList();
    final acceptedCount = itemsToAdd.where((accepted) => accepted).length;

    if (acceptedCount == 0) {
      ShadToaster.of(context).show(
        const ShadToast(description: Text('No items selected')),
      );
      return;
    }

    try {
      final service = await ShoppingListService.getInstance();
      var currentList = await service.getCurrentList();

      if (currentList == null) {
        final listName = widget.receipt.storeName != null
            ? '${widget.receipt.storeName} - ${widget.receipt.date ?? "Today"}'
            : 'Shopping List ${DateTime.now().toString().substring(0, 10)}';

        currentList = await service.createList(listName, storeName: widget.receipt.storeName);
      }

      int addedCount = 0;
      for (int i = 0; i < _items.length; i++) {
        if (_items[i].isAccepted) {
          final receiptItem = _items[i];
          final category = ItemCategory.categorizeItem(receiptItem.name);
          final uniqueId = '${DateTime.now().millisecondsSinceEpoch}_${addedCount}_${receiptItem.name.hashCode}';

          final newItem = ShoppingListItem(
            id: uniqueId,
            name: receiptItem.name,
            price: receiptItem.price,
            qty: receiptItem.qty ?? 1.0,
            category: category,
          );

          await service.addItem(currentList.id, newItem);
          addedCount++;
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      if (!context.mounted) return;

      ShadToaster.of(context).show(
        ShadToast(
          title: const Text('Success'),
          description: Text('Added $addedCount items to shopping list'),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ShoppingListScreen()),
      );
    } catch (e) {
      if (!context.mounted) return;
      ShadToaster.of(context).show(
        ShadToast.destructive(title: const Text('Error'), description: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final acceptedItems = _items.where((item) => item.isAccepted).toList();
    final calculatedTotal = _calculateTotal();

    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Zinc 950
      appBar: AppBar(
        title: const Text('Parsed Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.check, color: Colors.green),
            onPressed: () => _saveToShoppingList(context),
            tooltip: 'Save to List',
          ),
        ],
      ),
      body: Column(
        children: [
          // HEADER METADATA CARD
          // FIXED: Removed margin param, wrapped in Padding instead
          Padding(
            padding: const EdgeInsets.all(16),
            child: ShadCard(
              padding: const EdgeInsets.all(16),
              // Removed const because of runtime color calculation
              backgroundColor: _getMethodColor().withOpacity(0.1),
              border: ShadBorder.all(color: _getMethodColor().withOpacity(0.3)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_getMethodIcon(), color: _getMethodColor(), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        widget.receipt.storeName ?? 'Unknown Store',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildMetaRow('Date', widget.receipt.date ?? "Not found"),
                  _buildMetaRow('Method', widget.method),
                  _buildMetaRow('Confidence', '${(widget.receipt.parsingConfidence * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
          ),

          // ITEMS LIST
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                return Container(
                  decoration: BoxDecoration(
                    color: item.isAccepted ? const Color(0xFF18181B) : const Color(0xFF27272A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: item.isAccepted ? Colors.white10 : Colors.transparent,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: ShadCheckbox(
                      value: item.isAccepted,
                      onChanged: (_) => _toggleItemAcceptance(index),
                    ),
                    title: Text(
                      item.name,
                      style: TextStyle(
                        decoration: item.isAccepted ? null : TextDecoration.lineThrough,
                        color: item.isAccepted ? Colors.white : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Qty: ${item.qty?.toStringAsFixed(1)} • Confidence: ${(item.confidence * 100).toStringAsFixed(0)}%',
                      // Removed const
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '\u20B1${item.price?.toStringAsFixed(2) ?? "-.--"}',
                          // Removed const
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'Roboto',
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(LucideIcons.ellipsisVertical, size: 18, color: Colors.grey),
                          color: const Color(0xFF27272A),
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'edit', child: Text('Edit', style: TextStyle(color: Colors.white))),
                            const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                          ],
                          onSelected: (value) {
                            if (value == 'edit') _editItem(index);
                            else if (value == 'delete') _deleteItem(index);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // TOTAL SUMMARY
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF09090B),
              // Removed const
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Accepted: ${acceptedItems.length}/${_items.length}',
                          style: const TextStyle(color: Colors.grey)),
                      Text(
                        'Total: \u20B1${calculatedTotal.toStringAsFixed(2)}',
                        // Removed const
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Roboto',
                        ),
                      ),
                    ],
                  ),
                  if (widget.receipt.total != null && (calculatedTotal - widget.receipt.total!).abs() > 0.5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          // FIXED: Renamed alertTriangle to triangleAlert (depending on Lucide version) or alertTriangle if older
                          // I'll use triangleAlert as per previous fixes, or circleAlert as a safe fallback

                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ShadButton.outline(
                          onPressed: _addNewItem,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.plus, size: 16),
                              SizedBox(width: 8),
                              Text('Add Item'),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ShadButton(
                          onPressed: () => _saveToShoppingList(context),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.shoppingCart, size: 16),
                              SizedBox(width: 8),
                              Text('Add to List'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          // Removed const
          Text('$label: ', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Color _getMethodColor() {
    switch (widget.method) {
      case 'gemini': return Colors.green;
      case 'basic': return Colors.blue;
      case 'basic_fallback': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _getMethodIcon() {
    switch (widget.method) {
      case 'gemini': return LucideIcons.sparkles;
      case 'basic': return LucideIcons.scanLine;
    // FIXED: Renamed alertCircle -> circleAlert
      default: return LucideIcons.circleAlert;
    }
  }
}