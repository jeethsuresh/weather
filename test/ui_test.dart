import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/controller.dart';
import 'package:local_weather/main.dart';
import 'package:local_weather/repository.dart';
import 'package:local_weather/weather_api.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'support.dart';

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
    final iconLoader = FontLoader('MaterialIcons');
    final icons =
        await File.fromUri(
          root.resolve(
            '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ).readAsBytes();
    iconLoader.addFont(Future.value(ByteData.sublistView(icons)));
    await iconLoader.load();
  });

  WeatherController makeController() {
    final store = MemoryStore();
    return WeatherController(
      WeatherRepository(
        store,
        WeatherApi(StubTransport((_) async => fixture('canada')), store),
      ),
      publish: (_, _, _) async {},
      schedule: (_) async {},
    );
  }

  for (final width in [320.0, 390.0, 480.0]) {
    testWidgets(
      'weather, settings and city search fit ${width.toInt()}dp phone',
      (tester) async {
        tester.view.physicalSize = Size(width * 2, 1688);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = makeController();
        await tester.pumpWidget(DaybreakApp(controller: c));
        await tester.pumpAndSettle();
        expect(find.text('Toronto'), findsOneWidget);
        expect(find.text('Mainly Sunny'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Weather settings'));
        await tester.pumpAndSettle();
        expect(find.text('Make it yours'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Fahrenheit'));
        await tester.pumpAndSettle();
        expect(c.settings.fahrenheit, isTrue);
        await tester.tapAt(const Offset(12, 12));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Toronto'));
        await tester.pumpAndSettle();
        expect(find.text('Find your sky'), findsOneWidget);
        expect(find.text('Vancouver'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }

  testWidgets('forecast stays usable with larger accessibility text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = makeController();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Builder(builder: (context) => DaybreakApp(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('save a visual preview of the forecast screen', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = makeController();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: DaybreakApp(controller: c)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/daybreak.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
