import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_weather/controller.dart';
import 'package:local_weather/location.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/repository.dart';
import 'package:local_weather/weather_api.dart';
import 'support.dart';

class Probe implements LocationProbe {
  bool service = true;
  LocationPermission access = LocationPermission.denied;
  LocationPermission requested = LocationPermission.whileInUse;
  int requests = 0, fixes = 0;
  bool reverseFails = false;
  LocationFix position = LocationFix(43.671234, -79.381234, 8, DateTime.now());
  @override
  Future<bool> enabled() async => service;
  @override
  Future<LocationPermission> permission() async => access;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return requested;
  }

  @override
  Future<LocationFix> fix() async {
    fixes++;
    return position;
  }

  @override
  Future<LocationArea> area(LocationFix fix) async {
    if (reverseFails) throw Exception('geocoder unavailable');
    return const LocationArea(
      name: 'Yorkville',
      country: 'CA',
      region: 'Ontario',
    );
  }

  @override
  Future<String> deviceTimezone() async => 'America/Vancouver';
  @override
  Future<void> openSettings(LocationIssue issue) async {}
}

class Lookup implements LocationLookup {
  Lookup(this.result);
  final Future<Place> result;
  @override
  Future<Place> locate({bool requestPermission = true}) => result;
  @override
  Future<void> openSettings(LocationIssue issue) async {}
}

void main() {
  DeviceLocationLookup lookup(Probe probe, {bool offline = false}) =>
      DeviceLocationLookup(
        WeatherApi(
          StubTransport((_) async {
            if (offline) throw Exception('offline');
            return {'timezone': 'America/Toronto'};
          }),
          MemoryStore(),
        ),
        probe: probe,
      );
  test(
    'foreground location requests permission once and preserves the actual coordinates',
    () async {
      final p = Probe();
      final place = await lookup(p).locate();
      expect(p.requests, 1);
      expect(p.fixes, 1);
      expect(place.latitude, 43.671234);
      expect(place.longitude, -79.381234);
      expect(place.name, 'Yorkville');
      expect(place.country, 'CA');
      expect(place.timezone, 'America/Toronto');
      expect(place.isCurrentLocation, isTrue);
      expect(place.accuracyMeters, 8);
      final saved = Place.fromJson(jsonDecode(jsonEncode(place.toJson())));
      expect(saved.latitude, place.latitude);
      expect(saved.accuracyMeters, 8);
      expect(saved.isCurrentLocation, isTrue);
    },
  );
  test('denying location never obtains a fix', () async {
    final p = Probe()..requested = LocationPermission.denied;
    await expectLater(
      lookup(p).locate(),
      throwsA(
        isA<LocationFailure>().having(
          (f) => f.issue,
          'issue',
          LocationIssue.denied,
        ),
      ),
    );
    expect(p.fixes, 0);
  });
  test(
    'permanent denial offers settings without requesting permission again',
    () async {
      final p = Probe()..access = LocationPermission.deniedForever;
      await expectLater(
        lookup(p).locate(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.issue,
            'issue',
            LocationIssue.deniedForever,
          ),
        ),
      );
      expect(p.requests, 0);
      expect(p.fixes, 0);
    },
  );
  test(
    'disabled device location is distinct from denied app permission',
    () async {
      final p = Probe()..service = false;
      await expectLater(
        lookup(p).locate(),
        throwsA(
          isA<LocationFailure>().having(
            (f) => f.issue,
            'issue',
            LocationIssue.disabled,
          ),
        ),
      );
      expect(p.requests, 0);
      expect(p.fixes, 0);
    },
  );
  test('resuming never opens another permission prompt', () async {
    final p = Probe();
    await expectLater(
      lookup(p).locate(requestPermission: false),
      throwsA(isA<LocationFailure>()),
    );
    expect(p.requests, 0);
    expect(p.fixes, 0);
  });
  test('approximate access is accepted and its accuracy is retained', () async {
    final p =
        Probe()
          ..access = LocationPermission.whileInUse
          ..position = LocationFix(43.67, -79.38, 1500, DateTime.now());
    final place = await lookup(p).locate();
    expect(place.accuracyMeters, 1500);
    expect(p.requests, 0);
  });
  test('stale position does not silently stand in for a fresh fix', () async {
    final p =
        Probe()
          ..position = LocationFix(
            43.67,
            -79.38,
            20,
            DateTime.now().subtract(const Duration(hours: 1)),
          );
    await expectLater(
      lookup(p).locate(),
      throwsA(
        isA<LocationFailure>().having(
          (f) => f.issue,
          'issue',
          LocationIssue.unavailable,
        ),
      ),
    );
  });
  test(
    'offline timezone and unavailable geocoder preserve fix with safe global fallback',
    () async {
      final p = Probe()..reverseFails = true;
      final place = await lookup(p, offline: true).locate();
      expect(place.country, '');
      expect(place.name, 'Current location');
      expect(place.timezone, 'America/Vancouver');
      expect(place.latitude, 43.671234);
    },
  );
  test(
    'late GPS result cannot replace a manual city picked while locating',
    () async {
      final completer = Completer<Place>();
      final store = MemoryStore();
      final repository = WeatherRepository(
        store,
        WeatherApi(StubTransport((_) async => fixture('canada')), store),
      );
      final c = WeatherController(
        repository,
        publish: (_, _, _) async {},
        schedule: (_) async {},
        locationLookup: Lookup(completer.future),
      );
      final pending = c.useCurrentLocation();
      const manual = Place(
        name: 'Manual city',
        latitude: 43.66,
        longitude: -79.4,
        country: 'CA',
        timezone: 'America/Toronto',
        canadaSite: 'on-143',
      );
      await c.update(c.settings.copyWith(place: manual));
      completer.complete(
        const Place(
          name: 'GPS fix',
          latitude: 43.67,
          longitude: -79.38,
          country: 'CA',
          timezone: 'America/Toronto',
          isCurrentLocation: true,
        ),
      );
      expect(await pending, isFalse);
      expect(c.settings.place.name, 'Manual city');
      expect(c.locating, isFalse);
      expect((await repository.settings()).place.name, 'Manual city');
      c.dispose();
    },
  );
  test(
    'permission failure leaves both saved area and cached forecast intact',
    () async {
      final store = MemoryStore();
      final repository = WeatherRepository(
        store,
        WeatherApi(StubTransport((_) async => fixture('canada')), store),
      );
      final denied = Completer<Place>();
      final c = WeatherController(
        repository,
        publish: (_, _, _) async {},
        schedule: (_) async {},
        locationLookup: Lookup(denied.future),
      );
      await repository.saveSettings(const Settings());
      await repository.refresh(const Settings());
      final attempt = c.useCurrentLocation();
      denied.completeError(
        const LocationFailure(LocationIssue.denied, 'Not shared'),
      );
      expect(await attempt, isFalse);
      expect(c.settings.place.id, Place.toronto.id);
      expect(await repository.cached(const Settings()), isNotNull);
      expect(c.locationIssue, LocationIssue.denied);
      c.dispose();
    },
  );
}
