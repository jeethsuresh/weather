import 'dart:convert';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:workmanager/workmanager.dart';
import 'models.dart';
import 'repository.dart';
import 'widget_data.dart';

const refreshJob = 'dev.jeeth.daybreak.hourly';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    tzdata.initializeTimeZones();
    final repository = WeatherRepository.device();
    try {
      final settings = await repository.settings();
      if (!settings.hourly) return true;
      // WorkManager may run inside its hourly flex window before 60 minutes.
      // Each scheduled check must fetch, rather than skip a still-fresh cache.
      final forecast = await repository.refresh(settings, force: true);
      await publishWidget(repository, settings, forecast);
      return true;
    } catch (_) {
      // Keep the last successful forecast and its original timestamp on failure.
      // Android WorkManager applies backoff when the callback asks for a retry.
      return false;
    } finally {
      repository.close();
    }
  });
}

Future<void> scheduleRefresh(bool enabled) async {
  if (!enabled) {
    await Workmanager().cancelByUniqueName(refreshJob);
    return;
  }
  await Workmanager().registerPeriodicTask(
    refreshJob,
    refreshJob,
    frequency: const Duration(hours: 1),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );
}

Future<void> publishWidget(
  WeatherRepository repository,
  Settings s,
  Forecast? f,
) async {
  final current = await repository.settings();
  if (current.cacheKey != s.cacheKey || current.fahrenheit != s.fahrenheit) {
    return;
  }
  final payload = widgetPayload(s, f, DateTime.now());
  await HomeWidget.saveWidgetData<String>('weather', jsonEncode(payload));
  for (final provider in widgetProviders) {
    await HomeWidget.updateWidget(androidName: provider);
  }
}
