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
    days: [],
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
    expect(imperial['hours'], celsius['hours']);
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
    expect(empty['fetchedAt'], 0);
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
