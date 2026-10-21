import 'package:shared_preferences/shared_preferences.dart';

import 'flow_auth_service.dart';

/// Legacy, unowned keys remain quarantined; no guessing who owns pending work.
/// Each handle captures its scope, so in-flight writes cannot change owner.
class FlowPreferences {
  FlowPreferences._(this._prefs, this._prefix);
  final SharedPreferences _prefs;
  final String _prefix;
  static Future<FlowPreferences> getInstance() async => FlowPreferences._(
    await SharedPreferences.getInstance(),
    'flow_v2_${FlowAuthService.instance.storageScope}_',
  );
  String? getString(String key) => _prefs.getString('$_prefix$key');
  int? getInt(String key) => _prefs.getInt('$_prefix$key');
  bool? getBool(String key) => _prefs.getBool('$_prefix$key');
  double? getDouble(String key) => _prefs.getDouble('$_prefix$key');
  List<String>? getStringList(String key) =>
      _prefs.getStringList('$_prefix$key');
  bool containsKey(String key) => _prefs.containsKey('$_prefix$key');
  Future<bool> setString(String key, String value) =>
      _prefs.setString('$_prefix$key', value);
  Future<bool> setInt(String key, int value) =>
      _prefs.setInt('$_prefix$key', value);
  Future<bool> setBool(String key, bool value) =>
      _prefs.setBool('$_prefix$key', value);
  Future<bool> setDouble(String key, double value) =>
      _prefs.setDouble('$_prefix$key', value);
  Future<bool> setStringList(String key, List<String> value) =>
      _prefs.setStringList('$_prefix$key', value);
  Future<bool> remove(String key) => _prefs.remove('$_prefix$key');
}
