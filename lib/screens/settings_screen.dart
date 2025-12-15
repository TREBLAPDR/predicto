import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../services/settings_service.dart';
import '../services/backend_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsService _settings;
  bool _useOnlineOCR = false;
  bool _fastScanMode = false;
  bool _isLoading = true;
  BackendStatus _backendStatus = BackendStatus.offline;
  bool _checkingBackend = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkBackendStatus();
  }

  Future<void> _loadSettings() async {
    _settings = await SettingsService.getInstance();
    setState(() {
      _useOnlineOCR = _settings.useOnlineOCR;
      _fastScanMode = _settings.fastScanMode;
      _isLoading = false;
    });
  }

  Future<void> _checkBackendStatus() async {
    setState(() => _checkingBackend = true);

    final backendService = BackendService();
    final status = await backendService.checkBackendStatus();

    if (mounted) {
      setState(() {
        _backendStatus = status;
        _checkingBackend = false;
      });
    }
  }

  Future<void> _wakeUpBackend() async {
    setState(() => _checkingBackend = true);

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
              Text('Waking up backend...', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text(
                'This may take up to 60 seconds',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );

    final backendService = BackendService();
    final wakeStatus = await backendService.wakeUpBackend();

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    setState(() => _checkingBackend = false);

    String message;
    bool isError = false;

    switch (wakeStatus) {
      case BackendWakeStatus.alreadyAwake:
        message = 'Backend is already running!';
        setState(() => _backendStatus = BackendStatus.ready);
        break;
      case BackendWakeStatus.wokeUp:
        message = 'Backend woke up successfully!';
        setState(() => _backendStatus = BackendStatus.ready);
        break;
      case BackendWakeStatus.failed:
        message = 'Failed to wake backend. Check your connection.';
        isError = true;
        break;
      case BackendWakeStatus.alreadyWaking:
        message = 'Backend is already waking up...';
        break;
    }

    if (!mounted) return;

    ShadToaster.of(context).show(
      isError
          ? ShadToast.destructive(title: const Text('Wake Failed'), description: Text(message))
          : ShadToast(title: const Text('Success'), description: Text(message)),
    );
  }

  Future<void> _toggleOnlineOCR(bool value) async {
    await _settings.setUseOnlineOCR(value);
    setState(() {
      _useOnlineOCR = value;
    });

    if (!mounted) return;
    ShadToaster.of(context).show(
      ShadToast(
        title: Text(value ? 'Online Mode Enabled' : 'Offline Mode Enabled'),
        description: Text(value ? 'Using Gemini Pro' : 'Using ML Kit (Offline)'),
      ),
    );
  }

  Future<void> _toggleFastScanMode(bool value) async {
    // Fast scan requires online OCR
    if (value && !_useOnlineOCR) {
      await _settings.setUseOnlineOCR(true);
      setState(() => _useOnlineOCR = true);
    }

    await _settings.setFastScanMode(value);
    setState(() {
      _fastScanMode = value;
    });

    if (!mounted) return;
    ShadToaster.of(context).show(
      ShadToast(
        title: Text(value ? 'Fast Scan Enabled' : 'Fast Scan Disabled'),
        description: Text(value ? 'Auto preprocess & AI parse' : 'Manual review enabled'),
      ),
    );
  }

  Future<void> _editBackendUrl() async {
    final controller = TextEditingController(text: _settings.backendUrl);

    await showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Backend URL'),
        description: const Text('Enter the base URL for the Predicto backend.'),
        // FIXED: Use 'child' instead of 'content'
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ShadInput(
            controller: controller,
            placeholder: const Text('https://predicto-zt7z.onrender.com'),
            keyboardType: TextInputType.url,
          ),
        ),
        actions: [
          ShadButton.outline(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          ShadButton(
            child: const Text('Save'),
            onPressed: () async {
              final newUrl = controller.text;
              if (newUrl.isNotEmpty) {
                await _settings.setBackendUrl(newUrl);
                setState(() {}); // refresh UI

                if (mounted) {
                  Navigator.pop(context);
                  ShadToaster.of(context).show(
                    const ShadToast(
                      title: Text('URL Updated'),
                      description: Text('Backend URL has been saved.'),
                    ),
                  );
                  _checkBackendStatus(); // Recheck
                }
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF09090B),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final statusColor = _getStatusColor();
    final statusIcon = _getStatusIcon();

    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Deep dark background
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ------------------------------------
          // BACKEND STATUS CARD
          // ------------------------------------
          ShadCard(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Backend Status',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getStatusText(),
                            style: TextStyle(fontSize: 13, color: statusColor),
                          ),
                        ],
                      ),
                    ),
                    if (_checkingBackend)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                    // FIXED: Removed 'icon' param, used child Row
                      ShadButton.ghost(
                        size: ShadButtonSize.sm,
                        onPressed: _checkBackendStatus,
                        child: const Icon(LucideIcons.refreshCw, size: 16),
                      ),
                  ],
                ),

                if (_backendStatus == BackendStatus.sleeping) ...[
                  const SizedBox(height: 16),
                  ShadButton(
                    width: double.infinity,
                    backgroundColor: Colors.orange,
                    onPressed: _wakeUpBackend,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.power, size: 18),
                        SizedBox(width: 8),
                        Text('Wake Up Backend'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Free tier backend sleeps after 15 min inactivity.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text('Scanning Options', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // ------------------------------------
          // FAST SCAN TOGGLE
          // ------------------------------------
          ShadCard(
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fast Scan Mode', style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text(
                            'Skip review - Auto preprocess & parse',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ShadSwitch(
                      value: _fastScanMode,
                      onChanged: _toggleFastScanMode,
                    ),
                  ],
                ),

                if (_fastScanMode) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.info, color: Colors.blue, size: 18),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Camera → Auto Preprocess → AI Parse → Results',
                            style: TextStyle(color: Colors.blue, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ------------------------------------
          // ONLINE OCR TOGGLE
          // ------------------------------------
          ShadCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Online OCR (Gemini Pro)', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            _useOnlineOCR
                                ? 'Higher accuracy (Requires Internet)'
                                : 'Fast & Private (Uses On-device ML Kit)',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ShadSwitch(
                      value: _useOnlineOCR,
                      // Disable toggle if Fast Scan is ON (forces online)
                      enabled: !_fastScanMode,
                      onChanged: _toggleOnlineOCR,
                    ),
                  ],
                ),

                if (_useOnlineOCR && !_fastScanMode) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.info, color: Colors.orange, size: 18),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Sends receipt images to backend for Gemini processing.',
                            style: TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text('Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // ------------------------------------
          // BACKEND URL CONFIG
          // ------------------------------------
          ShadCard(
            child: InkWell(
              onTap: _editBackendUrl,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(LucideIcons.server, size: 24, color: Colors.grey),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Backend URL', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            _settings.backendUrl,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.pencil, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ------------------------------------
          // TEST CONNECTION BUTTON
          // ------------------------------------
          ShadButton.outline(
            onPressed: () async {
              showShadDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator()),
              );

              try {
                final backendService = BackendService();
                final isHealthy = await backendService.checkBackendHealth();

                if (!mounted) return;
                Navigator.pop(context); // Close loading

                if (isHealthy) {
                  ShadToaster.of(context).show(
                    const ShadToast(
                      title: Text('Connected'),
                      description: Text('Backend is reachable and healthy.'),
                    ),
                  );
                  _checkBackendStatus();
                } else {
                  ShadToaster.of(context).show(
                    const ShadToast.destructive(
                      title: Text('Connection Failed'),
                      description: Text('Backend not reachable.'),
                    ),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(context);
                ShadToaster.of(context).show(
                  ShadToast.destructive(
                    title: const Text('Error'),
                    description: Text(e.toString()),
                  ),
                );
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.wifi, size: 18),
                SizedBox(width: 8),
                Text('Test Connection'),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ------------------------------------
  // HELPER METHODS
  // ------------------------------------

  Color _getStatusColor() {
    switch (_backendStatus) {
      case BackendStatus.ready:
        return Colors.green;
      case BackendStatus.sleeping:
        return Colors.orange;
      case BackendStatus.offline:
      case BackendStatus.error:
        return Colors.red;
    }
  }

  IconData _getStatusIcon() {
    switch (_backendStatus) {
      case BackendStatus.ready:
      // FIXED: Renamed checkCircle -> circleCheck
        return LucideIcons.circleCheck;
      case BackendStatus.sleeping:
        return LucideIcons.moon;
      case BackendStatus.offline:
        return LucideIcons.cloudOff;
      case BackendStatus.error:
      // FIXED: Renamed alertCircle -> circleAlert
        return LucideIcons.circleAlert;
    }
  }

  String _getStatusText() {
    switch (_backendStatus) {
      case BackendStatus.ready:
        return 'Ready';
      case BackendStatus.sleeping:
        return 'Sleeping (Render Free Tier)';
      case BackendStatus.offline:
        return 'Offline / Unreachable';
      case BackendStatus.error:
        return 'Configuration Error';
    }
  }
}