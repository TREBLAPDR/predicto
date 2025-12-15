import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/shopping_list_models.dart';
import '../models/product_models.dart';
import '../widgets/product_picker_sheet.dart';
import '../services/shopping_list_service.dart';
import 'suggestions_screen.dart';
import '../services/suggestion_service.dart';
import 'share_list_screen.dart';
import '../services/sharing_service.dart';
import 'all_lists_screen.dart';

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> with TickerProviderStateMixin {
  late ShoppingListService _service;
  ShoppingList? _currentList;
  bool _isLoading = true;
  bool _groupByCategory = true;

  // Animation Controller for the shiny effect
  late AnimationController _shineController;

  @override
  void initState() {
    super.initState();
    _loadList();

    // Shine animation loop: Runs every 2.5 seconds
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(period: const Duration(seconds: 3));
  }

  @override
  void dispose() {
    _shineController.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    setState(() => _isLoading = true);
    _service = await ShoppingListService.getInstance();
    final list = await _service.getCurrentList();

    if (mounted) {
      setState(() {
        _currentList = list;
        _isLoading = false;
      });
    }
  }

  // --- HELPER: DUPLICATE DETECTION ---
  ShoppingListItem? _findDuplicateItem(String name, String category) {
    if (_currentList == null) return null;
    try {
      return _currentList!.items.firstWhere(
            (item) =>
        item.name.toLowerCase() == name.toLowerCase() &&
            item.category == category,
      );
    } catch (e) {
      return null;
    }
  }

  Future<String?> _showDuplicateDialog(ShoppingListItem existing,
      String newName, double newQty, double? newPrice) async {
    return showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('⚠️ Duplicate Item'),
        description: const Text('This item already exists in your list:'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF27272A), // Zinc 800
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(existing.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Current qty: ${existing.qty.toStringAsFixed(1)}',
                      style: const TextStyle(color: Colors.grey)),
                  if (existing.price != null)
                    Text('Price: \u20B1${existing.price!.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.grey, fontFamily: 'Roboto')),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('What would you like to do?',
                style: TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          ShadButton.outline(
            onPressed: () => Navigator.pop(context, 'merge'),
            child: const Text('Merge (Add Qty)'),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, 'replace'),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSuggestions() async {
    if (_currentList == null) return;
    final addedCount = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (context) => SuggestionsScreen(
          listId: _currentList!.id,
          currentItems: _currentList!.items,
        ),
      ),
    );

    if (addedCount != null && addedCount > 0) {
      await _loadList();
      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          title: const Text('Suggestions Added'),
          description: Text('Added $addedCount items from suggestions'),
        ),
      );
    }
  }

  // --- ADD FROM PRODUCTS ---
  Future<void> _addFromProducts() async {
    if (_currentList == null) return;

    final selected = await showModalBottomSheet<List<Product>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF09090B),
      builder: (context) => const ProductPickerSheet(),
    );

    if (selected != null && selected.isNotEmpty) {
      int addedCount = 0;
      for (final product in selected) {
        final duplicate = _findDuplicateItem(product.name, product.category);

        if (duplicate != null) {
          final action = await _showDuplicateDialog(
            duplicate,
            product.name,
            1.0,
            product.typicalPrice,
          );

          if (action == 'cancel') {
            continue;
          } else if (action == 'merge') {
            duplicate.qty += 1.0;
            if (product.typicalPrice != null) {
              duplicate.price = product.typicalPrice;
            }
            await _service.updateItem(_currentList!.id, duplicate);
            addedCount++;
          } else if (action == 'replace') {
            duplicate.qty = 1.0;
            duplicate.price = product.typicalPrice;
            await _service.updateItem(_currentList!.id, duplicate);
            addedCount++;
          }
        } else {
          final uniqueId =
              '${DateTime.now().microsecondsSinceEpoch}_${product.id}';

          final newItem = ShoppingListItem(
            id: uniqueId,
            name: product.name,
            price: product.typicalPrice,
            qty: 1.0,
            category: product.category,
          );

          await _service.addItem(_currentList!.id, newItem);
          addedCount++;
        }

        await Future.delayed(const Duration(milliseconds: 2));
      }

      await _loadList();

      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          title: const Text('Items Added'),
          description: Text('Processed ${selected.length} items'),
        ),
      );
    }
  }

  Future<void> _completeListAndRecordHistory() async {
    if (_currentList == null) return;

    final confirm = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Complete Shopping?'),
        description: const Text(
            'This will mark the list as complete and save it to history for future suggestions.'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final suggestionService = await SuggestionService.getInstance();
    await suggestionService.recordPurchases(_currentList!.items);
    await _service.completeList(_currentList!.id);

    if (!mounted) return;

    ShadToaster.of(context).show(
      const ShadToast(
        title: Text('Shopping Completed!'),
        description: Text('List moved to history.'),
      ),
    );
    await _loadList();
  }

  Future<void> _createNewList() async {
    DateTime? selectedDate = DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      helpText: 'When will you shop?',
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.white,
              onPrimary: Colors.black,
              surface: Color(0xFF18181B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      selectedDate = pickedDate;
    }

    final suggestedName = ShoppingListService.predictListName(selectedDate);
    final nameController = TextEditingController(text: suggestedName);

    if (!mounted) return;

    final created = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('New Shopping List'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text('List Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ShadInput(
              controller: nameController,
              placeholder: const Text('e.g., Weekly Groceries'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(LucideIcons.calendar, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Date: ${selectedDate?.year}-${selectedDate?.month.toString().padLeft(2, '0')}-${selectedDate?.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created == true && nameController.text.isNotEmpty) {
      final newList = await _service.createList(
        nameController.text,
        targetDate: selectedDate,
      );
      setState(() => _currentList = newList);
    }
  }

  // --- ADD ITEM ---
  Future<void> _addItem() async {
    if (_currentList == null) return;

    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    String selectedCategory = ItemCategory.other;

    final added = await showShadDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ShadDialog(
          title: const Text('Add Item'),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text('Item Name', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ShadInput(
                    controller: nameController,
                    placeholder: const Text('Enter item name'),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Price (\u20B1)', style: TextStyle(fontSize: 13, fontFamily: 'Roboto')),
                            const SizedBox(height: 4),
                            ShadInput(
                              controller: priceController,
                              placeholder: const Text('0.00'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Quantity', style: TextStyle(fontSize: 13)),
                            const SizedBox(height: 4),
                            ShadInput(
                              controller: qtyController,
                              placeholder: const Text('1'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  const Text('Category', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ShadSelect<String>(
                    placeholder: const Text('Select Category'),
                    options: ItemCategory.all.map((cat) =>
                        ShadOption(value: cat, child: Text(cat))
                    ).toList(),
                    initialValue: selectedCategory,
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

    if (added == true && nameController.text.isNotEmpty) {
      final name = nameController.text.trim();
      final qty = double.tryParse(qtyController.text) ?? 1.0;
      final price = double.tryParse(priceController.text);

      final duplicate = _findDuplicateItem(name, selectedCategory);

      if (duplicate != null) {
        final action = await _showDuplicateDialog(duplicate, name, qty, price);

        if (action == 'cancel') {
          return;
        } else if (action == 'merge') {
          duplicate.qty += qty;
          if (price != null) {
            duplicate.price = price;
          }
          await _service.updateItem(_currentList!.id, duplicate);

          if (!mounted) return;
          ShadToaster.of(context).show(
            ShadToast(
              title: const Text('Item Merged'),
              description: Text('Updated ${duplicate.name} qty to ${duplicate.qty.toStringAsFixed(1)}'),
            ),
          );
        } else if (action == 'replace') {
          duplicate.qty = qty;
          duplicate.price = price;
          await _service.updateItem(_currentList!.id, duplicate);

          if (!mounted) return;
          ShadToaster.of(context).show(
            ShadToast(
              title: const Text('Item Replaced'),
              description: Text('Updated ${duplicate.name}'),
            ),
          );
        }
      } else {
        final newItem = ShoppingListItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          price: price,
          qty: qty,
          category: selectedCategory,
        );

        await _service.addItem(_currentList!.id, newItem);
      }
      await _loadList();
    }
  }

  Future<void> _togglePurchased(ShoppingListItem item) async {
    if (_currentList != null) {
      await _service.toggleItemPurchased(_currentList!.id, item.id);
      await _loadList();
    }
  }

  Future<void> _deleteItem(ShoppingListItem item) async {
    if (_currentList != null) {
      await _service.deleteItem(_currentList!.id, item.id);
      await _loadList();

      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          description: Text('${item.name} removed'),
        ),
      );
    }
  }

  Future<void> _editItem(ShoppingListItem item) async {
    if (_currentList == null) return;
    final nameController = TextEditingController(text: item.name);
    final priceController = TextEditingController(text: item.price?.toStringAsFixed(2) ?? '');
    final qtyController = TextEditingController(text: item.qty.toStringAsFixed(1));
    final notesController = TextEditingController(text: item.notes ?? '');
    String selectedCategory = item.category;

    final saved = await showShadDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ShadDialog(
          title: const Text('Edit Item'),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text('Name', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ShadInput(controller: nameController),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Price (\u20B1)', style: TextStyle(fontSize: 13, fontFamily: 'Roboto')),
                            const SizedBox(height: 4),
                            ShadInput(controller: priceController, keyboardType: TextInputType.number),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Quantity', style: TextStyle(fontSize: 13)),
                            const SizedBox(height: 4),
                            ShadInput(controller: qtyController, keyboardType: TextInputType.number),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Text('Category', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ShadSelect<String>(
                    initialValue: selectedCategory,
                    options: ItemCategory.all.map((cat) => ShadOption(value: cat, child: Text(cat))).toList(),
                    onChanged: (val) => setDialogState(() => selectedCategory = val!),
                    selectedOptionBuilder: (ctx, val) => Text(val),
                  ),

                  const SizedBox(height: 12),
                  const Text('Notes', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  ShadInput(controller: notesController, placeholder: const Text('Add optional notes...')),
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

    if (saved == true && nameController.text.isNotEmpty) {
      item.name = nameController.text.trim();
      item.price = double.tryParse(priceController.text);
      item.qty = double.tryParse(qtyController.text) ?? 1.0;
      item.category = selectedCategory;
      item.notes = notesController.text.isEmpty ? null : notesController.text;

      await _service.updateItem(_currentList!.id, item);
      await _loadList();

      if (!mounted) return;
      ShadToaster.of(context).show(const ShadToast(description: Text('Item updated')));
    }
  }

  Future<void> _confirmDeleteItem(ShoppingListItem item) async {
    final confirm = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Delete Item?'),
        description: Text('Remove "${item.name}" from your list?'),
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
      await _deleteItem(item);
    }
  }

  Future<void> _incrementQuantity(ShoppingListItem item) async {
    if (_currentList == null) return;
    item.qty += 1.0;
    await _service.updateItem(_currentList!.id, item);
    await _loadList();
  }

  Future<void> _decrementQuantity(ShoppingListItem item) async {
    if (_currentList == null) return;
    if (item.qty > 1.0) {
      item.qty -= 1.0;
      await _service.updateItem(_currentList!.id, item);
      await _loadList();
    } else {
      await _confirmDeleteItem(item);
    }
  }

  Future<void> _shareList() async {
    if (_currentList == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShareListScreen(list: _currentList!),
      ),
    );
  }

  Future<void> _accessSharedList() async {
    final codeController = TextEditingController();
    final shareCode = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Access Shared List'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            const Text('Enter the share code you received:', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ShadInput(
              controller: codeController,
              placeholder: const Text('e.g., ABC123XYZ'),
            ),
          ],
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, codeController.text),
            child: const Text('Access'),
          ),
        ],
      ),
    );

    if (shareCode == null || shareCode.isEmpty) return;

    if (!mounted) return;
    showShadDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final sharingService = await SharingService.getInstance();
      final sharedList = await sharingService.accessSharedList(shareCode.trim());

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      showShadDialog(
        context: context,
        builder: (context) => ShadDialog.alert(
          title: Text(sharedList.name),
          description: Text('${sharedList.items.length} items found.'),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ShadButton(
              onPressed: () {
                Navigator.pop(context);
                _copyItemsFromSharedList(sharedList);
              },
              child: const Text('Copy to My List'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ShadToaster.of(context).show(
        ShadToast.destructive(title: const Text('Error'), description: Text(e.toString())),
      );
    }
  }

  Future<void> _copyItemsFromSharedList(ShoppingList sharedList) async {
    var currentList = _currentList;

    if (currentList == null) {
      currentList = await _service.createList('My Shopping List');
    }
    for (final item in sharedList.items) {
      final newItem = ShoppingListItem(
        id: '${DateTime.now().millisecondsSinceEpoch}_${item.name.hashCode}',
        name: item.name,
        price: item.price,
        qty: item.qty,
        category: item.category,
        isPurchased: false,
      );
      await _service.addItem(currentList.id, newItem);
    }
    await _loadList();
    if (!mounted) return;
    ShadToaster.of(context).show(
      ShadToast(title: const Text('Success'), description: Text('Copied ${sharedList.items.length} items')),
    );
  }

  Future<void> _saveListAs() async {
    if (_currentList == null) return;
    final controller = TextEditingController(text: '${_currentList!.name} (Copy)');

    final newName = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Save List As'),
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ShadInput(
            controller: controller,
            placeholder: const Text('e.g., Weekly Groceries'),
          ),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      final newList = await _service.createList(newName);
      for (final item in _currentList!.items) {
        await _service.addItem(
            newList.id,
            ShoppingListItem(
              id: '${DateTime.now().millisecondsSinceEpoch}_${item.id}',
              name: item.name,
              price: item.price,
              qty: item.qty,
              category: item.category,
              isPurchased: false,
            ));
      }
      if (!mounted) return;
      ShadToaster.of(context).show(ShadToast(description: Text('Saved as "$newName"')));
    }
  }

  Future<void> _renameCurrentList() async {
    if (_currentList == null) return;
    final controller = TextEditingController(text: _currentList!.name);

    final newName = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Rename List'),
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ShadInput(controller: controller),
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await _service.renameList(_currentList!.id, newName);
      await _loadList();
    }
  }

  Future<void> _deleteCurrentList() async {
    if (_currentList == null) return;
    final confirm = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Delete List?'),
        description: const Text('This action cannot be undone.'),
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
      await _service.deleteList(_currentList!.id);
      await _loadList();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF09090B),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentList == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF09090B),
        appBar: AppBar(
          title: const Text('Shopping List'),
          backgroundColor: const Color(0xFF09090B),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.shoppingCart, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('No shopping list yet', style: TextStyle(fontSize: 18, color: Colors.white)),
              const SizedBox(height: 24),
              ShadButton(
                onPressed: _createNewList,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.plus, size: 16),
                    SizedBox(width: 8),
                    Text('Create List'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _service.getListStatistics(_currentList!);
    final categorized = _service.getItemsByCategory(_currentList!);
    final double progress = stats['completionPercent'] / 100.0;

    // GOLD LOGIC
    final bool isComplete = progress >= 1.0;
    // White by default, Gold if complete
    final Color goldColor = const Color(0xFFFFD700);
    final Color statsColor = isComplete ? goldColor : Colors.white;

    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        title: Text(_currentList!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(LucideIcons.folderOpen, color: Colors.white70),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AllListsScreen()),
              );
              await _loadList();
            },
          ),
          IconButton(
            icon: Icon(LucideIcons.lightbulb, color: Colors.yellow),
            onPressed: _openSuggestions,
          ),

          PopupMenuButton<String>(
            icon: Icon(LucideIcons.ellipsisVertical, color: Colors.white70),
            color: const Color(0xFF18181B),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'save', child: Text('Save List As...', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'share', child: Text('Share List', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'access', child: Text('Access Shared List', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'new', child: Text('New List', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'rename', child: Text('Rename List', style: TextStyle(color: Colors.white))),
              const PopupMenuItem(value: 'delete', child: Text('Delete List', style: TextStyle(color: Colors.red))),
            ],
            onSelected: (value) async {
              if (value == 'save') await _saveListAs();
              else if (value == 'share') await _shareList();
              else if (value == 'access') await _accessSharedList();
              else if (value == 'new') await _createNewList();
              else if (value == 'rename') await _renameCurrentList();
              else if (value == 'delete') await _deleteCurrentList();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // STATISTICS CARD
          ShadCard(
            radius: BorderRadius.zero,
            backgroundColor: const Color(0xFF09090B),
            border: const ShadBorder(bottom: ShadBorderSide(color: Colors.white10)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Applied dynamic Gold color here
                    _buildStat('Items', '${stats['purchasedItems']}/${stats['totalItems']}', color: statsColor),
                    _buildStat('Total', '\u20B1${stats['totalCost'].toStringAsFixed(2)}', color: statsColor),
                    _buildStat('Progress', '${stats['completionPercent'].toStringAsFixed(0)}%', color: statsColor),
                  ],
                ),
                const SizedBox(height: 12),

                // --- ANIMATED PROGRESS BAR (GOLD) ---
                LayoutBuilder(
                  builder: (context, constraints) {
                    final maxWidth = constraints.maxWidth;

                    return Stack(
                      children: [
                        Container(
                          height: 8,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),

                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: progress),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Container(
                              height: 8,
                              width: maxWidth * value,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isComplete
                                      ? [const Color(0xFFFFD700), const Color(0xFFFFB300)] // Gold
                                      : [const Color(0xFF22C55E), const Color(0xFF4ADE80)], // Green
                                ),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isComplete ? const Color(0xFFFFD700) : const Color(0xFF22C55E)).withOpacity(0.4),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: AnimatedBuilder(
                                  animation: _shineController,
                                  builder: (context, child) {
                                    return FractionallySizedBox(
                                      widthFactor: 1.0,
                                      child: Transform.translate(
                                        offset: Offset(
                                            -maxWidth * value + (_shineController.value * (maxWidth * value * 3)),
                                            0
                                        ),
                                        child: Container(
                                          width: 40,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                Colors.white.withOpacity(0.7),
                                                Colors.transparent,
                                              ],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                          ),
                                          transform: Matrix4.skewX(-0.3),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),

          // ITEMS LIST
          Expanded(
            child: _currentList!.items.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.shoppingCart, size: 64, color: Colors.grey.shade800),
                  const SizedBox(height: 16),
                  Text('List is empty', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            )
                : _groupByCategory
                ? _buildCategorizedList(categorized)
                : _buildSimpleList(),
          ),

          // BOTTOM ACTIONS
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF09090B),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ShadButton.outline(
                          onPressed: _addItem,
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
                        child: ShadButton.secondary(
                          onPressed: _addFromProducts,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.package, size: 16),
                              SizedBox(width: 8),
                              Text('Products'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // --- SHINING COMPLETE BUTTON (GOLD) ---
                  LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            ShadButton(
                              width: double.infinity,
                              // Dynamic background color: Gold if complete, Green if not
                              backgroundColor: isComplete ? goldColor : Colors.green,
                              onPressed: _completeListAndRecordHistory,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Dark icons/text on Gold for contrast
                                  Icon(LucideIcons.circleCheck, size: 18, color: isComplete ? Colors.black : Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                      'Complete Shopping',
                                      style: TextStyle(
                                          color: isComplete ? Colors.black : Colors.white,
                                          fontWeight: FontWeight.bold
                                      )
                                  ),
                                ],
                              ),
                            ),

                            // Shine Effect for Button (Only if complete)
                            if (isComplete)
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6), // Match standard button radius
                                  child: AnimatedBuilder(
                                    animation: _shineController,
                                    builder: (context, child) {
                                      return Transform.translate(
                                        offset: Offset(
                                            -constraints.maxWidth + (_shineController.value * (constraints.maxWidth * 3)),
                                            0
                                        ),
                                        child: Container(
                                          width: 50,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.transparent,
                                                Colors.white.withOpacity(0.5),
                                                Colors.transparent,
                                              ],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                          ),
                                          transform: Matrix4.skewX(-0.3),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                          ],
                        );
                      }
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, {Color color = Colors.white}) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color, fontFamily: 'Roboto')),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildCategorizedList(Map<String, List<ShoppingListItem>> categorized) {
    final sortedCategories = categorized.keys.toList()..sort();

    return ListView.builder(
      itemCount: sortedCategories.length,
      padding: const EdgeInsets.only(bottom: 20),
      itemBuilder: (context, index) {
        final category = sortedCategories[index];
        final items = categorized[category]!;

        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(category, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text('${items.length} items', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            initiallyExpanded: true,
            iconColor: Colors.white70,
            collapsedIconColor: Colors.white30,
            children: items.map((item) => _buildItemTile(item)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildSimpleList() {
    return ListView.builder(
      itemCount: _currentList!.items.length,
      padding: const EdgeInsets.only(bottom: 20),
      itemBuilder: (context, index) => _buildItemTile(_currentList!.items[index]),
    );
  }

  Widget _buildItemTile(ShoppingListItem item) {
    return Dismissible(
      key: Key(item.id),
      background: Container(
        color: Colors.red.withOpacity(0.8),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        final confirm = await showShadDialog<bool>(
          context: context,
          builder: (context) => ShadDialog.alert(
            title: const Text('Remove Item?'),
            description: Text('Remove "${item.name}"?'),
            actions: [
              ShadButton.outline(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ShadButton.destructive(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
            ],
          ),
        );
        return confirm;
      },
      onDismissed: (_) => _deleteItem(item),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF18181B), // Zinc 900
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: ShadCheckbox(
            value: item.isPurchased,
            onChanged: (_) => _togglePurchased(item),
          ),
          title: Text(
            item.name,
            style: TextStyle(
              decoration: item.isPurchased ? TextDecoration.lineThrough : null,
              color: item.isPurchased ? Colors.grey : Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: item.price != null
              ? Text('\u20B1${item.price!.toStringAsFixed(2)} each', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontFamily: 'Roboto'))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => _decrementQuantity(item),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Icon(LucideIcons.minus, size: 14, color: Colors.white70),
                      ),
                    ),
                    Text(
                      item.qty.toStringAsFixed(item.qty == item.qty.toInt() ? 0 : 1),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                    ),
                    InkWell(
                      onTap: () => _incrementQuantity(item),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Icon(LucideIcons.plus, size: 14, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              PopupMenuButton<String>(
                icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: Colors.grey),
                color: const Color(0xFF27272A),
                itemBuilder: (context) => [
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
                  if (value == 'edit') _editItem(item);
                  else if (value == 'delete') _confirmDeleteItem(item);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}