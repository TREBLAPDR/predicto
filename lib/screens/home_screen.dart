import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:audioplayers/audioplayers.dart';

// Screens
import 'settings_screen.dart';
import 'camera_screen.dart';
import 'shopping_list_screen.dart';
import 'preview_screen.dart';
import 'ocr_result_screen.dart';
import 'parsed_receipt_screen.dart';
import 'suggestions_screen.dart';
import 'products_screen.dart';

// Services & AI
import '../ai/preprocess.dart';
import '../ai/ocr_service.dart';
import '../services/settings_service.dart';
import '../services/shopping_list_service.dart';
import '../services/backend_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String? _lastCapturedImage;
  bool _isWakingBackend = false;

  late AudioPlayer _audioPlayer;
  static bool _hasPlayedWelcomeSound = false;

  // Animation Controllers
  late AnimationController _entranceController; // For the "Building" effect
  late AnimationController _shineController;    // For the "Sword" effect

  @override
  void initState() {
    super.initState();
    _autoWakeBackend();
    _playWelcomeSound();

    // 1. Setup Entrance Animation (Runs once)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200), // Total build time
    );

    // 2. Setup Shine Animation (Loops)
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Start Sequence: Build first, then start shining
    _entranceController.forward().then((_) {
      _shineController.repeat(period: const Duration(seconds: 3));
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _shineController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playWelcomeSound() async {
    if (!_hasPlayedWelcomeSound) {
      _audioPlayer = AudioPlayer();
      await _audioPlayer.play(AssetSource('audio/welcome.mp3'));
      _hasPlayedWelcomeSound = true;
    } else {
      _audioPlayer = AudioPlayer();
    }
  }

  Future<void> _autoWakeBackend() async {
    final settings = await SettingsService.getInstance();
    if (settings.useOnlineOCR || settings.fastScanMode) {
      setState(() => _isWakingBackend = true);
      final backendService = BackendService();
      final status = await backendService.checkBackendStatus();
      if (status == BackendStatus.sleeping) {
        backendService.wakeUpBackend();
      }
      if (mounted) {
        setState(() => _isWakingBackend = false);
      }
    }
  }

  // ------------------------------------------------------
  // ACTION HANDLERS
  // ------------------------------------------------------

  Future<void> _openCamera() async {
    final String? imagePath = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const CameraScreen()),
    );

    if (imagePath != null) {
      final settings = await SettingsService.getInstance();
      if (settings.fastScanMode) {
        await _fastScanFlow(imagePath);
      } else {
        await _normalScanFlow(imagePath);
      }
    }
  }

  Future<void> _fastScanFlow(String imagePath) async {
    if (!mounted) return;

    showShadDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: ShadCard(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Processing Receipt...', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('AI Analysis in progress', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );

    try {
      final preprocessedPath = await ImagePreprocessor.preprocessImage(imagePath);
      final ocrService = OCRService();
      final ocrResult = await ocrService.performOCR(preprocessedPath);
      ocrService.dispose();

      final backendService = BackendService();
      final response = await backendService.processReceipt(
        imagePath: preprocessedPath,
        ocrResult: ocrResult,
        useGemini: true,
      );

      if (!mounted) return;
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
            ShadToast.destructive(title: const Text('Scan Failed'), description: Text(response.error ?? 'Unknown error'))
        );
      }
      setState(() => _lastCapturedImage = preprocessedPath);
      ImagePreprocessor.cleanupOldImages();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ShadToaster.of(context).show(
          ShadToast.destructive(title: const Text('Error'), description: Text(e.toString()))
      );
    }
  }

  Future<void> _normalScanFlow(String imagePath) async {
    if (!mounted) return;
    final String? finalPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => PreviewScreen(imagePath: imagePath)),
    );

    if (finalPath != null) {
      setState(() => _lastCapturedImage = finalPath);
      ImagePreprocessor.cleanupOldImages();
      if (!mounted) return;
      _performOCR(finalPath);
    }
  }

  Future<void> _performOCR(String imagePath) async {
    showShadDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: ShadCard(
          width: 250,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Reading Text...'),
            ],
          ),
        ),
      ),
    );

    try {
      final ocrService = OCRService();
      final ocrResult = await ocrService.performOCR(imagePath);
      ocrService.dispose();

      if (!mounted) return;
      Navigator.pop(context);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OCRResultScreen(ocrResult: ocrResult, imagePath: imagePath),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ShadToaster.of(context).show(
          ShadToast.destructive(title: const Text('OCR Failed'), description: Text(e.toString()))
      );
    }
  }

  Future<void> _showQuickSuggestions() async {
    final listService = await ShoppingListService.getInstance();
    var currentList = await listService.getCurrentList();
    if (currentList == null) {
      currentList = await listService.createList('My Shopping List');
    }
    if (!mounted) return;
    final addedCount = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (context) => SuggestionsScreen(listId: currentList!.id, currentItems: currentList.items),
      ),
    );

    if (addedCount != null && addedCount > 0) {
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (context) => const ShoppingListScreen()));
    }
  }

  // ------------------------------------------------------
  // UI BUILDER
  // ------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Deep Zinc background
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -----------------------
              // HEADER (Slide Down)
              // -----------------------
              _EntranceWrapper(
                controller: _entranceController,
                intervalStart: 0.0, // Starts immediately
                intervalEnd: 0.4,
                direction: _EntranceDirection.down,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        DefaultTextStyle(
                          style: const TextStyle(
                            fontSize: 24.0,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                          ),
                          child: AnimatedTextKit(
                            animatedTexts: [
                              ColorizeAnimatedText(
                                'Predictto',
                                textStyle: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                                colors: [
                                  Colors.white,
                                  const Color(0xFFE4E4E7),
                                  const Color(0xFFA1A1AA),
                                  Colors.white,
                                ],
                                speed: const Duration(milliseconds: 3000),
                              ),
                            ],
                            isRepeatingAnimation: true,
                            totalRepeatCount: 100,
                          ),
                        ),
                      ],
                    ),

                    BouncingWrapper(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SettingsScreen()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(LucideIcons.settings, size: 24, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),

              if (_isWakingBackend)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text("Syncing services...", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),

              const Spacer(),

              // -----------------------
              // CENTER HERO SECTION
              // -----------------------
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Typewriter Text (Fade In)
                    _EntranceWrapper(
                      controller: _entranceController,
                      intervalStart: 0.2, // Delays slightly
                      intervalEnd: 0.5,
                      direction: _EntranceDirection.fade,
                      child: SizedBox(
                        height: 50,
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            fontSize: 16.0,
                            fontFamily: 'Courier',
                            color: Colors.grey,
                          ),
                          child: AnimatedTextKit(
                            animatedTexts: [
                              TypewriterAnimatedText(
                                "Smarter Systems, Smarter You",
                                speed: const Duration(milliseconds: 80),
                                cursor: '|',
                              ),
                            ],
                            totalRepeatCount: 1,
                            displayFullTextOnTap: true,
                            stopPauseOnTap: true,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 2. Scan Button (Slide Up & Shine)
                    _EntranceWrapper(
                      controller: _entranceController,
                      intervalStart: 0.3,
                      intervalEnd: 0.7,
                      direction: _EntranceDirection.up,
                      child: BouncingWrapper(
                        onTap: _openCamera,
                        child: ShiningButton(
                          width: 240,
                          height: 64,
                          // Pass the shine controller here
                          shineController: _shineController,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.scanLine, size: 24, color: Colors.black),
                              SizedBox(width: 12),
                              Text(
                                'Scan Receipt',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 3. Secondary Actions (Scale In / Pop)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _EntranceWrapper(
                          controller: _entranceController,
                          intervalStart: 0.5,
                          intervalEnd: 0.8,
                          direction: _EntranceDirection.scale,
                          child: _buildQuickAction(
                            label: 'My List',
                            icon: LucideIcons.list,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ShoppingListScreen())),
                          ),
                        ),
                        const SizedBox(width: 16),
                        _EntranceWrapper(
                          controller: _entranceController,
                          intervalStart: 0.6,
                          intervalEnd: 0.9,
                          direction: _EntranceDirection.scale,
                          child: _buildQuickAction(
                            label: 'Products',
                            icon: LucideIcons.package,
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ProductsScreen())),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // 4. Smart Suggestions (Fade In Up)
                    _EntranceWrapper(
                      controller: _entranceController,
                      intervalStart: 0.7,
                      intervalEnd: 1.0,
                      direction: _EntranceDirection.up,
                      child: BouncingWrapper(
                        onTap: _showQuickSuggestions,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.sparkles, color: Colors.amber, size: 16),
                            SizedBox(width: 8),
                            Text('Smart Suggestions', style: TextStyle(color: Colors.amber)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // -----------------------
              // FOOTER
              // -----------------------
              if (_lastCapturedImage != null)
                Center(
                  child: ShadBadge.secondary(
                    child: Text(
                      'Last scan: ${_lastCapturedImage!.split('/').last}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction({required String label, required IconData icon, required VoidCallback onTap}) {
    return BouncingWrapper(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 90,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withOpacity(0.02),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: Colors.white70),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ENTRANCE ANIMATION WRAPPER
// -----------------------------------------------------------------------------

enum _EntranceDirection { up, down, left, right, fade, scale }

class _EntranceWrapper extends StatelessWidget {
  final AnimationController controller;
  final double intervalStart;
  final double intervalEnd;
  final _EntranceDirection direction;
  final Widget child;

  const _EntranceWrapper({
    required this.controller,
    required this.intervalStart,
    required this.intervalEnd,
    required this.direction,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Interval(intervalStart, intervalEnd, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // Fade logic (always fade in)
        final opacity = animation.value;

        // Transform logic
        Matrix4 transform = Matrix4.identity();

        switch (direction) {
          case _EntranceDirection.up:
            transform = Matrix4.translationValues(0, 30 * (1 - animation.value), 0);
            break;
          case _EntranceDirection.down:
            transform = Matrix4.translationValues(0, -30 * (1 - animation.value), 0);
            break;
          case _EntranceDirection.left:
            transform = Matrix4.translationValues(30 * (1 - animation.value), 0, 0);
            break;
          case _EntranceDirection.right:
            transform = Matrix4.translationValues(-30 * (1 - animation.value), 0, 0);
            break;
          case _EntranceDirection.scale:
            final scale = 0.8 + (0.2 * animation.value);
            transform = Matrix4.diagonal3Values(scale, scale, 1.0);
            break;
          case _EntranceDirection.fade:
          // No movement, just fade (handled by Opacity widget)
            break;
        }

        return Opacity(
          opacity: opacity,
          child: Transform(
            transform: transform,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

// -----------------------------------------------------------------------------
// CUSTOM ANIMATION WIDGETS
// -----------------------------------------------------------------------------

class BouncingWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const BouncingWrapper({super.key, required this.child, required this.onTap});

  @override
  State<BouncingWrapper> createState() => _BouncingWrapperState();
}

class _BouncingWrapperState extends State<BouncingWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Duration _duration = const Duration(milliseconds: 100);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration, lowerBound: 0.0, upperBound: 0.1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final scale = 1 - _controller.value;
          return Transform.scale(
            scale: scale,
            child: widget.child,
          );
        },
      ),
    );
  }
}

class ShiningButton extends StatefulWidget {
  final Widget child;
  final double width;
  final double height;
  final AnimationController? shineController; // Now accepts external controller

  const ShiningButton({
    super.key,
    required this.child,
    this.width = 200,
    this.height = 50,
    this.shineController,
  });

  @override
  State<ShiningButton> createState() => _ShiningButtonState();
}

class _ShiningButtonState extends State<ShiningButton> with SingleTickerProviderStateMixin {
  late AnimationController _localController;
  AnimationController get _controller => widget.shineController ?? _localController;

  @override
  void initState() {
    super.initState();
    if (widget.shineController == null) {
      _localController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
      _startAnimationLoop();
    }
  }

  void _startAnimationLoop() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        await _localController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    if (widget.shineController == null) {
      _localController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white, // Shadcn Primary
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Center(child: widget.child),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Positioned(
                top: 0,
                bottom: 0,
                left: -widget.width + (_controller.value * (widget.width * 2.5)),
                width: widget.width / 2,
                child: Container(
                  transform: Matrix4.skewX(-0.3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.6),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}