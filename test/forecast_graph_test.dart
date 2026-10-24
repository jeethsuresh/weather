import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/main.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/ui/forecast_cards.dart';
import 'package:local_weather/ui/forecast_chart_data.dart';
import 'package:local_weather/ui/weather_charts.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'compact_test.dart' show compactController, loadFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  setUpAll(loadFonts);
  final now = DateTime.utc(2026, 10, 18, 23, 30);
  Forecast data({List<HourForecast>? hours, List<DayForecast>? days}) =>
      Forecast(
        source: WeatherSource.canada,
        fetchedAt: now,
        observedAt: now,
        temperature: -2,
        summary: 'Cloudy',
        days:
            days ??
            const [
              DayForecast(
                label: 'Sunday',
                date: '2026-10-18',
                summary: 'Cloudy',
                high: 4,
                low: -5,
              ),
              DayForecast(
                label: 'Monday',
                date: '2026-10-19',
                summary: 'Rain',
                high: 6,
                low: -3,
              ),
            ],
        hours:
            hours ??
            List.generate(
              16,
              (i) => HourForecast(
                time: DateTime.utc(2026, 10, 18, 23).add(Duration(hours: i)),
                temperature: -5 + i.toDouble(),
                summary: 'Cloudy',
                rain: i == 2 ? null : i * 5,
              ),
            ),
      );

  test('daily heading includes weekday and calendar date', () {
    final f = data();
    expect(forecastDayHeading(f.days[1], f, Place.toronto), 'Monday · Oct 19');
    expect(
      todayForecast(f, Place.toronto, DateTime.utc(2026, 10, 19, 5))?.high,
      6,
    );
    expect(
      todayForecast(f, Place.toronto, DateTime.utc(2026, 10, 20, 5)),
      isNull,
    );
  });
  test('main graph spans the next 24 hours across local midnight', () {
    final f = data(
      hours: [
        for (var i = 0; i < 32; i++)
          HourForecast(
            time: DateTime.utc(2026, 10, 18, 23).add(Duration(hours: i)),
            temperature: i.toDouble(),
            summary: 'Sunny',
          ),
      ],
    );
    final range = upcomingChartRange(now);
    final hours = range.hoursFrom(f);
    expect(range.start, now);
    expect(range.end, now.add(const Duration(hours: 24)));
    expect(hours.map((h) => h.time), [
      for (var h = 0; h < 24; h++) DateTime.utc(2026, 10, 19, h),
    ]);
  });
  test('sparse forecasts keep the full 24 hour axis without filling gaps', () {
    final range = upcomingChartRange(now);
    final hours = range.hoursFrom(data());
    expect(range.end.difference(range.start), const Duration(hours: 24));
    expect(hours.last.time.isBefore(range.end), isTrue);
    expect(hours.length, 15);
  });
  test('next 24 hours remain an elapsed day across both DST changes', () {
    for (final at in [
      DateTime.utc(2026, 3, 8, 4),
      DateTime.utc(2026, 11, 1, 4),
    ]) {
      final range = upcomingChartRange(at);
      expect(range.end.difference(range.start), const Duration(hours: 24));
      expect(
        Place.toronto.local(range.start).timeZoneOffset,
        isNot(Place.toronto.local(range.end).timeZoneOffset),
      );
    }
  });
  test(
    'next-hours graph sorts timestamps, limits horizon and preserves gaps and null rain',
    () {
      final f = data(
        hours: [
          HourForecast(
            time: now.add(const Duration(hours: 6)),
            temperature: 0,
            summary: 'Snow',
            rain: null,
          ),
          HourForecast(
            time: now.subtract(const Duration(minutes: 31)),
            temperature: -5,
            summary: 'Snow',
          ),
          HourForecast(
            time: now.add(const Duration(hours: 1)),
            temperature: -2,
            summary: 'Snow',
            rain: 0,
          ),
          HourForecast(
            time: now.add(const Duration(hours: 25)),
            temperature: 10,
            summary: 'Sunny',
          ),
        ],
      );
      final hours = upcomingChartHours(f, now);
      expect(hours.length, 2);
      expect(hours.first.rain, 0);
      expect(hours.last.rain, isNull);
      expect(
        hours.last.time.difference(hours.first.time),
        const Duration(hours: 5),
      );
    },
  );
  test(
    'legacy headings use the issue date while unknown dates stay unknown',
    () {
      final f = data();
      const legacy = DayForecast(label: 'Tonight', summary: 'Snow');
      expect(forecastDayHeading(legacy, f, Place.toronto), 'Sunday · Oct 18');
      const unknown = DayForecast(label: 'Later', summary: 'Cloudy');
      expect(forecastDayDate(unknown, f, Place.toronto), isNull);
    },
  );
  test('DST repeated local hours remain distinct absolute chart samples', () {
    final at = DateTime.utc(2026, 11, 1, 4);
    final f = Forecast(
      source: WeatherSource.nws,
      fetchedAt: at,
      observedAt: at,
      temperature: 2,
      summary: 'Cloudy',
      days: const [],
      hours: [
        for (final hour in [5, 6])
          HourForecast(
            time: DateTime.utc(2026, 11, 1, hour),
            temperature: 2,
            summary: 'Cloudy',
          ),
      ],
    );
    final hours = upcomingChartHours(f, at);
    expect(hours.length, 2);
    expect(Place.toronto.local(hours.first.time).hour, 1);
    expect(Place.toronto.local(hours.last.time).hour, 1);
    expect(
      hours.last.time.difference(hours.first.time),
      const Duration(hours: 1),
    );
  });

  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'hourly pips scroll through each hour with large Fahrenheit text',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final f = data();
      const settings = Settings(fahrenheit: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
              child: HourlyForecastStrip(hours: f.hours, settings: settings),
            ),
          ),
        ),
      );
      expect(find.byType(WeatherChart), findsNothing);
      expect(find.text('23°'), findsOneWidget);
      final first = tester.getRect(
        find.byKey(ValueKey('hour-pip-${f.hours[0].time.toIso8601String()}')),
      );
      final next = tester.getRect(
        find.byKey(ValueKey('hour-pip-${f.hours[1].time.toIso8601String()}')),
      );
      expect(next.left - first.right, closeTo(1, .01));
      final scrollable = find.descendant(
        of: find.byType(HourlyForecastStrip),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('hour-pip-${f.hours.last.time.toIso8601String()}')),
        200,
        scrollable: scrollable,
      );
      expect(find.text('50°'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'main cards flip from temperature to precipitation and retain the face when folded',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final c = compactController();
      await tester.pumpWidget(DaybreakApp(controller: c));
      await tester.pumpAndSettle();
      Finder charts() => find.descendant(
        of: find.byType(CurrentWeatherCard),
        matching: find.byType(WeatherChart),
      );
      expect(
        tester.widget<WeatherChart>(charts()).kind,
        WeatherChartKind.temperature,
      );
      final range = tester.widget<WeatherChart>(charts()).range!;
      expect(range.end.difference(range.start), const Duration(hours: 24));
      await tester.tap(charts());
      await tester.pumpAndSettle();
      expect(
        tester.widget<WeatherChart>(charts()).kind,
        WeatherChartKind.precipitation,
      );
      expect(find.text('Humidity'), findsOneWidget);
      tester.view.physicalSize = const Size(804, 812);
      await tester.pumpAndSettle();
      expect(
        tester.widget<WeatherChart>(charts()).kind,
        WeatherChartKind.precipitation,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'daily forecast is a connected list of thin weather and high low rows',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final f = data();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: DailyForecastList(forecast: f, settings: const Settings()),
            ),
          ),
        ),
      );
      expect(find.byType(WeatherChart), findsNothing);
      expect(find.text('Sun'), findsOneWidget);
      expect(find.text('Oct 18'), findsOneWidget);
      expect(find.text('Cloudy'), findsOneWidget);
      expect(find.text('4°'), findsOneWidget);
      expect(find.text('-5°'), findsOneWidget);
      final first = tester.getRect(
        find.byKey(const ValueKey('forecast-day-0')),
      );
      final next = tester.getRect(find.byKey(const ValueKey('forecast-day-1')));
      expect(first.height, lessThanOrEqualTo(44));
      expect(next.top - first.bottom, closeTo(1, .01));
      expect(
        tester.getSize(find.byType(DailyForecastList)).height,
        lessThan(90),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'thin daily rows fit narrow windows with large text and missing values',
    (tester) async {
      viewport(tester, const Size(320, 844));
      final f = data(
        days: const [
          DayForecast(
            label: 'Monday',
            date: '2026-10-19',
            summary: 'Rain showers changing to thunderstorms',
            high: 110,
            low: -40,
          ),
          DayForecast(
            label: 'Later',
            summary: 'Conditions not reported',
            low: 0,
          ),
        ],
      );
      for (final compact in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(2.5),
                  ),
                  child: DailyForecastList(
                    forecast: f,
                    settings: const Settings(fahrenheit: true),
                    compact: compact,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('230°'), findsOneWidget);
        expect(find.text('-40°'), findsOneWidget);
        expect(find.text('—'), findsOneWidget);
        expect(find.text('32°'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'missing hourly precipitation stays unavailable while zero paints as a real dry forecast',
    (tester) async {
      final f = data();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 240,
              height: 110,
              child: WeatherChart(
                hours: f.hours.where((h) => h.rain == null).toList(),
                settings: const Settings(),
                kind: WeatherChartKind.precipitation,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Hourly precipitation not available'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 240,
              height: 110,
              child: WeatherChart(
                hours: f.hours.take(1).toList(),
                settings: const Settings(),
                kind: WeatherChartKind.precipitation,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Hourly precipitation not available'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing high uses the current card graph in both layouts and units',
    (tester) async {
      final f = data(
        days: const [DayForecast(label: 'Tonight', summary: 'Snow', low: -8)],
        hours: [
          for (final (offset, temperature) in [
            (-1, 20.0),
            (1, -5.0),
            (3, -2.0),
            (6, double.nan),
            (25, 30.0),
          ])
            HourForecast(
              time: now.add(Duration(hours: offset)),
              temperature: temperature,
              summary: 'Snow',
            ),
        ],
      );
      for (final compact in [false, true]) {
        for (final fahrenheit in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: CurrentWeatherCard(
                  forecast: f,
                  settings: Settings(fahrenheit: fahrenheit),
                  now: now,
                  height: compact ? 200 : 300,
                  compact: compact,
                ),
              ),
            ),
          );
          expect(
            find.descendant(
              of: find.byType(TemperatureRangeChart),
              matching: find.text(fahrenheit ? '28°' : '-2°'),
            ),
            findsOneWidget,
          );
          final chart = tester.widget<WeatherChart>(find.byType(WeatherChart));
          expect(chart.high, -2);
          expect(chart.low, -8);
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  testWidgets('reported and missing highs handle zero and absent graph data', (
    tester,
  ) async {
    for (final (reported, temperatures, expected) in [
      (0.0, [-5.0, 2.0], 0.0),
      (null, [-5.0, 0.0], 0.0),
      (null, <double>[], null),
      (null, [double.nan, double.infinity], null),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 80,
              child: TemperatureRangeChart(
                hours: [
                  for (var i = 0; i < temperatures.length; i++)
                    HourForecast(
                      time: now.add(Duration(hours: i)),
                      temperature: temperatures[i],
                      summary: 'Cloudy',
                    ),
                ],
                settings: const Settings(),
                high: reported,
                low: -8,
              ),
            ),
          ),
        ),
      );
      expect(find.text(const Settings().temperature(expected)), findsOneWidget);
      expect(
        tester.widget<WeatherChart>(find.byType(WeatherChart)).high,
        expected,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('flat freezing temperature chart paints in either unit', (
    tester,
  ) async {
    final f = data(
      hours: [
        for (var i = 0; i < 6; i++)
          HourForecast(
            time: now.add(Duration(hours: i)),
            temperature: 0,
            summary: 'Snow',
          ),
      ],
    );
    for (final fahrenheit in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 230,
              height: 80,
              child: TemperatureRangeChart(
                hours: f.hours,
                settings: Settings(fahrenheit: fahrenheit),
                high: 0,
                low: 0,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('main graph card previews', (tester) async {
    viewport(tester, const Size(390, 844));
    final c = compactController();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: DaybreakApp(controller: c)),
    );
    await tester.pumpAndSettle();
    Future<void> save(String name) async => tester.runAsync(() async {
      final render =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await save('main-graphs-front');
    await tester.tap(find.byKey(const ValueKey('flip-current')));
    await tester.pumpAndSettle();
    await save('main-graphs-back');
    await tester.ensureVisible(find.byType(DailyForecastList));
    await tester.pumpAndSettle();
    await save('main-dense-forecast');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
