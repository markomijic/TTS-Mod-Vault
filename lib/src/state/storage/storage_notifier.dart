import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

class Storage {
  late final SharedPreferences _prefs;
  bool _initialized = false;

  Future<void> init() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  // Save item value
  Future<bool> saveItem(String itemName, String value) async {
    if (!_initialized) await init();
    return await _prefs.setString(itemName, value);
  }

  // Save item's updated time
  Future<bool> saveItemUpdateTime(String itemName, int timestamp) async {
    if (!_initialized) await init();
    return await _prefs.setInt('${itemName}UpdatedTime', timestamp);
  }

  // Save item's map data
  Future<bool> saveItemMap(String itemName, Map<String, String> data) async {
    if (!_initialized) await init();
    return await _prefs.setString('${itemName}List', jsonEncode(data));
  }

  // Get item value
  String? getItem(String itemName) {
    if (!_initialized) return null;
    return _prefs.getString(itemName);
  }

  // Get item's updated time
  int? getItemUpdateTime(String itemName) {
    if (!_initialized) return null;
    return _prefs.getInt('${itemName}UpdatedTime');
  }

  // Get item's map data
  Map<String, String>? getItemMap(String itemName) {
    if (!_initialized) return null;
    final jsonStr = _prefs.getString('${itemName}List');
    if (jsonStr == null) return null;

    final Map<String, dynamic> decoded = jsonDecode(jsonStr);

    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  // Save all information for an item at once
  Future<bool> saveAllItemData(String itemName, String value, int updateTime,
      Map<String, String> data) async {
    if (!_initialized) await init();

    final results = await Future.wait([
      saveItem(itemName, value),
      saveItemUpdateTime(itemName, updateTime),
      saveItemMap(itemName, data)
    ]);

    return !results.contains(false);
  }

  // Delete all information for an item
  Future<bool> deleteItem(String itemName) async {
    if (!_initialized) return false;

    final results = await Future.wait([
      _prefs.remove(itemName),
      _prefs.remove('${itemName}UpdatedTime'),
      _prefs.remove('${itemName}List')
    ]);

    return !results.contains(false);
  }
}
