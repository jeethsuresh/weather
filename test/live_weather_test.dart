import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/weather_api.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'support.dart';

/// Explicit opt-in: ordinary tests never depend on network availability.
void main() {
  const enabled = bool.fromEnvironment('LIVE_WEATHER');
  setUpAll(() {
    tzdata.initializeTimeZones();
    if (enabled) HttpOverrides.global = null;
  });
  const ny = Place(
    name: 'New York',
    latitude: 40.7128,
    longitude: -74.006,
    country: 'US',
    timezone: 'America/New_York',
  );
  for (final s in [
    const Settings(source: WeatherSource.canada),
    const Settings(place: ny, source: WeatherSource.nws),
    const Settings(source: WeatherSource.openMeteo),
  ]) {
    test(
      'live ${s.source.label} provides current temperature and future hours',
      () async {
        final transport = HttpTransport();
        try {
          final f = await WeatherApi(transport, MemoryStore()).fetch(s);
          expect(f.source, s.source);
          expect(f.temperature.isFinite, isTrue);
          expect(f.upcoming(DateTime.now()), isNotEmpty);
          expect(f.days, isNotEmpty);
          expect(
            f.observedAt.isAfter(
              DateTime.now().subtract(const Duration(hours: 6)),
            ),
            isTrue,
          );
        } finally {
          transport.close();
        }
      },
      skip: !enabled,
      timeout: const Timeout(Duration(seconds: 90)),
    );
  }
  test('live geocoding resolves city and timezone', () async {
    final transport = HttpTransport();
    try {
      final places = await WeatherApi(
        transport,
        MemoryStore(),
      ).search('Ottawa');
      expect(
        places.any((p) => p.country == 'CA' && p.timezone == 'America/Toronto'),
        isTrue,
      );
    } finally {
      transport.close();
    }
  }, skip: !enabled);
}
