import 'dart:async';
import 'package:flutter/foundation.dart';
import 'models.dart';
import 'repository.dart';
import 'location.dart';

typedef WidgetPublisher =
    Future<void> Function(WeatherRepository, Settings, Forecast?);

class WeatherController extends ChangeNotifier {
  WeatherController(
    this.repository, {
    required this.publish,
    required this.schedule,
    LocationLookup? locationLookup,
  }) : locationLookup = locationLookup ?? DeviceLocationLookup(repository.api);
  final WeatherRepository repository;
  final WidgetPublisher publish;
  final LocationLookup locationLookup;
  bool locating = false;
  String? locationError;
  LocationIssue? locationIssue;
  int _locationRevision = 0;
  final Future<void> Function(bool) schedule;
  Settings settings = const Settings();
  Forecast? forecast;
  String? error, backgroundError;
  bool loading = true, initialized = false;
  int _revision = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    settings = await repository.settings();
    forecast = await repository.cached(settings);
    initialized = true;
    _notify();
    await _schedule();
    await refresh();
  }

  Future<void> _schedule() async {
    try {
      await schedule(settings.hourly);
      backgroundError = null;
    } catch (_) {
      backgroundError =
          'Background checks could not be scheduled. Open the app to refresh.';
    }
    _notify();
  }

  Future<void> refresh({bool force = false}) async {
    final revision = ++_revision;
    final selected = settings;
    loading = true;
    error = null;
    _notify();
    try {
      final value = await repository.refresh(selected, force: force);
      if (revision != _revision || _disposed) return;
      forecast = value;
      await _publish(selected, value);
    } catch (_) {
      if (revision != _revision || _disposed) return;
      error =
          forecast == null
              ? 'Couldn’t get the weather. Check your connection or try another source.'
              : 'Couldn’t refresh. Showing your saved forecast.';
    } finally {
      if (revision == _revision) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> update(Settings value) async {
    if (value.place.id != settings.place.id ||
        value.place.isCurrentLocation != settings.place.isCurrentLocation) {
      ++_locationRevision;
      locationError = null;
      locationIssue = null;
    }
    final weatherChanged = value.cacheKey != settings.cacheKey;
    final revision = ++_revision;
    settings = value;
    error = null;
    await repository.saveSettings(value);
    if (revision != _revision || _disposed) return;
    if (weatherChanged) {
      final cached = await repository.cached(value);
      if (revision != _revision || _disposed) return;
      forecast = cached;
    }
    loading = false;
    _notify();
    // Clear old-city widget data immediately, even when the new city is offline.
    await _publish(value, forecast);
    await _schedule();
    if (revision != _revision || _disposed) return;
    if (weatherChanged || forecast == null) await refresh();
  }

  Future<void> _publish(Settings s, Forecast? value) async {
    try {
      await publish(repository, s, value);
    } catch (_) {
      backgroundError =
          'The widget could not be updated. Your forecast is still available here.';
    }
  }

  Future<bool> useCurrentLocation({bool requestPermission = true}) async {
    if (locating) return false;
    final revision = ++_locationRevision;
    locating = true;
    locationError = null;
    locationIssue = null;
    _notify();
    try {
      final place = await locationLookup.locate(
        requestPermission: requestPermission,
      );
      if (_disposed || revision != _locationRevision) return false;
      await update(settings.copyWith(place: place, source: WeatherSource.auto));
      return true;
    } on LocationFailure catch (failure) {
      if (_disposed || revision != _locationRevision) return false;
      locationError = failure.message;
      locationIssue = failure.issue;
    } catch (_) {
      if (_disposed || revision != _locationRevision) return false;
      locationError =
          'Couldn’t get your location. Your saved area is unchanged.';
      locationIssue = LocationIssue.unavailable;
    } finally {
      locating = false;
      _notify();
    }
    return false;
  }

  Future<void> resume() async {
    await refresh();
    if (!_disposed && settings.place.isCurrentLocation) {
      await useCurrentLocation(requestPermission: false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    repository.close();
    super.dispose();
  }
}
