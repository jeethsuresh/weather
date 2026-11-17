import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/ui/forecast_feedback.dart';

void main() {
  Forecast reading(int revision, double temperature) => Forecast(
    source: WeatherSource.canada,
    fetchedAt: DateTime.utc(2026, 11, 17, 12, revision),
    observedAt: DateTime.utc(2026, 11, 17, 12),
    temperature: temperature,
    summary: 'Clear',
    days: const [],
    hours: const [],
  );
  Widget scene(Forecast forecast, {bool reduced = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(
        body: ForecastRefreshFeedback(
          forecast: forecast,
          child: const SizedBox(width: 200, height: 100),
        ),
      ),
    ),
  );
  double alpha(WidgetTester tester) =>
      ((tester
                          .widget<DecoratedBox>(
                            find.byKey(
                              const ValueKey('forecast-refresh-accent'),
                            ),
                          )
                          .decoration
                      as BoxDecoration)
                  .border
              as Border)
          .top
          .color
          .a;

  testWidgets('initial, unchanged and older forecasts do not replay feedback', (
    tester,
  ) async {
    await tester.pumpWidget(scene(reading(0, 4)));
    expect(alpha(tester), 0);
    await tester.pumpWidget(scene(reading(1, 4)));
    expect(alpha(tester), 0);
    await tester.pumpWidget(scene(reading(0, 5)));
    expect(alpha(tester), 0);
    await tester.pumpWidget(scene(reading(2, 6)));
    expect(alpha(tester), greaterThan(0));
    await tester.pump(const Duration(seconds: 1));
    expect(alpha(tester), 0);
  });

  testWidgets('reduced motion settles active feedback without a stuck border', (
    tester,
  ) async {
    final before = reading(0, 4), after = reading(1, 6);
    await tester.pumpWidget(scene(before));
    await tester.pumpWidget(scene(after));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(scene(after, reduced: true));
    expect(alpha(tester), greaterThan(0));
    await tester.pump(const Duration(seconds: 1));
    expect(alpha(tester), 0);
    await tester.pumpWidget(scene(after));
    expect(alpha(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
