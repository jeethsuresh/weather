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
  Forecast data({List<HourForecast>? hours}) => Forecast(
    source: WeatherSource.canada,
    fetchedAt: now,
    observedAt: now,
    temperature: -2,
    summary: 'Cloudy',
    days: const [
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
  test(
    'daily graph assigns hours by location date, even after UTC midnight',
    () {
      final f = data();
      final today = chartHoursForDay(f, f.days[0], Place.toronto, now);
      expect(today.map((h) => h.time), [
        for (var h = 0; h < 4; h++) DateTime.utc(2026, 10, 19, h),
      ]);
      expect(
        chartHoursForDay(f, f.days[1], Place.toronto, now).first.time,
        DateTime.utc(2026, 10, 19, 4),
      );
    },
  );
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
            time: now.add(const Duration(hours: 13)),
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
      expect(highestHour(hours), 0);
      expect(lowestHour(hours), -2);
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
      expect(chartHoursForDay(f, unknown, Place.toronto, now), isEmpty);
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
    'daily graph sits between high and low, with precipitation on the back',
    (tester) async {
      viewport(tester, const Size(390, 844));
      final c = compactController();
      await tester.pumpWidget(DaybreakApp(controller: c));
      await tester.pumpAndSettle();
      final card = find.byType(DailyWeatherCard).first;
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      final high = find.descendant(of: card, matching: find.text('High'));
      final low = find.descendant(of: card, matching: find.text('Low'));
      final chart = find.descendant(
        of: card,
        matching: find.byType(WeatherChart),
      );
      expect(
        tester.getRect(chart).left,
        greaterThan(tester.getRect(high).right),
      );
      expect(tester.getRect(chart).right, lessThan(tester.getRect(low).left));
      final f = c.forecast!;
      expect(
        find.text(
          forecastDayHeading(f.days.first, f, c.settings.place).toUpperCase(),
        ),
        findsOneWidget,
      );
      await tester.tap(chart);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WeatherChart>(
              find.descendant(of: card, matching: find.byType(WeatherChart)),
            )
            .kind,
        WeatherChartKind.precipitation,
      );
      expect(find.text('Peak wind'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
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
    await tester.ensureVisible(find.byType(DailyWeatherCard).first);
    await tester.pumpAndSettle();
    await save('main-days-graphs-front');
    await tester.tap(find.byKey(const ValueKey('flip-day-0')));
    await tester.pumpAndSettle();
    await save('main-days-graphs-back');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
