import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../ai/preprocess.dart';

class PreviewScreen extends StatefulWidget {
  final String imagePath;

  const PreviewScreen({super.key, required this.imagePath});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  String? _preprocessedPath;
  bool _isProcessing = false;
  bool _showPreprocessed = false;
  Map<String, dynamic>? _imageMetrics;

  @override
  void initState() {
    super.initState();
    _analyzeOriginal();
  }

  Future<void> _analyzeOriginal() async {
    final metrics = await ImagePreprocessor.analyzeImage(widget.imagePath);
    if (mounted) {
      setState(() {
        _imageMetrics = metrics;
      });
    }
  }

  Future<void> _preprocessImage() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final preprocessedPath = await ImagePreprocessor.preprocessImage(widget.imagePath);

      if (mounted) {
        setState(() {
          _preprocessedPath = preprocessedPath;
          _showPreprocessed = true;
          _isProcessing = false;
        });

        ShadToaster.of(context).show(
          const ShadToast(
            title: Text('Success'),
            description: Text('Image optimized for text recognition'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Processing Failed'),
            description: Text(e.toString()),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayPath = _showPreprocessed && _preprocessedPath != null
        ? _preprocessedPath!
        : widget.imagePath;

    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Zinc 950
      appBar: AppBar(
        title: Text(
          _showPreprocessed ? 'Enhanced Image' : 'Original Image',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF09090B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_preprocessedPath != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ShadButton.ghost(
                onPressed: () {
                  setState(() {
                    _showPreprocessed = !_showPreprocessed;
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showPreprocessed ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(_showPreprocessed ? 'View Original' : 'View Enhanced'),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // IMAGE DISPLAY
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.file(
                      File(displayPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // METRICS PANEL
          if (_imageMetrics != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B), // Zinc 900
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.info, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Image Metrics',
                        // FIXED: Removed const
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMetric('Resolution', '${_imageMetrics!['width']}x${_imageMetrics!['height']}'),
                      _buildMetric('Quality', '${_imageMetrics!['megapixels']} MP'),
                      _buildMetric('Light', '${_imageMetrics!['avgBrightness']}/255'),
                      _buildMetric('Size', '${_imageMetrics!['fileSize']}'),
                    ],
                  ),
                ],
              ),
            ),

          // ACTIONS
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF09090B),
              // FIXED: Removed const
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_preprocessedPath == null)
                    ShadButton(
                      width: double.infinity,
                      size: ShadButtonSize.lg,
                      onPressed: _isProcessing ? null : _preprocessImage,
                      child: _isProcessing
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // FIXED: Changed wand2 -> sparkles
                          Icon(LucideIcons.sparkles, size: 18),
                          SizedBox(width: 8),
                          Text('Enhance Image for OCR'),
                        ],
                      ),
                    ),

                  if (_preprocessedPath != null) ...[
                    ShadButton(
                      width: double.infinity,
                      size: ShadButtonSize.lg,
                      backgroundColor: const Color(0xFF22C55E), // Green
                      onPressed: () {
                        Navigator.pop(context, _preprocessedPath);
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.check, size: 18),
                          SizedBox(width: 8),
                          Text('Use Enhanced Image'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ShadButton.outline(
                      width: double.infinity,
                      onPressed: () {
                        Navigator.pop(context, widget.imagePath);
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.image, size: 18),
                          SizedBox(width: 8),
                          Text('Use Original Image'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          // FIXED: Removed const
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}