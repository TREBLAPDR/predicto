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
  late SuggestionService _suggestionService;
  List<ItemSuggestion> _suggestions = [];
  bool _isLoading = true;
  int _addedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _suggestionService = await SuggestionService.getInstance();
    _loadAISuggestions();
  }

  Future<void> _loadAISuggestions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final aiResults = await _suggestionService.getAISuggestions();
      if (mounted) {
        setState(() {
          _suggestions = aiResults;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Do not crash, just show empty or error in console
        print("AI Error: $e");
      }
    }
  }

  Future<void> _addItem(ItemSuggestion suggestion) async {
    try {
      final listService = await ShoppingListService.getInstance();

      final newItem = ShoppingListItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: suggestion.itemName,
        price: suggestion.estimatedPrice,
        qty: 1.0,
        category: suggestion.category,
        notes: "AI Suggested",
      );

      await listService.addItem(widget.listId, newItem);

      setState(() {
        _suggestions.remove(suggestion);
        _addedCount++;
      });

      if (!mounted) return;
      ShadToaster.of(context).show(
        ShadToast(
          title: const Text('Added'),
          description: Text('${suggestion.itemName} added to list'),
        ),
      );
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.sparkles, color: Colors.purple, size: 20),
            SizedBox(width: 8),
            Text('AI Insights', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        backgroundColor: const Color(0xFF09090B),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context, _addedCount),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: _loadAISuggestions,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : _suggestions.isEmpty
          ? _buildEmptyState()
          : _buildList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.brainCircuit, size: 64, color: Colors.grey.shade800),
          const SizedBox(height: 16),
          const Text("No Insights Yet", style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 8),
          const Text("Try adding items to your history first.", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ShadButton.outline(onPressed: _loadAISuggestions, child: const Text("Retry"))
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _suggestions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _suggestions[index];
        return ShadCard(
          padding: const EdgeInsets.all(16),
          backgroundColor: const Color(0xFF18181B),
          border: ShadBorder.all(color: Colors.purple.withOpacity(0.4), width: 1),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(LucideIcons.lightbulb, color: Colors.purple, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(item.reason, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ),
              ),
              ShadButton(
                size: ShadButtonSize.sm,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                onPressed: () => _addItem(item),
                child: const Icon(LucideIcons.plus, size: 18),
              ),
            ],
          ),
        );
      },
    );
  }
}