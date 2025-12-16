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
    // Initialize service and load AI suggestions immediately
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
        // Log error but show empty state UI instead of crashing
        print("AI Load Error: $e");
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
      // Handle error silently or show toast
      print("Error adding item: $e");
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
            Text(
                'AI Insights',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF09090B),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context, _addedCount),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: _loadAISuggestions,
            tooltip: 'Refresh Predictions',
          )
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    // 1. Loading State
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.purple),
            const SizedBox(height: 24),
            Text(
              "Consulting Gemini AI...",
              style: TextStyle(color: Colors.purple.shade200, fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              "Analyzing your purchase patterns",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // 2. Empty State
    if (_suggestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.brainCircuit, size: 48, color: Colors.purple),
              ),
              const SizedBox(height: 24),
              const Text(
                "No Insights Yet",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                "Gemini needs more purchase history to make predictions. Try scanning more receipts or checking off items!",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 32),
              ShadButton.outline(
                onPressed: _loadAISuggestions,
                child: const Text("Try Again"),
              )
            ],
          ),
        ),
      );
    }

    // 3. List of Suggestions
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
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.lightbulb, color: Colors.purple, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.category,
                            style: TextStyle(color: Colors.grey.shade300, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (item.confidence > 0)
                          Text(
                            "${(item.confidence * 100).toInt()}% Match",
                            style: TextStyle(color: Colors.purple.shade200, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
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