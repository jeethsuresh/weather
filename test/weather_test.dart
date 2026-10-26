import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/controller.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/repository.dart';
import 'package:local_weather/weather_api.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'support.dart';

void main() {
  tzdata.initializeTimeZones();
  final now = DateTime.utc(2026, 10, 18, 16, 30);
  const ny = Place(
    name: 'New York',
    latitude: 40.7128,
    longitude: -74.006,
    country: 'US',
    timezone: 'America/New_York',
  );

  test(
    'Environment Canada real response: units, missing feels-like, periods and timestamps',
    () {
      final f = parseCanada(fixture('canada'), now);
      expect(f.source, WeatherSource.canada);
      expect(f.temperature, 14.4);
      expect(
        f.feelsLike,
        isNull,
      ); // warm-day windChill=-3 is outside its valid range
      expect(f.humidity, 40);
      expect(f.hours.first.rain, 0);
      expect(f.hours.first.wind, 20);
      expect(f.hours.first.time, DateTime.utc(2026, 10, 18, 17));
      expect(f.days.first.high, isNotNull);
      expect(f.days.first.low, isNotNull); // Today and Tonight are one row
      expect(f.observedAt, DateTime.utc(2026, 10, 18, 16));
    },
  );

  test(
    'Canadian alerts retain the official colour and type for the widget',
    () {
      final j = fixture('canada');
      j['properties']['warnings'] = [
        {
          'description': {'en': 'Wind warning'},
          'type': {'en': 'warning'},
          'alertColourLevel': {'en': 'orange'},
          'expiryTime': {'en': '2026-10-18T22:00:00Z'},
        },
      ];
      final alert = parseCanada(j, now).alerts.single;
      expect(alert.type, 'warning');
      expect(alert.colour, 'orange');
      expect(WeatherAlert.fromJson(alert.toJson()).colour, 'orange');
    },
  );

  test(
    'missing Canadian observation uses the matching hourly forecast, not an old observation timestamp',
    () {
      final j = fixture('canada');
      j['properties']['currentConditions'].remove('temperature');
      final f = parseCanada(j, now);
      expect(f.temperature, f.hours.first.temperature);
      expect(f.observedAt, f.hours.first.time);
      expect(f.notice, contains('hourly forecast'));
    },
  );

  test(
    'unknown or missing weather fields do not become sunny or zero percent rain',
    () {
      final j = fixture('canada');
      j['properties']['currentConditions'].remove('condition');
      for (final h
          in j['properties']['hourlyForecastGroup']['hourlyForecasts']) {
        h.remove('condition');
        h.remove('lop');
      }
      final f = parseCanada(j, now);
      expect(f.hours.first.rain, isNull);
      expect(conditionKind(f.summary), 'unknown');
    },
  );

  test(
    'Open-Meteo epoch times stay absolute, sunrise and daily labels use city timezone',
    () {
      final j = fixture('open_meteo');
      final f = parseOpenMeteo(j, Place.toronto, now);
      expect(f.hours.length, 168);
      expect(f.days.length, 7);
      expect(f.hours.first.time.isUtc, isTrue);
      expect(f.days.first.label, 'Sunday');
      expect(Place.toronto.local(f.sunrise!).hour, inInclusiveRange(6, 8));
      expect(f.temperature, j['current']['temperature_2m']);
      final roundTrip = Forecast.fromJson(jsonDecode(jsonEncode(f.toJson())));
      expect(roundTrip.sunset, f.sunset);
      expect(roundTrip.hours[12].time, f.hours[12].time);
    },
  );

  test(
    'NWS SI response: Celsius, wind, combined days and actual active alerts',
    () {
      final f = parseNws(
        fixture('nws_hourly'),
        fixture('nws_daily'),
        {
          'features': [
            {
              'properties': {
                'status': 'Actual',
                'event': 'Wind advisory',
                'headline': 'Strong wind',
                'description': 'Use care outdoors.',
                'expires': '2026-10-18T22:00:00Z',
              },
            },
            {
              'properties': {'status': 'Test', 'event': 'Test warning'},
            },
            {
              'properties': {
                'status': 'Actual',
                'event': 'Expired',
                'expires': '2026-10-17T22:00:00Z',
              },
            },
          ],
        },
        ny,
        now,
      );
      expect(f.source, WeatherSource.nws);
      expect(f.hours, isNotEmpty);
      expect(
        f.temperature,
        number(
          fixture('nws_hourly')['properties']['periods'][0]['temperature'],
        ),
      );
      expect(f.alerts.length, 1);
      expect(f.alerts.first.title, 'Strong wind');
      expect(f.alerts.first.type, 'Wind advisory');
      expect(f.days.first.low, isNotNull);
    },
  );

  test('NWS Fahrenheit and mph convert to canonical metric values', () {
    final j = fixture('nws_hourly');
    j['properties']['periods'] = [
      {
        'temperature': 68,
        'temperatureUnit': 'F',
        'windSpeed': '10 mph',
        'startTime': '2026-10-18T13:00:00-04:00',
        'shortForecast': 'Sunny',
        'probabilityOfPrecipitation': {'value': null},
      },
    ];
    final f = parseNws(j, fixture('nws_daily'), {'features': []}, ny, now);
    expect(f.temperature, closeTo(20, .001));
    expect(f.wind, closeTo(16.09344, .001));
    expect(f.hours.first.rain, isNull);
  });

  test(
    'Automatic Canada fallback is visible and requests never require credentials',
    () async {
      final store = MemoryStore();
      final http = StubTransport((uri) async {
        if (uri.host == 'api.weather.gc.ca') {
          throw const WeatherException('offline');
        }
        return fixture('open_meteo');
      });
      final api = WeatherApi(http, store, clock: () => now);
      final f = await api.fetch(const Settings());
      expect(f.source, WeatherSource.openMeteo);
      expect(f.notice, contains('national service is unavailable'));
      expect(http.calls.last.host, 'api.open-meteo.com');
      expect(
        http.calls.every((u) => !u.queryParameters.containsKey('apikey')),
        isTrue,
      );
      expect(http.calls.every((u) => u.scheme == 'https'), isTrue);
    },
  );

  test(
    'Automatic US uses national hourly/daily links and filters point alerts',
    () async {
      final http = StubTransport((uri) async {
        if (uri.path.startsWith('/points/')) return fixture('nws_points');
        if (uri.path.endsWith('/hourly')) return fixture('nws_hourly');
        if (uri.path.startsWith('/alerts')) return {'features': []};
        return fixture('nws_daily');
      });
      final f = await WeatherApi(
        http,
        MemoryStore(),
        clock: () => now,
      ).fetch(const Settings(place: ny));
      expect(f.source, WeatherSource.nws);
      expect(http.calls.every((u) => u.host == 'api.weather.gov'), isTrue);
      expect(
        http.calls
            .where((u) => u.path.contains('forecast'))
            .every((u) => u.queryParameters['units'] == 'si'),
        isTrue,
      );
    },
  );

  test(
    'Nearby Canadian discovery chooses nearest station and persists its identifier',
    () async {
      const p = Place(
        name: 'Test',
        latitude: 43.65,
        longitude: -79.38,
        country: 'CA',
        timezone: 'America/Toronto',
      );
      final store = MemoryStore();
      final near = fixture('canada');
      final far = fixture('canada');
      far['geometry']['coordinates'] = [-79.9, 44.1];
      far['properties']['identifier'] = 'far';
      final http = StubTransport(
        (u) async =>
            u.path.endsWith('/items')
                ? {
                  'features': [far, near],
                }
                : near,
      );
      final api = WeatherApi(http, store, clock: () => now);
      await api.fetch(const Settings(place: p));
      expect(await store.read('canada.site.${p.id}'), 'on-143');
      await api.fetch(const Settings(place: p));
      expect(http.calls.last.path, endsWith('/on-143'));
    },
  );

  test(
    'failed refresh preserves offline cache and its original successful timestamp',
    () async {
      final store = MemoryStore();
      var offline = false;
      var clock = now;
      final http = StubTransport((_) async {
        if (offline) throw const WeatherException('offline');
        return fixture('open_meteo');
      });
      final repo = WeatherRepository(
        store,
        WeatherApi(http, store, clock: () => clock),
      );
      const settings = Settings(source: WeatherSource.openMeteo);
      final first = await repo.refresh(settings);
      offline = true;
      clock = now.add(const Duration(hours: 3));
      await expectLater(
        repo.refresh(settings),
        throwsA(isA<WeatherException>()),
      );
      final saved = await repo.cached(settings);
      expect(saved!.fetchedAt, first.fetchedAt);
      expect(saved.staleAt(clock), isTrue);
      expect(
        await repo.cached(
          const Settings(place: ny, source: WeatherSource.openMeteo),
        ),
        isNull,
      );
    },
  );

  test(
    'fresh cached weather avoids another fetch, manual refresh bypasses it',
    () async {
      final store = MemoryStore();
      final http = StubTransport((_) async => fixture('open_meteo'));
      final repo = WeatherRepository(
        store,
        WeatherApi(http, store, clock: () => now),
      );
      const s = Settings(source: WeatherSource.openMeteo);
      await repo.refresh(s);
      await repo.refresh(s);
      expect(http.calls.length, 1);
      await repo.refresh(s, force: true);
      expect(http.calls.length, 2);
    },
  );

  test(
    'corrupt local data recovers to safe settings and an empty cache',
    () async {
      final store = MemoryStore();
      store.values['settings.v1'] = 'broken';
      store.values[const Settings().cacheKey] = '{"source":"deleted"}';
      final repo = WeatherRepository(
        store,
        WeatherApi(StubTransport((_) async => {}), store),
      );
      expect((await repo.settings()).place.name, 'Toronto');
      expect(await repo.cached(const Settings()), isNull);
    },
  );

  test(
    'changing units during a fetch cannot leave the screen permanently loading',
    () async {
      final store = MemoryStore();
      final delayed = Completer<Json>();
      final http = StubTransport((_) => delayed.future);
      final repo = WeatherRepository(
        store,
        WeatherApi(http, store, clock: () => now),
      );
      final controller = WeatherController(
        repo,
        publish: (_, _, _) async {},
        schedule: (_) async {},
      );
      controller.settings = const Settings(source: WeatherSource.openMeteo);
      controller.forecast = parseOpenMeteo(
        fixture('open_meteo'),
        Place.toronto,
        now,
      );
      final refresh = controller.refresh(force: true);
      await Future<void>.delayed(Duration.zero);
      await controller.update(controller.settings.copyWith(fahrenheit: true));
      delayed.complete(fixture('open_meteo'));
      await refresh;
      expect(controller.loading, isFalse);
      expect(controller.settings.fahrenheit, isTrue);
      controller.dispose();
    },
  );

  test(
    'timezone formatting handles the repeated hour at the daylight saving transition',
    () {
      final first = Place.toronto.local(DateTime.utc(2026, 11, 1, 5, 30));
      final second = Place.toronto.local(DateTime.utc(2026, 11, 1, 6, 30));
      expect(first.hour, 1);
      expect(second.hour, 1);
      expect(first.timeZoneOffset, const Duration(hours: -4));
      expect(second.timeZoneOffset, const Duration(hours: -5));
      expect(const Settings(fahrenheit: true).temperature(20), '68°');
      expect(const Settings(fahrenheit: true).wind(16.09344), '10 mph');
    },
  );
}
