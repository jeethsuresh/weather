import 'dart:convert';
import 'models.dart';
import 'storage.dart';
import 'weather_api.dart';

class WeatherRepository {
  WeatherRepository(this.store, this.api);
  factory WeatherRepository.device() {
    final store = DeviceStore();
    return WeatherRepository(store, WeatherApi(HttpTransport(), store));
  }
  final LocalStore store;
  final WeatherApi api;

  Future<Settings> settings() async {
    try {
      final s = await store.read('settings.v1');
      return s == null ? const Settings() : Settings.fromJson(jsonDecode(s));
    } catch (_) {
      return const Settings();
    }
  }

  Future<void> saveSettings(Settings s) =>
      store.write('settings.v1', jsonEncode(s.toJson()));
  Future<Forecast?> cached(Settings s) async {
    try {
      final data = await store.read(s.cacheKey);
      return data == null ? null : Forecast.fromJson(jsonDecode(data));
    } catch (_) {
      return null;
    }
  }

  Future<Forecast> refresh(Settings s, {bool force = false}) async {
    final old = await cached(s);
    if (!force &&
        old != null &&
        api.now().difference(old.fetchedAt) < const Duration(hours: 1) &&
        !old.staleAt(api.now())) {
      return old;
    }
    final fresh = await api.fetch(s);
    // A location/source-specific key prevents a background task from replacing a
    // different place's forecast while the user changes cities in the foreground.
    await store.write(s.cacheKey, jsonEncode(fresh.toJson()));
    return fresh;
  }

  void close() => api.http.close();
}
