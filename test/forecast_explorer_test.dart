import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/ui/forecast_explorer.dart';
import 'package:local_weather/ui/forecast_cards.dart';
import 'package:local_weather/ui/weather_charts.dart';
import 'package:local_weather/ui/flip_weather_card.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'compact_test.dart' show loadFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  setUpAll(loadFonts);
  final now = DateTime.utc(2026, 11, 17, 12);
  final forecast = Forecast(
    source: WeatherSource.canada,
    fetchedAt: now,
    observedAt: now,
    temperature: 4,
    summary: 'Clear',
    wind: 11,
    humidity: 55,
    feelsLike: 2,
    days: const [],
    hours: [
      HourForecast(time: now, temperature: 4, summary: 'Clear', rain: 0),
      HourForecast(
        time: now.add(const Duration(hours: 1)),
        temperature: 6,
        summary: 'Cloudy',
      ),
      HourForecast(
        time: now.add(const Duration(hours: 4)),
        temperature: 9,
        summary: 'Rain',
        rain: 80,
      ),
    ],
  );
  late ForecastSelectionController selection;
  setUp(() => selection = ForecastSelectionController());
  tearDown(() => selection.dispose());
  Widget scene({
    bool compact = false,
    bool reduced = false,
    double scale = 1,
    Settings settings = const Settings(),
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduced,
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              CurrentWeatherCard(
                key: const ValueKey('hero'),
                forecast: forecast,
                settings: settings,
                now: now,
                height: 300 * scale,
                compact: compact,
                selection: selection,
              ),
              ForecastExplorer(
                forecast: forecast,
                settings: settings,
                now: now,
                compact: compact,
                selection: selection,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'one hero transforms into a real hour; missing metrics stay unavailable; Now resets',
    (tester) async {
      await tester.pumpWidget(scene());
      expect(find.byType(WeatherChart), findsOneWidget);
      expect(find.textContaining('RIGHT NOW'), findsOneWidget);
      final currentSky =
          tester
              .widget<FlipWeatherCard>(find.byType(FlipWeatherCard))
              .background;
      await tester.tap(
        find.byKey(
          ValueKey('hour-pip-${forecast.hours[1].time.toIso8601String()}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('FORECAST ·'), findsOneWidget);
      expect(find.text('— rain chance'), findsOneWidget);
      expect(
        tester.widget<FlipWeatherCard>(find.byType(FlipWeatherCard)).background,
        isNot(currentSky),
      );
      final hero = find.byKey(const ValueKey('hero'));
      expect(
        find.descendant(of: hero, matching: find.text('6°')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: hero, matching: find.text('Cloudy')),
        findsOneWidget,
      );
      expect(find.byType(WeatherChart), findsOneWidget);
      expect(
        find.byKey(const ValueKey('forecast-explorer-chart')),
        findsNothing,
      );
      // Flip from the header, not the interactive chart.
      await tester.tap(find.textContaining('FORECAST ·'));
      await tester.pumpAndSettle();
      expect(find.byType(WeatherChart), findsOneWidget);
      expect(find.text('Not reported'), findsNWidgets(2));
      expect(find.text('Feels like'), findsNothing);
      expect(find.text('11 km/h'), findsNothing);
      await tester.tap(find.text('Now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('RIGHT NOW'), findsOneWidget);
      expect(find.text('11 km/h'), findsOneWidget);
    },
  );

  testWidgets(
    'original chart scrub and keyboard synchronize the strip, preserve gaps and fold state',
    (tester) async {
      await tester.pumpWidget(scene());
      final chart = find.byKey(const ValueKey('hero-temperature-chart'));
      await tester.drag(chart, const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(selection.time, forecast.hours.last.time);
      Focus.of(tester.element(chart)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(selection.time, forecast.hours[1].time);
      await tester.pumpWidget(scene(compact: true, reduced: true));
      expect(find.text('— rain chance'), findsOneWidget);
      expect(find.byType(WeatherChart), findsOneWidget);
      await tester.pumpWidget(
        scene(
          settings: const Settings(
            place: Place(
              name: 'Other',
              latitude: 20,
              longitude: 20,
              country: '',
              timezone: 'UTC',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('RIGHT NOW'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact large text remains scrollable without adding a second plot',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(scene(compact: true, reduced: true, scale: 2.5));
      await tester.pumpAndSettle();
      expect(find.byType(WeatherChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
