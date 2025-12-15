import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/shopping_list_models.dart';
import '../services/shopping_list_service.dart';
import 'shopping_list_screen.dart';

class AllListsScreen extends StatefulWidget {
  const AllListsScreen({super.key});

  @override
  State<AllListsScreen> createState() => _AllListsScreenState();
}

class _AllListsScreenState extends State<AllListsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late ShoppingListService _service;
  List<ShoppingList> _activeLists = [];
  List<ShoppingList> _historyLists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLists();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    setState(() => _isLoading = true);

    _service = await ShoppingListService.getInstance();
    final active = await _service.getActiveLists();
    final history = await _service.getHistoryLists();

    if (mounted) {
      setState(() {
        _activeLists = active;
        _historyLists = history;
        _isLoading = false;
      });
    }
  }

  Future<void> _openList(ShoppingList list) async {
    await _service.setCurrentList(list.id);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const ShoppingListScreen()),
    );
  }

  Future<void> _renameList(ShoppingList list) async {
    final controller = TextEditingController(text: list.name);

    final newName = await showShadDialog<String>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Rename List'),
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: ShadInput(
            controller: controller,
            placeholder: const Text('Enter list name'),
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
      await _service.renameList(list.id, newName);
      await _loadLists();
    }
  }

  Future<void> _deleteList(ShoppingList list) async {
    final confirm = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Delete List?'),
        description: Text('Delete "${list.name}"? This cannot be undone.'),
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
      await _service.deleteList(list.id);
      await _loadLists();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Zinc 950
      appBar: AppBar(
        title: const Text('My Lists', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          dividerColor: Colors.white10,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.list, size: 16),
                  const SizedBox(width: 8),
                  Text('Active (${_activeLists.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.history, size: 16),
                  const SizedBox(width: 8),
                  Text('History (${_historyLists.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _buildActiveTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildActiveTab() {
    if (_activeLists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Removed const due to shade800
            Icon(LucideIcons.shoppingCart, size: 64, color: Colors.grey.shade800),
            const SizedBox(height: 16),
            // Removed const due to shade400
            Text('No active lists', style: TextStyle(fontSize: 18, color: Colors.grey.shade400)),
            const SizedBox(height: 24),
            ShadButton.outline(
              onPressed: () => Navigator.pop(context),
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
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _activeLists.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final list = _activeLists[index];
        final stats = _service.getListStatistics(list);

        return GestureDetector(
          onTap: () => _openList(list),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B), // Zinc 900
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                // Icon Box
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    // Removed const due to withOpacity
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${list.items.length}',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        list.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // FIXED: Use squareCheck instead of checkSquare
                          Icon(LucideIcons.squareCheck, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            '${stats['purchasedItems']}/${stats['totalItems']} checked',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                          const SizedBox(width: 12),
                          // Removed const from Icon
                          Icon(LucideIcons.clock, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(list.updatedAt),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Menu
                PopupMenuButton<String>(
                  icon: const Icon(LucideIcons.ellipsisVertical, color: Colors.grey),
                  color: const Color(0xFF27272A),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(LucideIcons.folderOpen, size: 16, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Open', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(LucideIcons.pencil, size: 16, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Rename', style: TextStyle(color: Colors.white)),
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
                    if (value == 'open') _openList(list);
                    else if (value == 'rename') _renameList(list);
                    else if (value == 'delete') _deleteList(list);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    if (_historyLists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Removed const due to shade800
            Icon(LucideIcons.history, size: 64, color: Colors.grey.shade800),
            const SizedBox(height: 16),
            // Removed const due to shade400
            Text('No history yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade400)),
            const SizedBox(height: 8),
            // Removed const due to shade600
            Text(
              'Completed lists will appear here',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _historyLists.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final list = _historyLists[index];
        final stats = _service.getListStatistics(list);

        return GestureDetector(
          onTap: () => _showCompletedListDetails(list),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              // Removed const due to withOpacity
              color: const Color(0xFF18181B).withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                // Icon Box (Green for completed)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(LucideIcons.check, color: Colors.green),
                  ),
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        list.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white70,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${list.items.length} items • \u20B1${stats['totalCost'].toStringAsFixed(2)}',
                            // Removed const due to shade600
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontFamily: 'Roboto'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Removed const due to shade700
                IconButton(
                  icon: Icon(LucideIcons.trash2, color: Colors.grey.shade700, size: 20),
                  onPressed: () => _deleteList(list),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCompletedListDetails(ShoppingList list) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF09090B),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  // Removed const due to shade800
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // FIXED: Use circleCheck instead of checkCircle
                  const Icon(LucideIcons.circleCheck, color: Colors.green, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          list.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          'Completed ${_formatDate(list.updatedAt)}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),

            // Items
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: list.items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = list.items[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181B),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        // FIXED: Use squareCheck instead of checkSquare
                        item.isPurchased ? LucideIcons.squareCheck : LucideIcons.square,
                        color: item.isPurchased ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      title: Text(
                        item.name,
                        style: TextStyle(color: Colors.white70, decoration: item.isPurchased ? TextDecoration.lineThrough : null),
                      ),
                      subtitle: Text('Qty: ${item.qty.toStringAsFixed(1)}', style: const TextStyle(color: Colors.grey)),
                      trailing: item.price != null
                          ? Text(
                        '\u20B1${item.price!.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white, fontFamily: 'Roboto'),
                      )
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}