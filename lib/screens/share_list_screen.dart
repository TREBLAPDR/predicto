import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/shopping_list_models.dart';
import '../models/shared_list_models.dart';
import '../services/sharing_service.dart';

class ShareListScreen extends StatefulWidget {
  final ShoppingList list;

  const ShareListScreen({super.key, required this.list});

  @override
  State<ShareListScreen> createState() => _ShareListScreenState();
}

class _ShareListScreenState extends State<ShareListScreen> {
  SharedListInfo? _shareInfo;
  bool _isLoading = false;
  int _daysValid = 7;

  Future<void> _createShareLink() async {
    setState(() => _isLoading = true);

    try {
      final sharingService = await SharingService.getInstance();
      final shareInfo = await sharingService.createShareLink(
        list: widget.list,
        permission: SharePermission.edit, // Default permission
        daysValid: _daysValid,
      );

      if (mounted) {
        setState(() {
          _shareInfo = shareInfo;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Error'),
            description: Text('Failed to create share link: $e'),
          ),
        );
      }
    }
  }

  void _copyShareCode() {
    if (_shareInfo == null) return;

    Clipboard.setData(ClipboardData(text: _shareInfo!.shareId));
    ShadToaster.of(context).show(
      const ShadToast(
        title: Text('Copied!'),
        description: Text('Share code copied to clipboard.'),
      ),
    );
  }

  void _shareViaText() {
    if (_shareInfo == null) return;

    const String bridgeUrl = 'https://TREBLAPDR.github.io/link';
    final String httpsLink = '$bridgeUrl/?id=${_shareInfo!.shareId}';

    final message = '''
Hey! I'm sharing my shopping list "${widget.list.name}" with you.

Tap here to join instantly:
$httpsLink

Or enter Share Code manually: ${_shareInfo!.shareId}

Valid until: ${_shareInfo!.expiresAt.toString().substring(0, 16)}
    ''';

    Clipboard.setData(ClipboardData(text: message));
    ShadToaster.of(context).show(
      const ShadToast(
        title: Text('Message Copied'),
        description: Text('Link copied! Paste it in Messenger/SMS.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Zinc 950
      appBar: AppBar(
        title: const Text('Share List', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER CARD
            ShadCard(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              backgroundColor: const Color(0xFF18181B), // Zinc 900
              // FIXED: Use ShadBorder instead of Border
              border: ShadBorder.all(color: Colors.white10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(LucideIcons.shoppingBag, size: 24, color: Colors.blue),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.list.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${widget.list.items.length} items',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            if (_shareInfo == null) ...[
              // --- SETUP SECTION ---
              const Text('Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),

              const Text('Valid For', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              ShadSelect<int>(
                placeholder: const Text('Select Duration'),
                initialValue: _daysValid,
                options: [1, 3, 7, 14, 30].map((days) {
                  return ShadOption(
                    value: days,
                    child: Text('$days ${days == 1 ? 'day' : 'days'}'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _daysValid = value);
                },
                selectedOptionBuilder: (context, value) => Text('$value ${value == 1 ? 'day' : 'days'}'),
              ),

              const SizedBox(height: 32),

              ShadButton(
                width: double.infinity,
                size: ShadButtonSize.lg,
                onPressed: _isLoading ? null : _createShareLink,
                // FIXED: Removed 'icon' param, used child Row
                child: _isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.share2, size: 18),
                    SizedBox(width: 8),
                    Text('Create Share Link'),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Info Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.info, color: Colors.blue, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Anyone with the link can view and edit this list. You can revoke access later.',
                        style: TextStyle(fontSize: 13, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),

            ] else ...[
              // --- RESULT SECTION ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withOpacity(0.1), // Green tint
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    // Fixed icon name from circleCheck -> checkCircle if needed, or stick to circleCheck
                    const Icon(LucideIcons.circleCheck, color: Color(0xFF22C55E), size: 40),
                    const SizedBox(height: 12),
                    const Text(
                      'Link Created Successfully!',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              const Text('Share Link', style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),

              // Link Display Box
              GestureDetector(
                onTap: _copyShareCode,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.link, size: 16, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'https://TREBLAPDR.github.io/link/?id=${_shareInfo!.shareId}',
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(LucideIcons.copy, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Details Row
              Row(
                children: [
                  Expanded(
                    child: _buildDetailTile(LucideIcons.clock, 'Expires', _shareInfo!.expiresAt.toString().substring(0, 10)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDetailTile(LucideIcons.shield, 'Permission', _shareInfo!.permission.displayName),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Actions
              ShadButton(
                width: double.infinity,
                size: ShadButtonSize.lg,
                onPressed: _shareViaText,
                // FIXED: Removed 'icon' param, used child Row
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.messageSquare, size: 18),
                    SizedBox(width: 8),
                    Text('Share via Message'),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              ShadButton.outline(
                width: double.infinity,
                onPressed: _copyShareCode,
                // FIXED: Removed 'icon' param, used child Row
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.copy, size: 18),
                    SizedBox(width: 8),
                    Text('Copy Code Only'),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Instructions
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('How it works:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 16),
                    _buildInstruction('1', 'Send the link via Messenger or SMS'),
                    _buildInstruction('2', 'Friend taps the link'),
                    _buildInstruction('3', 'App opens and imports the list!'),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildInstruction(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}