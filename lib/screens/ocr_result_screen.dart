import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../models/ocr_result.dart';
import '../services/backend_service.dart';
import '../services/settings_service.dart';
import '../ai/confidence_analyzer.dart';
import 'parsed_receipt_screen.dart';

class OCRResultScreen extends StatefulWidget {
  final OCRResult ocrResult;
  final String imagePath;

  const OCRResultScreen({
    super.key,
    required this.ocrResult,
    required this.imagePath,
  });

  @override
  State<OCRResultScreen> createState() => _OCRResultScreenState();
}

class _OCRResultScreenState extends State<OCRResultScreen> {
  late ConfidenceAnalysis _analysis;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _analysis = ConfidenceAnalyzer.analyze(widget.ocrResult);
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: widget.ocrResult.fullText));
    ShadToaster.of(context).show(
      const ShadToast(
        title: Text('Copied'),
        description: Text('Text copied to clipboard'),
      ),
    );
  }

  Future<void> _parseWithBackend(BuildContext context, {bool forceGemini = false}) async {
    final settings = await SettingsService.getInstance();

    bool useGemini = forceGemini || settings.useOnlineOCR;

    if (!useGemini &&
        (_analysis.recommendation == ProcessingRecommendation.onlineSuggested ||
            _analysis.recommendation == ProcessingRecommendation.onlineRequired)) {

      if (!context.mounted) return;

      final enable = await showShadDialog<bool>(
        context: context,
        builder: (context) => ShadDialog(
          title: const Text('Use Online AI?'),
          description: Text(_analysis.reasoning),
          child: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Online mode uses Google Gemini for better accuracy but sends receipt data to the cloud.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Use Local Only'),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Use Online AI'),
            ),
          ],
        ),
      );

      if (enable == true) {
        await settings.setUseOnlineOCR(true);
        useGemini = true;
      }
    }

    if (!context.mounted) return;

    showShadDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: ShadCard(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                useGemini ? 'Parsing with AI...' : 'Processing locally...',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                useGemini
                    ? 'First request may take 60s (server wake-up)'
                    : 'This may take 2-3 seconds',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final backendService = BackendService();
      final isHealthy = await backendService.checkBackendHealth();

      if (!isHealthy) {
        if (!context.mounted) return;
        Navigator.pop(context);

        ShadToaster.of(context).show(
          const ShadToast.destructive(
            title: Text('Connection Error'),
            description: Text('Backend not reachable. Check if server is running.'),
          ),
        );
        return;
      }

      final response = await backendService.processReceipt(
        imagePath: widget.imagePath,
        ocrResult: widget.ocrResult,
        useGemini: useGemini,
      );

      if (!context.mounted) return;
      Navigator.pop(context);

      if (response.success && response.receipt != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ParsedReceiptScreen(
              receipt: response.receipt!,
              method: response.method,
              processingTimeMs: response.processingTimeMs,
            ),
          ),
        );
      } else {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Parsing Failed'),
            description: Text(response.error ?? 'Unknown error'),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);

      ShadToaster.of(context).show(
        ShadToast.destructive(
          title: const Text('Error'),
          description: Text(e.toString().substring(0, 100)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _analysis.getScoreColor();

    // FIXED: Updated Icon names to match Lucide standard
    IconData statusIcon;
    if (_analysis.overallScore >= 0.8) {
      statusIcon = LucideIcons.circleCheck;
    } else if (_analysis.overallScore >= 0.6) {
      statusIcon = LucideIcons.triangleAlert;
    } else {
      statusIcon = LucideIcons.circleX;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Zinc 950
      appBar: AppBar(
        title: const Text('OCR Results', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.copy, color: Colors.white70),
            onPressed: () => _copyToClipboard(context),
            tooltip: 'Copy text',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Confidence Analysis Card
            Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  // FIXED: Removed const
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  // FIXED: Removed const
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          // FIXED: Removed const
                          color: statusColor.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(statusIcon, color: statusColor, size: 24),
                      ),
                      title: Text(
                        'Quality Score: ${(_analysis.overallScore * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _analysis.reasoning,
                          // FIXED: Removed const
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          _isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                          color: Colors.white70,
                        ),
                        onPressed: () {
                          setState(() {
                            _isExpanded = !_isExpanded;
                          });
                        },
                      ),
                    ),
                    if (_isExpanded) ...[
                      // Divider - FIXED: Removed const
                      Container(height: 1, color: statusColor.withOpacity(0.2)),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildScoreDetail('OCR Confidence', _analysis.ocrConfidence),
                            _buildScoreDetail('Text Density', _analysis.textDensityScore),
                            _buildScoreDetail('Price Patterns', _analysis.pricePatternScore),
                            _buildScoreDetail('Structure', _analysis.structureScore),

                            if (_analysis.issues.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Text(
                                'Issues Detected:',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              ..._analysis.issues.map((issue) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('• ', style: TextStyle(color: Colors.red)),
                                    Expanded(child: Text(issue, style: const TextStyle(fontSize: 13, color: Colors.grey))),
                                  ],
                                ),
                              )),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // OCR Statistics
            // FIXED: Replaced margin param with Padding wrapper
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ShadCard(
                backgroundColor: const Color(0xFF18181B),
                border: ShadBorder.all(color: Colors.white10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          // FIXED: Renamed barChart2 -> chartBar
                          Icon(LucideIcons.chartBar, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Scan Statistics',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatItem('Time', '${widget.ocrResult.processingTime.inMilliseconds}ms'),
                          _buildStatItem('Blocks', '${widget.ocrResult.blockCount}'),
                          _buildStatItem('Lines', '${widget.ocrResult.lineCount}'),
                          _buildStatItem('Chars', '${widget.ocrResult.fullText.length}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Extracted text preview
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Raw Text Preview',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B), // Zinc 900
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.ocrResult.fullText.isEmpty ? 'No text detected' : widget.ocrResult.fullText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.grey),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Primary action
                  ShadButton(
                    width: double.infinity,
                    size: ShadButtonSize.lg,
                    onPressed: () => _parseWithBackend(context, forceGemini: true),
                    // FIXED: Removed const
                    backgroundColor: _analysis.recommendation == ProcessingRecommendation.onlineRequired
                        ? const Color(0xFF22C55E) // Green
                        : Colors.white,
                    foregroundColor: _analysis.recommendation == ProcessingRecommendation.onlineRequired
                        ? Colors.white
                        : Colors.black,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.sparkles, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _analysis.recommendation == ProcessingRecommendation.onlineRequired
                              ? 'Process with AI (Recommended)'
                              : 'Improve Accuracy (Online AI)',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Secondary action
                  if (_analysis.recommendation != ProcessingRecommendation.onlineRequired)
                    ShadButton.outline(
                      width: double.infinity,
                      onPressed: () => _parseWithBackend(context, forceGemini: false),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.zap, size: 18),
                          SizedBox(width: 8),
                          Text('Process Locally (Faster)'),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),

                  ShadButton.ghost(
                    width: double.infinity,
                    onPressed: () => Navigator.pop(context),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.arrowLeft, size: 18),
                        SizedBox(width: 8),
                        Text('Back to Home'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        const SizedBox(height: 2),
        // FIXED: Removed const
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildScoreDetail(String label, double score) {
    final Color barColor = score >= 0.8
        ? const Color(0xFF22C55E)
        : score >= 0.6
        ? Colors.orange
        : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            // FIXED: Removed const
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade300)),
          ),
          Expanded(
            flex: 4,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: score,
                child: Container(
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 40,
            child: Text(
              '${(score * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}