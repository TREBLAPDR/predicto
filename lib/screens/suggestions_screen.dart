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

class _SuggestionsScreenState extends State<SuggestionsScreen> with SingleTickerProviderStateMixin {
  late SuggestionService _suggestionService;
  List<ItemSuggestion> _standardSuggestions = [];
  List<ItemSuggestion> _aiSuggestions = [];

  bool _isLoadingStandard = true;
  bool _isLoadingAI = false;
  bool _aiLoaded = false;

  int _addedCount = 0;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    _suggestionService = await SuggestionService.getInstance();
    _loadStandardSuggestions();
  }

  Future<void> _loadStandardSuggestions() async {
    if (!mounted) return;
    setState(() => _isLoadingStandard = true);

    final results = await _suggestionService.generateSuggestions(
        currentList: widget.currentItems,
        maxSuggestions: 15
    );

    if (mounted) {
      setState(() {
        _standardSuggestions = results;
        _isLoadingStandard = false;
      });
    }
  }

  Future<void> _loadAISuggestions() async {
    if (_aiLoaded && _aiSuggestions.isNotEmpty) return;

    setState(() {
      _isLoadingAI = true;
    });

    try {
      final aiResults = await _suggestionService.getAISuggestions();
      if (mounted) {
        setState(() {
          _aiSuggestions = aiResults;
          _isLoadingAI = false;
          _aiLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAI = false);
        ShadToaster.of(context).show(
          ShadToast.destructive(title: const Text('AI Error'), description: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _addItem(ItemSuggestion suggestion, bool isAI) async {
    try {
      final listService = await ShoppingListService.getInstance();

      final newItem = ShoppingListItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: suggestion.itemName,
        price: suggestion.estimatedPrice,
        qty: 1.0,
        category: suggestion.category,
        notes: isAI ? "AI Suggested" : null,
      );

      await listService.addItem(widget.listId, newItem);

      setState(() {
        if (isAI) {
          _aiSuggestions.remove(suggestion);
        } else {
          _standardSuggestions.remove(suggestion);
        }
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
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        title: const Text('Suggestions', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF09090B),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context, _addedCount),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: "Standard"),
            Tab(text: "AI Insights ✨"),
          ],
          onTap: (index) {
            if (index == 1 && !_aiLoaded) {
              _loadAISuggestions();
            }
          },
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Standard Tab
          _buildSuggestionList(_standardSuggestions, _isLoadingStandard, false),

          // AI Tab
          _buildAITab(),
        ],
      ),
    );
  }

  Widget _buildAITab() {
    if (_isLoadingAI) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.purple),
            const SizedBox(height: 16),
            Text(
              "Consulting Gemini AI...",
              style: TextStyle(color: Colors.purple.shade200, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              "Analyzing purchase history patterns",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (!_aiLoaded && _aiSuggestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.sparkles, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text("Unlock AI Insights", style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Gemini can analyze your habits and seasonality to predict what you need next.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 24),
            ShadButton(
              onPressed: _loadAISuggestions,
              backgroundColor: Colors.purple,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.brainCircuit, size: 18),
                  SizedBox(width: 8),
                  Text("Generate Suggestions"),
                ],
              ),
            )
          ],
        ),
      );
    }

    return _buildSuggestionList(_aiSuggestions, false, true);
  }

  Widget _buildSuggestionList(List<ItemSuggestion> items, bool isLoading, bool isAI) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (items.isEmpty) {
      return const Center(
        child: Text("No suggestions found", style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return ShadCard(
          padding: const EdgeInsets.all(16),
          backgroundColor: const Color(0xFF18181B),
          border: isAI
              ? ShadBorder.all(color: Colors.purple.withOpacity(0.5), width: 1)
              : ShadBorder.all(color: Colors.white.withOpacity(0.1)),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isAI ? Colors.purple.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    isAI ? LucideIcons.sparkles : LucideIcons.history,
                    color: isAI ? Colors.purple : Colors.blue,
                    size: 20
                ),
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
                    if (isAI && item.confidence > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "Confidence: ${(item.confidence * 100).toStringAsFixed(0)}%",
                          style: TextStyle(color: Colors.purple.shade200, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: () => _addItem(item, isAI),
                child: const Icon(LucideIcons.plus, size: 16),
              ),
            ],
          ),
        );
      },
    );
  }
}