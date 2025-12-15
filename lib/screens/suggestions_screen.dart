import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/suggestion_models.dart';
import '../models/shopping_list_models.dart';
import '../services/suggestion_service.dart';
import '../services/shopping_list_service.dart';

class SuggestionsScreen extends StatefulWidget {
  final String listId;
  final List<ShoppingListItem> currentItems;

  const SuggestionsScreen({
    super.key,
    required this.listId,
    required this.currentItems,
  });

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  List<ItemSuggestion> _suggestions = [];
  bool _isLoading = true;
  final Set<String> _selectedSuggestions = {};

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoading = true);

    try {
      final suggestionService = await SuggestionService.getInstance();
      final suggestions = await suggestionService.generateSuggestions(
        currentList: widget.currentItems,
        maxSuggestions: 10,
      );

      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Error'),
            description: Text('Failed to load suggestions: $e'),
          ),
        );
      }
    }
  }

  Future<void> _addSelectedToList() async {
    if (_selectedSuggestions.isEmpty) return;

    showShadDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final shoppingListService = await ShoppingListService.getInstance();
      var currentList = await shoppingListService.getListById(widget.listId);

      if (currentList == null) throw Exception('List not found');

      int addedCount = 0;
      for (final itemName in _selectedSuggestions) {
        final suggestion = _suggestions.firstWhere((s) => s.itemName == itemName);

        // Check for duplicates
        final existingItem = currentList.items.firstWhere(
              (item) => item.name.toLowerCase() == suggestion.itemName.toLowerCase(),
          orElse: () => ShoppingListItem(id: '', name: '', qty: 0, category: ''),
        );

        if (existingItem.id.isNotEmpty) continue;

        final newItem = ShoppingListItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_$addedCount',
          name: suggestion.itemName,
          price: suggestion.estimatedPrice,
          qty: 1.0,
          category: suggestion.category,
        );

        await shoppingListService.addItem(currentList.id, newItem);
        addedCount++;
        await Future.delayed(const Duration(milliseconds: 2));
      }

      if (!mounted) return;
      Navigator.pop(context);
      Navigator.pop(context, addedCount);

    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ShadToaster.of(context).show(
        ShadToast.destructive(
          title: const Text('Error'),
          description: Text('Failed to add items: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Zinc 950
      appBar: AppBar(
        title: const Text('AI Insights', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _suggestions.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: _suggestions.length,
            itemBuilder: (context, index) {
              return _buildSuggestionCard(_suggestions[index]);
            },
          ),

          // Floating Action Bar (Glassmorphism effect)
          if (_selectedSuggestions.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xFF09090B).withOpacity(1.0),
                      const Color(0xFF09090B).withOpacity(0.0),
                    ],
                  ),
                ),
                child: ShadButton(
                  size: ShadButtonSize.lg,
                  onPressed: _addSelectedToList,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.circlePlus, size: 20),
                      const SizedBox(width: 8),
                      Text('Add ${_selectedSuggestions.length} Items'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(ItemSuggestion suggestion) {
    final isSelected = _selectedSuggestions.contains(suggestion.itemName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedSuggestions.remove(suggestion.itemName);
            } else {
              _selectedSuggestions.add(suggestion.itemName);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF27272A) : const Color(0xFF18181B), // Zinc 800 vs 900
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.white24 : Colors.white10,
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selection Indicator
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    isSelected ? LucideIcons.circleCheck : LucideIcons.circle,
                    color: isSelected ? Colors.white : Colors.grey[700],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            suggestion.itemName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          // Price
                          if (suggestion.estimatedPrice != null)
                            Text(
                              '\u20B1${suggestion.estimatedPrice!.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontFamily: 'Roboto',
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4ADE80),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Reason & Match Score Row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                // UPDATED: Using Icon widget for LucideIcons
                                Icon(
                                    suggestion.reason.icon,
                                    size: 14,
                                    color: Colors.blue.shade300
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  suggestion.reason.displayText,
                                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(suggestion.confidence * 100).toInt()}% Match',
                            style: TextStyle(
                              fontSize: 12,
                              color: _getConfidenceColor(suggestion.confidence),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      if (suggestion.relatedItems.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Pairs with: ${suggestion.relatedItems.join(", ")}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.brainCircuit, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          const Text(
            'No Insights Yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan more receipts to unlock AI predictions.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return const Color(0xFF4ADE80); // Green 400
    if (confidence >= 0.6) return const Color(0xFFFACC15); // Yellow 400
    return const Color(0xFF94A3B8); // Slate 400
  }
}