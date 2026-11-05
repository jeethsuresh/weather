import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/sky.dart';
import 'package:local_weather/ui/forecast_cards.dart';
import 'package:local_weather/ui/sky_weather.dart';
import 'package:local_weather/widget_data.dart';
import 'package:timezone/data/latest.dart' as tzdata;

Forecast forecast(
  String summary,
  DateTime now, {
  List<WeatherAlert> alerts = const [],
  DateTime? sunrise,
  DateTime? sunset,
}) => Forecast(
  source: WeatherSource.nws,
  fetchedAt: now,
  observedAt: now,
  temperature: 12,
  summary: summary,
  hours: [
    for (var i = 0; i < 24; i++)
      HourForecast(
        time: now.add(Duration(hours: i)),
        temperature: 12 + i % 5,
        summary: summary,
        rain: 20,
      ),
  ],
  days: const [],
  alerts: alerts,
  sunrise: sunrise,
  sunset: sunset,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  setUpAll(() async {
    final packages =
        jsonDecode(
              File('.dart_tool/package_config.json').readAsStringSync(),
            )['packages']
            as List;
    final root = Uri.parse(
      '${packages.firstWhere((p) => p['name'] == 'flutter')['rootUri']}/',
    );
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Light', 'Medium', 'Bold']) {
      final bytes =
          await File.fromUri(
            root.resolve(
              '../../bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
            ),
          ).readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons');
    final bytes =
        await File.fromUri(
          root.resolve(
            '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ).readAsBytes();
    icons.addFont(Future.value(ByteData.sublistView(bytes)));
    await icons.load();
  });
  final noon = DateTime.utc(2026, 11, 5, 17);
  final night = DateTime.utc(2026, 11, 6, 3);
  const settings = Settings();
  test(
    'solar events use the place date and actual provider events only that day',
    () {
      final sun = SolarDay.at(Place.toronto, noon);
      final rise = Place.toronto.local(sun.sunrise!);
      final set = Place.toronto.local(sun.sunset!);
      expect(rise.day, 5);
      expect(rise.hour * 60 + rise.minute, inInclusiveRange(414, 426));
      expect(set.hour, 17);
      expect(set.minute, inInclusiveRange(0, 12));
      expect(sun.nightAt(noon), isFalse);
      expect(sun.nightAt(night), isTrue);
      final supplied = forecast(
        'Clear',
        noon,
        sunrise: DateTime.utc(2026, 11, 5, 12, 1),
        sunset: DateTime.utc(2026, 11, 5, 22, 9),
      );
      expect(
        SolarDay.at(Place.toronto, noon, supplied).sunset,
        supplied.sunset,
      );
      expect(
        SolarDay.at(
          Place.toronto,
          noon.add(const Duration(days: 1)),
          supplied,
        ).sunset,
        isNot(supplied.sunset),
      );
    },
  );
  test(
    'date line, opposite hemispheres, DST and polar seasons stay on the local date',
    () {
      for (final place in [
        Place.toronto,
        const Place(
          name: 'Sydney',
          latitude: -33.87,
          longitude: 151.21,
          country: 'AU',
          timezone: 'Australia/Sydney',
        ),
        const Place(
          name: 'Kiritimati',
          latitude: 1.87,
          longitude: -157.43,
          country: 'KI',
          timezone: 'Pacific/Kiritimati',
        ),
        const Place(
          name: 'Pago Pago',
          latitude: -14.27,
          longitude: -170.7,
          country: 'AS',
          timezone: 'Pacific/Pago_Pago',
        ),
      ]) {
        for (final now in [
          DateTime.utc(2026, 3, 8, 6),
          DateTime.utc(2026, 11, 1, 6),
          noon,
        ]) {
          final expected = place.local(now);
          final solar = SolarDay.at(place, now);
          for (final value in [solar.sunrise!, solar.sunset!]) {
            final local = place.local(value);
            expect(
              [local.year, local.month, local.day],
              [expected.year, expected.month, expected.day],
            );
          }
        }
      }
      const arctic = Place(
        name: 'Tromsø',
        latitude: 69.65,
        longitude: 18.96,
        country: 'NO',
        timezone: 'Europe/Oslo',
      );
      final summer = DateTime.utc(2026, 6, 21, 12);
      final winter = DateTime.utc(2026, 12, 21, 12);
      expect(SolarDay.at(arctic, summer).sunrise, isNull);
      expect(SolarDay.at(arctic, summer).nightAt(summer), isFalse);
      expect(SolarDay.at(arctic, winter).nightAt(winter), isTrue);
    },
  );
  test('mean moon phase wraps before and after the reference new moon', () {
    final reference = DateTime.utc(2000, 1, 6, 18, 14);
    expect(moonPhaseName(moonPhase(reference)), 'New moon');
    expect(
      moonPhaseName(moonPhase(reference.add(const Duration(days: 15)))),
      'Full moon',
    );
    expect(
      moonPhaseName(moonPhase(reference.subtract(const Duration(days: 7)))),
      'Last quarter',
    );
  });
  test('only active official hazards add edges; multiple types coexist', () {
    final alerts = [
      WeatherAlert(
        'YELLOW ADVISORY - FROST',
        '',
        expires: noon.add(const Duration(hours: 1)),
      ),
      const WeatherAlert('Wind warning', ''),
      const WeatherAlert('Severe Thunderstorm Watch', ''),
      WeatherAlert('Freeze warning', '', expires: noon),
    ];
    expect(warningEdges(alerts, noon), {'frost', 'wind', 'thunder'});
    expect(
      warningEdges([WeatherAlert('Wind warning', '', expires: noon)], noon),
      isEmpty,
    );
    expect(warningEdges([], noon), isEmpty);
    final payload = widgetPayload(
      settings,
      forecast('Thunderstorm', noon),
      noon,
    );
    expect(payload['alerts'], isEmpty);
    expect(payload['latitude'], Place.toronto.latitude);
    expect(payload['longitude'], Place.toronto.longitude);
    expect(
      SkyPalette.at(settings, forecast('Sunny', noon), noon).card,
      isNot(SkyPalette.at(settings, forecast('Cloudy', noon), noon).card),
    );
    expect(
      SkyPalette.at(settings, forecast('Rain', noon), noon).card,
      isNot(SkyPalette.at(settings, forecast('Cloudy', noon), noon).card),
    );
  });
  testWidgets(
    'clear nights show the moon and local solar times, cloudy nights do not',
    (tester) async {
      Future<void> show(String summary) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CurrentWeatherCard(
                    forecast: forecast(summary, night),
                    settings: settings,
                    now: night,
                    height: 280,
                  ),
                  SkyDetails(
                    settings: settings,
                    forecast: forecast(summary, night),
                    now: night,
                  ),
                ],
              ),
            ),
          ),
        );
      }

      await show('Clear');
      expect(find.byType(MoonDisc), findsNWidgets(2));
      expect(find.textContaining('Sunrise'), findsOneWidget);
      expect(find.textContaining('Sunset'), findsOneWidget);
      await show('Cloudy');
      expect(find.byType(MoonDisc), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'warning art leaves controls tappable and generates sky previews',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: RepaintBoundary(
              key: key,
              child: GridView.count(
                crossAxisCount: 2,
                childAspectRatio: 400 / 550,
                children: [
                  for (final item in [
                    ('Sunny', noon, {'frost'}),
                    ('Cloudy', noon, {'wind'}),
                    ('Rain', noon, {'thunder'}),
                    ('Clear', night, {'frost', 'wind', 'thunder'}),
                  ])
                    WarningEdges(
                      hazards: item.$3,
                      child: ColoredBox(
                        color:
                            SkyPalette.at(
                              settings,
                              forecast(item.$1, item.$2),
                              item.$2,
                            ).background,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Text(
                                item.$1,
                                style: const TextStyle(fontSize: 24),
                              ),
                              const SizedBox(height: 12),
                              CurrentWeatherCard(
                                forecast: forecast(item.$1, item.$2),
                                settings: settings,
                                now: item.$2,
                                height: 280,
                              ),
                              SkyDetails(
                                settings: settings,
                                forecast: forecast(item.$1, item.$2),
                                now: item.$2,
                              ),
                              TextButton(
                                onPressed: () => taps++,
                                child: const Text('Refresh'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Refresh').first);
      expect(taps, 1);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/previews/sky-themes.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    },
  );
}
