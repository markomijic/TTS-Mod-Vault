import 'dart:io' show Platform;

import 'package:bson/bson.dart' show ObjectId;
import 'package:flutter/material.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart' show dotenv;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

class AnalyticsService {
  static const String _deviceIdKey = 'analytics_device_id';
  static const String _lastPingDateKey = 'analytics_last_ping_date';

  /// Initialize Supabase and send daily ping. Fire-and-forget.
  /// Call this once during app startup after dotenv is loaded.
  static Future<void> initAndPing({required String appVersion}) async {
    try {
      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final supabaseAnonKey = dotenv.env['SUPABASE_PUBLISHABLE_KEY'];

      if (supabaseUrl == null || supabaseAnonKey == null) {
        debugPrint('AnalyticsService: Missing Supabase credentials in .env');
        return;
      }

      final prefs = SharedPreferencesAsync();

      // Check if already pinged today
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final lastPingDate = await prefs.getString(_lastPingDateKey);

      if (lastPingDate == today) {
        debugPrint('AnalyticsService: Already pinged today');
        return;
      }

      // Get or create anonymous device ID
      var deviceId = await prefs.getString(_deviceIdKey);
      if (deviceId == null) {
        deviceId = ObjectId().oid;
        await prefs.setString(_deviceIdKey, deviceId);
      }

      // Determine platform
      final platform = Platform.isWindows
          ? 'windows'
          : Platform.isMacOS
              ? 'macos'
              : Platform.isLinux
                  ? 'linux'
                  : 'unknown';

      // Send ping
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      await Supabase.instance.client.from('daily_pings').insert({
        'device_id': deviceId,
        'app_version': appVersion,
        'platform': platform,
      });

      await prefs.setString(_lastPingDateKey, today);

      debugPrint('AnalyticsService: Ping sent successfully');
    } catch (e) {
      // Silently ignore all errors -- fire-and-forget telemetry
      debugPrint('AnalyticsService: $e');
    }
  }
}
