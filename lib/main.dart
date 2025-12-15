import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 1. Import services
import 'package:app_links/app_links.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

// Screens
import 'screens/video_splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shopping_list_screen.dart';

// Services & Models
import 'services/shopping_list_service.dart';
import 'services/sharing_service.dart';

void main() async { // 2. Mark main as async
  // 3. Ensure bindings are initialized first
  WidgetsFlutterBinding.ensureInitialized();

  // 4. Lock orientation to Portrait Up and Down
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ShoppingListApp());
}

class ShoppingListApp extends StatefulWidget {
  const ShoppingListApp({super.key});

  @override
  State<ShoppingListApp> createState() => _ShoppingListAppState();
}

class _ShoppingListAppState extends State<ShoppingListApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('Deep link error: $err');
    });
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme == 'shoplist' && uri.host == 'share') {
      final shareId = uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : null;
      if (shareId != null) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => SharedListDeepLinkHandler(shareId: shareId),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      navigatorKey: _navigatorKey,
      title: 'Predictto',
      themeMode: ThemeMode.dark,
      darkTheme: ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: const ShadZincColorScheme.dark(),
      ),
      // Starts with your Video Splash Screen
      home: const VideoSplashScreen(),
    );
  }
}

// ---------------------------------------------------------
// DEEP LINK HANDLER
// ---------------------------------------------------------

class SharedListDeepLinkHandler extends StatefulWidget {
  final String shareId;
  const SharedListDeepLinkHandler({super.key, required this.shareId});

  @override
  State<SharedListDeepLinkHandler> createState() =>
      _SharedListDeepLinkHandlerState();
}

class _SharedListDeepLinkHandlerState extends State<SharedListDeepLinkHandler> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSharedList();
    });
  }

  Future<void> _loadSharedList() async {
    showShadDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final sharingService = await SharingService.getInstance();
      final sharedList = await sharingService.accessSharedList(widget.shareId);

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      showShadDialog(
        context: context,
        builder: (context) => ShadDialog.alert(
          title: Row(
            children: [
              const Icon(LucideIcons.share2, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(sharedList.name)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${sharedList.items.length} items shared with you'),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      children: sharedList.items.map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              item.isPurchased
                                  ? LucideIcons.squareCheck
                                  : LucideIcons.square,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            if (item.price != null)
                              Text(
                                '₱${item.price!.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ShadButton.outline(
              child: const Text('Close'),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
            ),
            ShadButton(
              child: const Text('Copy to My List'),
              onPressed: () async {
                Navigator.pop(context);

                final listService = await ShoppingListService.getInstance();
                var currentList = await listService.getCurrentList();

                if (currentList == null) {
                  currentList = await listService.createList('My Shopping List');
                }

                for (final item in sharedList.items) {
                  await listService.addItem(currentList.id, item);
                }

                if (!mounted) return;

                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const ShoppingListScreen()),
                      (route) => route.isFirst,
                );

                ShadToaster.of(context).show(
                  ShadToast(
                    title: const Text('Success'),
                    description: Text('Added ${sharedList.items.length} items to your list'),
                  ),
                );
              },
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.pop(context);

      ShadToaster.of(context).show(
        ShadToast.destructive(
          title: const Text('Error'),
          description: Text('Loading shared list failed: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(),
    );
  }
}