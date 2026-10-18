import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// The uncached API sees writes from WorkManager's separate Dart isolate.
class DeviceStore implements LocalStore {
  final _preferences = SharedPreferencesAsync();
  @override
  Future<String?> read(String key) => _preferences.getString(key);
  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);
}
