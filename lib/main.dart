import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:workmanager/workmanager.dart';
import 'background.dart';
import 'controller.dart';
import 'repository.dart';
import 'ui/weather_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  // Let the current display choose its orientation when the phone opens/closes.
  await SystemChrome.setPreferredOrientations([]);
  // The forecast screen stays usable even if Android declines background setup.
  try {
    await Workmanager().initialize(callbackDispatcher);
  } catch (_) {}
  runApp(const DaybreakApp());
}

class DaybreakApp extends StatefulWidget {
  const DaybreakApp({super.key, this.controller});
  final WeatherController? controller;
  @override
  State<DaybreakApp> createState() => _DaybreakAppState();
}

class _DaybreakAppState extends State<DaybreakApp> with WidgetsBindingObserver {
  late final WeatherController controller;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller =
        widget.controller ??
        WeatherController(
          WeatherRepository.device(),
          publish: publishWidget,
          schedule: scheduleRefresh,
        );
    unawaited(controller.initialize());
    timer = Timer.periodic(const Duration(hours: 1), (_) {
      if (controller.settings.hourly) unawaited(controller.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && controller.initialized) {
      // A background isolate may have refreshed while the app was suspended.
      unawaited(controller.resume());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Daybreak',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff7f8f4),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff285a50),
        surface: const Color(0xfff7f8f4),
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: const Color(0xff193b38),
        displayColor: const Color(0xff193b38),
      ),
    ),
    home: WeatherScreen(controller: controller),
  );
}
