import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/controller.dart';
import 'package:local_weather/main.dart';
import 'package:local_weather/location.dart';
import 'package:local_weather/ui/weather_screen.dart';
import 'dart:async';
import 'package:local_weather/models.dart';
import 'package:local_weather/repository.dart';
import 'package:local_weather/ui/compact_weather.dart';
import 'package:local_weather/ui/forecast_cards.dart';
import 'package:local_weather/ui/weather_charts.dart';
import 'package:local_weather/weather_api.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'support.dart';

Future<void> loadFonts() async {
  final packages =
      jsonDecode(
            File('.dart_tool/package_config.json').readAsStringSync(),
          )['packages']
          as List;
  final root = Uri.parse(
    '${packages.firstWhere((p) => p['name'] == 'flutter')['rootUri']}/',
  );
  for (final family in ['Roboto', 'MaterialIcons']) {
    final loader = FontLoader(family);
    final files =
        family == 'Roboto'
            ? [
              'Roboto-Regular.ttf',
              'Roboto-Light.ttf',
              'Roboto-Medium.ttf',
              'Roboto-Bold.ttf',
            ]
            : ['MaterialIcons-Regular.otf'];
    for (final file in files) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            await File.fromUri(
              root.resolve('../../bin/cache/artifacts/material_fonts/$file'),
            ).readAsBytes(),
          ),
        ),
      );
    }
    await loader.load();
  }
}

WeatherController compactController({LocationLookup? locationLookup}) {
  final now = DateTime.now().toUtc();
  final start = DateTime.utc(now.year, now.month, now.day, now.hour + 1);
  final f = Forecast(
    source: WeatherSource.canada,
    fetchedAt: now,
    observedAt: now,
    temperature: 16,
    summary: 'Mainly sunny',
    wind: 21,
    humidity: 43,
    feelsLike: 15,
    hours: List.generate(
      8,
      (i) => HourForecast(
        time: start.add(Duration(hours: i)),
        temperature: 16 - i.toDouble(),
        summary: i > 2 ? 'Rain showers' : 'Sunny',
        rain: 20 + i * 10,
        wind: 18 + i.toDouble(),
      ),
    ),
    days: List.generate(
      7,
      (i) => DayForecast(
        label:
            i == 0
                ? 'Today'
                : [
                  'Monday',
                  'Tuesday',
                  'Wednesday',
                  'Thursday',
                  'Friday',
                  'Saturday',
                ][i - 1],
        summary: i % 2 == 0 ? 'Partly cloudy' : 'Rain showers',
        high: 17 + i.toDouble(),
        low: 6 + i.toDouble(),
        rain: 30 + i * 5,
        windMax: 24 + i.toDouble(),
      ),
    ),
  );
  final store = MemoryStore();
  store.values[const Settings().cacheKey] = jsonEncode(f.toJson());
  return WeatherController(
    WeatherRepository(
      store,
      WeatherApi(StubTransport((_) async => fixture('canada')), store),
    ),
    publish: (_, _, _) async {},
    schedule: (_) async {},
    locationLookup: locationLookup,
  );
}

class DeferredLocation implements LocationLookup {
  final completion = Completer<Place>();
  @override
  Future<Place> locate({bool requestPermission = true}) => completion.future;
  @override
  Future<void> openSettings(LocationIssue issue) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  setUpAll(loadFonts);
  void viewport(WidgetTester tester, Size size, {double cutout = 0}) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    tester.view.viewPadding = FakeViewPadding(top: 48, bottom: cutout * 2);
    tester.view.padding = FakeViewPadding(top: 48, bottom: cutout * 2);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
  }

  for (final size in [
    const Size(402, 406),
    const Size(360, 360),
    const Size(320, 320),
    const Size(480, 360),
  ]) {
    testWidgets(
      'compact cards fit $size with camera insets and flip without overflow',
      (tester) async {
        viewport(tester, size, cutout: 72);
        final c = compactController();
        await tester.pumpWidget(DaybreakApp(controller: c));
        await tester.pumpAndSettle();
        expect(find.byType(CompactWeatherView), findsOneWidget);
        expect(find.text('16°'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('flip-current')));
        await tester.pumpAndSettle();
        expect(find.text('Humidity'), findsOneWidget);
        expect(find.text('21 km/h'), findsOneWidget);
        expect(find.text('Mainly sunny'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byType(HourlyForecastStrip),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final strip = find.byType(HourlyForecastStrip);
        expect(
          find.descendant(of: strip, matching: find.byType(WeatherChart)),
          findsNothing,
        );
        final list = find.descendant(
          of: strip,
          matching: find.byType(ListView),
        );
        expect(tester.widget<ListView>(list).scrollDirection, Axis.horizontal);
        await tester.drag(list, const Offset(-600, 0));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: strip, matching: find.text('9°')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('flip-day-0')),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('flip-day-0')));
        await tester.pumpAndSettle();
        expect(find.text('Peak wind'), findsOneWidget);
        expect(find.text('24 km/h'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('flip-current')),
          -100,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Humidity'),
          findsOneWidget,
        ); // independent state survives vertical scrolling
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
  testWidgets(
    'current card fits completely above simulated Razr camera/navigation inset',
    (tester) async {
      viewport(tester, const Size(402, 406), cutout: 80);
      final c = compactController();
      await tester.pumpWidget(DaybreakApp(controller: c));
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byKey(const ValueKey('flip-current')));
      expect(card.top, greaterThanOrEqualTo(24));
      expect(card.bottom, lessThanOrEqualTo(326));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'larger cover text, settings and city search remain scrollable with keyboard',
    (tester) async {
      viewport(tester, const Size(360, 360));
      final c = compactController();
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(DaybreakApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('flip-current')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Weather settings'));
      await tester.pumpAndSettle();
      expect(find.text('Make it yours'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toronto'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 360);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('city-search-scroll')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('opening the phone changes layout and keeps weather and units', (
    tester,
  ) async {
    viewport(tester, const Size(402, 406));
    final c = compactController();
    await tester.pumpWidget(DaybreakApp(controller: c));
    await tester.pumpAndSettle();
    await c.update(c.settings.copyWith(fahrenheit: true));
    await tester.pumpAndSettle();
    expect(find.byType(CompactWeatherView), findsOneWidget);
    expect(find.text('61°'), findsWidgets);
    tester.view.physicalSize = const Size(780, 1688);
    await tester.pumpAndSettle();
    expect(find.byType(CompactWeatherView), findsNothing);
    expect(find.text('Toronto'), findsOneWidget);
    expect(find.text('61°'), findsWidgets);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(804, 812);
    await tester.pumpAndSettle();
    expect(find.byType(CompactWeatherView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'reduced motion flips immediately and exposes only the visible face',
    (tester) async {
      viewport(tester, const Size(402, 406));
      final c = compactController();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(DaybreakApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('flip-current')));
      await tester.pump();
      expect(find.text('Humidity'), findsOneWidget);
      expect(find.text('Mainly sunny'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'dismissing the picker while locating does not pop a disposed route',
    (tester) async {
      viewport(tester, const Size(402, 406));
      final location = DeferredLocation();
      final c = compactController(locationLookup: location);
      await tester.pumpWidget(DaybreakApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toronto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use current location'));
      await tester.pump();
      Navigator.of(tester.element(find.byType(PlaceSheet))).pop();
      await tester.pumpAndSettle();
      location.completion.complete(
        const Place(
          name: 'GPS fix',
          latitude: 43.66,
          longitude: -79.4,
          country: 'CA',
          timezone: 'America/Toronto',
          canadaSite: 'on-143',
          isCurrentLocation: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(c.settings.place.isCurrentLocation, isTrue);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('cover-card previews', (tester) async {
    viewport(tester, const Size(402, 406), cutout: 48);
    final c = compactController();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: DaybreakApp(controller: c)),
    );
    await tester.pumpAndSettle();
    Future<void> save(String name) async {
      await tester.runAsync(() async {
        final render =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final f = File('build/previews/$name.png');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await save('cover-front');
    await tester.tap(find.byKey(const ValueKey('flip-current')));
    await tester.pumpAndSettle();
    await save('cover-back');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('flip-day-0')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await save('cover-days');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
