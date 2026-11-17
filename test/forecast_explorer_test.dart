import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/ui/forecast_explorer.dart';
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
  Widget scene({
    bool compact = false,
    bool reduced = false,
    double scale = 1,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduced,
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: ForecastExplorer(
            key: const ValueKey('explorer'),
            forecast: forecast,
            settings: const Settings(),
            now: now,
            compact: compact,
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'real-hour selection preserves missing rain and survives layout change',
    (tester) async {
      await tester.pumpWidget(scene());
      expect(find.text('4° · 0% rain'), findsOneWidget);
      await tester.tap(find.byTooltip('Later forecast hour'));
      await tester.pump();
      expect(find.text('6° · Rain chance unavailable'), findsOneWidget);
      await tester.pumpWidget(scene(compact: true, reduced: true));
      await tester.pump();
      expect(find.text('6° · Rain chance unavailable'), findsOneWidget);
      await tester.tap(find.byTooltip('Later forecast hour'));
      await tester.pump();
      expect(find.text('9° · 80% rain'), findsOneWidget);
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('chart scrub and keyboard choose actual samples across a gap', (
    tester,
  ) async {
    await tester.pumpWidget(scene());
    final chart = find.byKey(const ValueKey('forecast-explorer-chart'));
    await tester.drag(chart, const Offset(400, 0));
    await tester.pump();
    expect(find.text('9° · 80% rain'), findsOneWidget);
    Focus.of(tester.element(chart)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('6° · Rain chance unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact large-text exploration remains scrollable and free of overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(scene(compact: true, reduced: true, scale: 2.5));
      await tester.pump();
      expect(find.text('4° · 0% rain'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
