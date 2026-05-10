import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'api_service.dart';

class UpdateService {
  /// Compare two semantic version strings (e.g. "1.0.0" vs "1.0.1")
  /// Returns true if current < minimum
  static bool _isVersionBelow(String current, String minimum) {
    final curParts = current.split('.').map(int.tryParse).toList();
    final minParts = minimum.split('.').map(int.tryParse).toList();
    for (int i = 0; i < 3; i++) {
      final c = (i < curParts.length ? curParts[i] : 0) ?? 0;
      final m = (i < minParts.length ? minParts[i] : 0) ?? 0;
      if (c < m) return true;
      if (c > m) return false;
    }
    return false;
  }

  /// Check if the app needs a force update.
  /// Returns null if no update needed, or a map with update info.
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version; // e.g. "1.0.0"

      // Call the backend (no auth needed)
      final response = await ApiService.getPublic('/app-version');

      if (response['success'] != true) return null;

      final minVersion = response['minVersion'] as String? ?? '1.0.0';
      final latestVersion = response['latestVersion'] as String? ?? currentVersion;
      final forceUpdate = response['forceUpdate'] as bool? ?? false;
      final message = response['message'] as String? ?? '';
      final updateUrl = response['updateUrl'] as Map<String, dynamic>? ?? {};

      final needsUpdate = forceUpdate || _isVersionBelow(currentVersion, minVersion);
      final hasOptionalUpdate = _isVersionBelow(currentVersion, latestVersion);

      if (!needsUpdate && !hasOptionalUpdate) return null;

      // Determine store URL based on platform
      String storeUrl = '';
      if (kIsWeb) {
        storeUrl = updateUrl['web'] ?? '';
      } else if (Platform.isAndroid) {
        storeUrl = updateUrl['android'] ?? '';
      } else if (Platform.isIOS) {
        storeUrl = updateUrl['ios'] ?? '';
      }

      return {
        'forceUpdate': needsUpdate,
        'currentVersion': currentVersion,
        'latestVersion': latestVersion,
        'message': message,
        'storeUrl': storeUrl,
      };
    } catch (_) {
      // Don't block the app if version check fails
      return null;
    }
  }
}
