import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/receipt_models.dart';
import '../models/ocr_result.dart';
import 'settings_service.dart';

class BackendService {
  late SettingsService _settings;
  bool _isWakingUp = false;

  Future<void> _ensureSettings() async {
    _settings = await SettingsService.getInstance();
  }

  /// Wake up Render backend (if sleeping)
  Future<BackendWakeStatus> wakeUpBackend() async {
    await _ensureSettings();

    if (_isWakingUp) {
      return BackendWakeStatus.alreadyWaking;
    }

    _isWakingUp = true;
    final startTime = DateTime.now();

    try {
      final response = await http.get(
        Uri.parse('${_settings.backendUrl}/health'),
      ).timeout(const Duration(seconds: 90)); // Long timeout for cold start

      final duration = DateTime.now().difference(startTime);
      _isWakingUp = false;

      if (response.statusCode == 200) {
        if (duration.inSeconds > 10) {
          return BackendWakeStatus.wokeUp; // Was sleeping, now awake
        } else {
          return BackendWakeStatus.alreadyAwake; // Was already running
        }
      }

      return BackendWakeStatus.failed;
    } catch (e) {
      _isWakingUp = false;
      return BackendWakeStatus.failed;
    }
  }

  /// Check backend status quickly
  Future<BackendStatus> checkBackendStatus() async {
    await _ensureSettings();

    try {
      final response = await http.get(
        Uri.parse('${_settings.backendUrl}/health'),
      ).timeout(const Duration(seconds: 3)); // Quick check

      if (response.statusCode == 200) {
        return BackendStatus.ready;
      }
      return BackendStatus.error;
    } on TimeoutException {
      return BackendStatus.sleeping; // Likely sleeping
    } catch (e) {
      return BackendStatus.offline;
    }
  }

  /// Send receipt to backend for advanced parsing
  Future<BackendResponse> processReceipt({
    String? imagePath,
    OCRResult? ocrResult,
    bool useGemini = true,
  }) async {
    await _ensureSettings();

    final String baseUrl = _settings.backendUrl;
    final Uri endpoint = Uri.parse('$baseUrl/api/process-advanced');

    try {
      // Prepare request body
      String? imageBase64;
      if (imagePath != null) {
        final bytes = await File(imagePath).readAsBytes();
        imageBase64 = base64Encode(bytes);
      }

      final Map<String, dynamic> requestBody = {
        'useGemini': useGemini,
      };

      if (imageBase64 != null) {
        requestBody['imageBase64'] = imageBase64;
      }

      if (ocrResult != null) {
        requestBody['ocrText'] = ocrResult.fullText;
        requestBody['ocrBlocks'] = ocrResult.toJson()['blocks'];
      }

      // Send request
      final response = await http.post(
        endpoint,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 90)); // Increased for Render cold start

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return BackendResponse.fromJson(jsonResponse);
      } else {
        throw Exception('Backend error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to backend: $e');
    }
  }

  /// Check if backend is reachable
  Future<bool> checkBackendHealth() async {
    await _ensureSettings();

    try {
      final response = await http.get(
        Uri.parse('${_settings.backendUrl}/health'),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Check if Gemini is configured on backend
  Future<Map<String, dynamic>> checkGeminiStatus() async {
    await _ensureSettings();

    try {
      final response = await http.get(
        Uri.parse('${_settings.backendUrl}/api/gemini-status'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'configured': false, 'error': 'Failed to check status'};
    } catch (e) {
      return {'configured': false, 'error': e.toString()};
    }
  }

  /// Process receipt with automatic fallback
  Future<BackendResponse> processReceiptWithFallback({
    String? imagePath,
    OCRResult? ocrResult,
    bool preferGemini = true,
  }) async {
    try {
      // Try with Gemini first if preferred
      if (preferGemini) {
        try {
          return await processReceipt(
            imagePath: imagePath,
            ocrResult: ocrResult,
            useGemini: true,
          );
        } catch (e) {
          // If Gemini fails, fall back to basic
          print('Gemini failed, falling back to basic: $e');
          return await processReceipt(
            imagePath: imagePath,
            ocrResult: ocrResult,
            useGemini: false,
          );
        }
      } else {
        // Use basic processing
        return await processReceipt(
          imagePath: imagePath,
          ocrResult: ocrResult,
          useGemini: false,
        );
      }
    } catch (e) {
      rethrow;
    }
  }
}

enum BackendStatus {
  ready,      // Backend is awake and responding
  sleeping,   // Backend is asleep (Render free tier)
  offline,    // Backend not reachable
  error,      // Backend error
}

enum BackendWakeStatus {
  alreadyAwake,   // Was already running
  wokeUp,         // Successfully woke up from sleep
  alreadyWaking,  // Already in process of waking
  failed,         // Failed to wake up
}