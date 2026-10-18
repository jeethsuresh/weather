import 'dart:async';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'models.dart';
import 'weather_api.dart';

enum LocationIssue { denied, deniedForever, disabled, unavailable }

class LocationFailure implements Exception {
  const LocationFailure(this.issue, this.message);
  final LocationIssue issue;
  final String message;
}

class LocationFix {
  const LocationFix(
    this.latitude,
    this.longitude,
    this.accuracy,
    this.timestamp,
  );
  final double latitude, longitude, accuracy;
  final DateTime timestamp;
}

class LocationArea {
  const LocationArea({
    this.name = 'Current location',
    this.country = '',
    this.region = '',
  });
  final String name, country, region;
}

abstract interface class LocationLookup {
  Future<Place> locate({bool requestPermission = true});
  Future<void> openSettings(LocationIssue issue);
}

/// Platform I/O boundary: the app requests one foreground fix, never a stream.
abstract interface class LocationProbe {
  Future<bool> enabled();
  Future<LocationPermission> permission();
  Future<LocationPermission> requestPermission();
  Future<LocationFix> fix();
  Future<LocationArea> area(LocationFix fix);
  Future<String> deviceTimezone();
  Future<void> openSettings(LocationIssue issue);
}

class DeviceLocationProbe implements LocationProbe {
  @override
  Future<bool> enabled() => Geolocator.isLocationServiceEnabled();
  @override
  Future<LocationPermission> permission() => Geolocator.checkPermission();
  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();
  @override
  Future<LocationFix> fix() async {
    final p = await Geolocator.getCurrentPosition(
      // Use Android's own location manager without asking users to enable
      // Google's optional Location Accuracy/crowdsourcing service.
      locationSettings: AndroidSettings(
        forceLocationManager: true,
        accuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      ),
    );
    return LocationFix(p.latitude, p.longitude, p.accuracy, p.timestamp);
  }

  @override
  Future<LocationArea> area(LocationFix fix) async {
    final p =
        (await placemarkFromCoordinates(
          fix.latitude,
          fix.longitude,
        ).timeout(const Duration(seconds: 6))).firstOrNull;
    final names = [
      p?.subLocality,
      p?.locality,
    ].whereType<String>().where((n) => n.isNotEmpty);
    return LocationArea(
      name: names.firstOrNull ?? 'Current location',
      country: p?.isoCountryCode?.toUpperCase() ?? '',
      region: p?.administrativeArea ?? '',
    );
  }

  @override
  Future<String> deviceTimezone() async =>
      await const MethodChannel(
        'dev.jeeth.daybreak/actions',
      ).invokeMethod<String>('timeZone') ??
      'UTC';
  @override
  Future<void> openSettings(LocationIssue issue) async {
    if (issue == LocationIssue.disabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}

class DeviceLocationLookup implements LocationLookup {
  DeviceLocationLookup(this.api, {LocationProbe? probe})
    : probe = probe ?? DeviceLocationProbe();
  final WeatherApi api;
  final LocationProbe probe;
  @override
  Future<Place> locate({bool requestPermission = true}) async {
    if (!await probe.enabled()) {
      throw const LocationFailure(
        LocationIssue.disabled,
        'Turn on location services, or choose a city below.',
      );
    }
    var permission = await probe.permission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await probe.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        LocationIssue.deniedForever,
        'Location access is off for Daybreak. You can enable it in app settings, or choose a city.',
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const LocationFailure(
        LocationIssue.denied,
        'Location was not shared. You can still choose any city.',
      );
    }
    final LocationFix fix;
    try {
      fix = await probe.fix();
    } on TimeoutException {
      throw const LocationFailure(
        LocationIssue.unavailable,
        'A fresh location was not available. Try again outdoors, or choose a city.',
      );
    }
    if (!fix.latitude.isFinite ||
        !fix.longitude.isFinite ||
        fix.latitude.abs() > 90 ||
        fix.longitude.abs() > 180 ||
        DateTime.now().difference(fix.timestamp) > const Duration(minutes: 5)) {
      throw const LocationFailure(
        LocationIssue.unavailable,
        'Couldn’t get a fresh location. Your saved area is unchanged.',
      );
    }
    var area = const LocationArea();
    try {
      area = await probe.area(fix);
    } catch (_) {}
    // Resolve the timezone at the actual fix, including when crossing timezones.
    // If lookup is offline, the device timezone is still useful for cached data.
    String timezone;
    try {
      timezone = await api.timezoneAt(fix.latitude, fix.longitude);
    } catch (_) {
      try {
        timezone = await probe.deviceTimezone();
      } catch (_) {
        timezone = 'UTC';
      }
    }
    return Place(
      name: area.name,
      latitude: fix.latitude,
      longitude: fix.longitude,
      country: area.country,
      region: area.region,
      timezone: timezone,
      isCurrentLocation: true,
      accuracyMeters:
          fix.accuracy.isFinite && fix.accuracy >= 0 ? fix.accuracy : null,
    );
  }

  @override
  Future<void> openSettings(LocationIssue issue) => probe.openSettings(issue);
}
