import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesWithCache, SharedPreferencesWithCacheOptions;
import 'dart:convert' show jsonDecode, jsonEncode;

class Storage {
  late final SharedPreferencesWithCache _prefs;
  bool _initialized = false;

  // Constants for storage keys
  static const String updatedTimeSuffix = 'UpdatedTime';
  static const String listsSuffix = 'Lists';

  Future<void> init() async {
    if (!_initialized) {
      final SharedPreferencesWithCache prefsWithCache =
          await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );

      _prefs = prefsWithCache;
      _initialized = true;
    }
  }

  Future<void> saveMod(String modName, String value) async {
    if (!_initialized) await init();
    return await _prefs.setString(modName, value);
  }

  Future<void> saveModUpdateTime(String modName, int timestamp) async {
    if (!_initialized) await init();
    return await _prefs.setInt('$modName$updatedTimeSuffix', timestamp);
  }

  Future<void> saveModMap(String modName, Map<String, String> data) async {
    if (!_initialized) await init();
    return await _prefs.setString('$modName$listsSuffix', jsonEncode(data));
  }

  String? getMod(String modName) {
    if (!_initialized) return null;
    return _prefs.getString(modName);
  }

  int? getModUpdateTime(String modName) {
    if (!_initialized) return null;
    return _prefs.getInt('$modName$updatedTimeSuffix');
  }

  Map<String, String>? getModAssetLists(String jsonFileName) {
    if (!_initialized) return null;
    final jsonStr = _prefs.getString('$jsonFileName$listsSuffix');
    if (jsonStr == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(jsonStr);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  Future<bool> saveModData(
      String modName, int updateTime, Map<String, String> data) async {
    if (!_initialized) await init();

    final results = await Future.wait([
      saveMod(modName, modName),
      saveModUpdateTime(modName, updateTime),
      saveModMap(modName, data)
    ]);

    return !results.contains(false);
  }

  Future<bool> deleteMod(String modName) async {
    if (!_initialized) return false;

    final results = await Future.wait([
      _prefs.remove(modName),
      _prefs.remove('$modName$updatedTimeSuffix'),
      _prefs.remove('$modName$listsSuffix')
    ]);

    return !results.contains(false);
  }
}
