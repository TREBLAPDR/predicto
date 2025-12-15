import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyUseOnlineOCR = 'use_online_ocr';
  static const String _keyBackendUrl = 'backend_url';
  static const String _keyFastScanMode = 'fast_scan_mode';

  static SettingsService? _instance;
  late SharedPreferences _prefs;

  SettingsService._();

  static Future<SettingsService> getInstance() async {
    if (_instance == null) {
      _instance = SettingsService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  // Online OCR mode (uses Gemini Pro via backend)
  bool get useOnlineOCR => _prefs.getBool(_keyUseOnlineOCR) ?? false;

  Future<void> setUseOnlineOCR(bool value) async {
    await _prefs.setBool(_keyUseOnlineOCR, value);
  }

  // Fast Scan Mode - auto preprocess and parse with AI
  bool get fastScanMode => _prefs.getBool(_keyFastScanMode) ?? false;

  Future<void> setFastScanMode(bool value) async {
    await _prefs.setBool(_keyFastScanMode, value);
  }

  // Backend URL for online processing
  String get backendUrl {
    final savedUrl = _prefs.getString(_keyBackendUrl);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      return savedUrl;
    }
    // Production URL (Render)
    return 'https://predicto-zt7z.onrender.com';
  }

  Future<void> setBackendUrl(String url) async {
    await _prefs.setString(_keyBackendUrl, url);
  }
}