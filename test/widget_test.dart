import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/background.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/repository.dart';
import 'package:local_weather/weather_api.dart';
import 'package:local_weather/widget_data.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  final now = DateTime.utc(2026, 10, 18, 18, 40);
  Forecast forecast({double? wind = 32.2, double? rain = 60}) => Forecast(
    source: WeatherSource.canada,
    fetchedAt: now,
    observedAt: now,
    temperature: -12,
    summary: 'Snow',
    wind: wind,
    days: const [
      DayForecast(
        label: 'Today',
        date: '2026-10-18',
        summary: 'Snow',
        high: 3,
        low: -17,
      ),
      DayForecast(
        label: 'Monday',
        date: '2026-10-19',
        summary: 'Cloudy',
        high: 5,
        low: -8,
      ),
    ],
    hours: [
      HourForecast(
        time: now.subtract(const Duration(hours: 2)),
        temperature: 0,
        summary: 'Sunny',
        rain: 0,
      ),
      HourForecast(
        time: now.add(const Duration(minutes: 20)),
        temperature: -11,
        summary: 'Snow',
        rain: rain,
      ),
    ],
  );

  test('widget snapshot converts units and identifies precipitation hour', () {
    final celsius = widgetPayload(const Settings(), forecast(), now);
    expect(celsius['temperature'], '-12°');
    expect(celsius['wind'], '32 km/h');
    expect(celsius['kind'], 'snow');
    expect(celsius['hours'], [
      {
        'timestamp':
            now.add(const Duration(minutes: 20)).millisecondsSinceEpoch,
        'time': '3pm',
        'temperature': -11.0,
        'temperatureText': '-11°',
        'rain': '60%',
      },
    ]);
    final imperial = widgetPayload(
      const Settings(fahrenheit: true),
      forecast(),
      now,
    );
    expect(imperial['temperature'], '10°');
    expect(imperial['wind'], '20 mph');
    expect(
      (imperial['hours'] as List).single['temperature'],
      closeTo(12.2, .001),
    );
    expect((imperial['hours'] as List).single['temperatureText'], '12°');
    expect((imperial['hours'] as List).single['rain'], '60%');
    expect(celsius['days'], [
      {'date': '2026-10-18', 'high': '3°', 'low': '-17°'},
      {'date': '2026-10-19', 'high': '5°', 'low': '-8°'},
    ]);
    expect((imperial['days'] as List).first, {
      'date': '2026-10-18',
      'high': '37°',
      'low': '1°',
    });
    expect(celsius['timeZone'], 'America/Toronto');
  });

  test('missing wind and probability stay unavailable, zero stays zero', () {
    final missing = widgetPayload(
      const Settings(),
      forecast(wind: null, rain: null),
      now,
    );
    expect(missing['wind'], '—');
    expect((missing['hours'] as List).single['rain'], isNull);
    final zero = widgetPayload(
      const Settings(),
      forecast(wind: 0, rain: 0),
      now,
    );
    expect(zero['wind'], '0 km/h');
    expect((zero['hours'] as List).single['rain'], '0%');
  });

  test('old hours disappear without changing original weather timestamps', () {
    final old = widgetPayload(
      const Settings(),
      forecast(),
      now.add(const Duration(hours: 4)),
    );
    expect(old['hours'], isEmpty);
    expect(old['fetchedAt'], now.millisecondsSinceEpoch);
    expect(old['observedAt'], now.millisecondsSinceEpoch);
  });

  test('clearing a location clears measurements from every widget', () {
    final empty = widgetPayload(const Settings(), null, now);
    expect(empty['temperature'], '—');
    expect(empty['wind'], '—');
    expect(empty['summary'], 'Tap to set up');
    expect(empty['hours'], isEmpty);
    expect(empty['days'], isEmpty);
    expect(empty['fetchedAt'], 0);
  });

  test(
    'dated ranges survive midnight and never relabel yesterday as today',
    () {
      final midnight = DateTime.utc(2026, 10, 19, 4, 15);
      final payload = widgetPayload(const Settings(), forecast(), midnight);
      expect((payload['days'] as List).first['date'], '2026-10-18');
      expect((payload['days'] as List)[1]['date'], '2026-10-19');
      expect(payload['timeZone'], 'America/Toronto');
    },
  );

  test(
    'legacy ranges only infer issue day and missing extrema remain unavailable',
    () {
      final f = Forecast.fromJson(
        forecast().toJson()
          ..['days'] = [
            {'label': 'Today', 'summary': 'Sunny', 'low': -4},
            {'label': 'Monday', 'summary': 'Sunny', 'high': 8, 'low': 2},
          ],
      );
      final payload = widgetPayload(const Settings(), f, now);
      expect((payload['days'] as List).first, {
        'date': '2026-10-18',
        'high': '—',
        'low': '-4°',
      });
      expect((payload['days'] as List)[1]['date'], isNull);
    },
  );

  test(
    'hourly graph preserves chronological temperatures through a flat or freezing trend',
    () {
      final j = forecast().toJson();
      j['hours'] = List.generate(
        13,
        (index) =>
            HourForecast(
              time: now.add(Duration(hours: index)),
              temperature: index < 4 ? -2 : 0,
              summary: 'Cloudy',
            ).toJson(),
      );
      final data = widgetPayload(const Settings(), Forecast.fromJson(j), now);
      final hours = data['hours'] as List;
      expect(hours.length, 13);
      expect(hours.take(4).map((h) => h['temperature']), everyElement(-2));
      expect(hours.last['temperature'], 0);
      expect(hours.last['temperatureText'], '0°');
      expect(
        hours.map((h) => h['timestamp']),
        orderedEquals(
          List.generate(
            13,
            (i) => now.add(Duration(hours: i)).millisecondsSinceEpoch,
          ),
        ),
      );
    },
  );

  test(
    'widget alerts preserve official colours and survive cache round trips',
    () {
      final alerts = [
        WeatherAlert(
          'Wind warning',
          'Take care',
          type: 'warning',
          colour: 'yellow',
          expires: now.add(const Duration(hours: 1)),
        ),
        WeatherAlert('Strong wind', 'Take care', type: 'Wind Advisory'),
        WeatherAlert('Snow watch', 'Take care'),
        WeatherAlert('Expired warning', 'Old', expires: now),
      ];
      final f = Forecast.fromJson(
        forecast().toJson()
          ..['alerts'] = alerts.map((alert) => alert.toJson()).toList(),
      );
      final data = widgetPayload(const Settings(), f, now);
      expect((data['alerts'] as List).map((alert) => alert['colour']), [
        'yellow',
        'yellow',
        'orange',
      ]);
      expect((data['alerts'] as List).map((alert) => alert['event']), [
        'warning',
        'Wind Advisory',
        '',
      ]);
      expect(
        (data['alerts'] as List).first['expires'],
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
      expect((data['alerts'] as List)[1]['title'], 'Strong wind');
      expect(widgetPayload(const Settings(), null, now)['alerts'], isEmpty);
      expect(
        widgetPayload(const Settings(), forecast(), now)['alerts'],
        isEmpty,
      );
    },
  );

  test('legacy alerts infer their type and unknown alerts remain visible', () {
    for (final (title, colour) in [
      ('Snow warning', 'red'),
      ('Thunderstorm watch', 'orange'),
      ('Wind advisory', 'yellow'),
      ('Special weather statement', 'blue'),
    ]) {
      final old = WeatherAlert.fromJson({'title': title, 'detail': 'Details'});
      final alert = widgetAdvisory(old);
      expect(alert['event'], '');
      expect(alert['colour'], colour);
      expect(alert['expires'], isNull);
    }
  });

  final calls = <MethodCall>[];
  const channel = MethodChannel('home_widget');
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  WeatherRepository repository() => WeatherRepository(
    MemoryStore(),
    WeatherApi(StubTransport((_) async => fixture('canada')), MemoryStore()),
  );

  test(
    'publishing saves once then refreshes all three native providers',
    () async {
      final repo = repository();
      await publishWidget(repo, const Settings(), forecast());
      expect(calls.map((call) => call.method), [
        'saveWidgetData',
        'updateWidget',
        'updateWidget',
        'updateWidget',
      ]);
      expect(
        calls.skip(1).map((call) => call.arguments['android']),
        widgetProviders,
      );
      final saved = jsonDecode(calls.first.arguments['data'] as String);
      expect(saved['temperature'], '-12°');
      expect(saved['wind'], '32 km/h');
    },
  );

  test(
    'late refresh cannot republish previous units or previous city',
    () async {
      final repo = repository();
      await repo.saveSettings(const Settings(fahrenheit: true));
      await publishWidget(repo, const Settings(), forecast());
      expect(calls, isEmpty);
      await repo.saveSettings(const Settings());
      await publishWidget(
        repo,
        const Settings(
          place: Place(
            name: 'Other',
            region: '',
            country: 'US',
            latitude: 40,
            longitude: -75,
            timezone: 'America/New_York',
          ),
        ),
        forecast(),
      );
      expect(calls, isEmpty);
    },
  );
}
