import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controller.dart';
import '../models.dart';
import 'weather_style.dart';
import 'forecast_cards.dart';
export 'flip_weather_card.dart';

/// Use the app window, which changes when a Razr opens or closes, rather than
/// physical display pixels or a manufacturer/model check.
bool useCompactWeatherLayout(Size window) => window.height <= 600;

const _background = Color(0xff102923);
const _paper = Color(0xffe7f0df);
const _soft = Color(0xffb9cec1);

class CompactWeatherView extends StatelessWidget {
  const CompactWeatherView({
    super.key,
    required this.controller,
    required this.onPlaces,
    required this.onSettings,
  });
  final WeatherController controller;
  final VoidCallback onPlaces, onSettings;

  @override
  Widget build(BuildContext context) {
    final s = controller.settings;
    final f = controller.forecast;
    final now = DateTime.now();
    final hours = f?.upcoming(now) ?? <HourForecast>[];
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _background,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _background,
        // Honor all system-reported cutouts and navigation insets on either display.
        body: SafeArea(
          minimum: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 4, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onPlaces,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 17,
                                color: _soft,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s.place.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _paper,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      f == null
                                          ? 'DAYBREAK'
                                          : '${DateFormat('EEE, MMM d').format(s.place.local(now))} · Updated ${age(f.fetchedAt, now)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _soft,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.expand_more,
                                size: 16,
                                color: _soft,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh forecast',
                      onPressed:
                          controller.loading
                              ? null
                              : () => controller.refresh(force: true),
                      color: _soft,
                      icon:
                          controller.loading
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _soft,
                                ),
                              )
                              : const Icon(Icons.refresh, size: 21),
                    ),
                    IconButton(
                      tooltip: 'Weather settings',
                      onPressed: onSettings,
                      icon: const Icon(Icons.tune, color: _soft, size: 21),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final scale = MediaQuery.textScalerOf(
                      context,
                    ).scale(1).clamp(1.0, 2.5);
                    final currentHeight = math.min(
                      220.0,
                      math.max(184.0, bounds.maxHeight - 8),
                    );
                    return RefreshIndicator(
                      onRefresh: () => controller.refresh(force: true),
                      color: ink,
                      child: ListView(
                        key: const PageStorageKey('compact-weather-scroll'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                        children: [
                          if (f == null)
                            _EmptyCompact(
                              controller: controller,
                              onPlaces: onPlaces,
                            )
                          else ...[
                            if (controller.error != null || f.staleAt(now))
                              _CompactNotice(
                                controller.error ??
                                    'Saved conditions · ${age(f.observedAt, now)}',
                              ),
                            if (f.notice != null) _CompactNotice(f.notice!),
                            if (controller.backgroundError != null)
                              _CompactNotice(controller.backgroundError!),
                            CurrentWeatherCard(
                              key: ValueKey('card-current-${s.place.id}'),
                              forecast: f,
                              settings: s,
                              now: now,
                              compact: true,
                              height: currentHeight * scale,
                            ),
                            if (hours.isNotEmpty) ...[
                              const Padding(
                                padding: EdgeInsets.fromLTRB(8, 12, 8, 6),
                                child: Text(
                                  'THE HOURS AHEAD',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.7,
                                    color: _soft,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              HourlyForecastStrip(
                                key: ValueKey('card-hours-${s.place.id}'),
                                hours: hours,
                                settings: s,
                                compact: true,
                              ),
                            ],
                            if (f.days.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(8, 12, 8, 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'A LITTLE FURTHER OUT',
                                        style: TextStyle(
                                          fontSize: 10,
                                          letterSpacing: 1.7,
                                          color: _soft,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'HIGH / LOW',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: _soft,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (f.days.isNotEmpty)
                              DailyForecastList(
                                key: ValueKey('forecast-days-${s.place.id}'),
                                forecast: f,
                                settings: s,
                                compact: true,
                              ),
                            for (final alert in f.alerts.where(
                              (a) =>
                                  a.expires == null || a.expires!.isAfter(now),
                            ))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Card(
                                  color: const Color(0xfff6d3b0),
                                  child: ExpansionTile(
                                    iconColor: ink,
                                    collapsedIconColor: ink,
                                    title: Text(
                                      alert.title,
                                      style: const TextStyle(
                                        color: ink,
                                        fontSize: 13,
                                      ),
                                    ),
                                    leading: const Icon(
                                      Icons.warning_amber,
                                      color: ink,
                                    ),
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(
                                          alert.detail,
                                          style: const TextStyle(
                                            color: ink,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            TextButton(
                              onPressed: onSettings,
                              child: Text(
                                f.source.label,
                                style: const TextStyle(
                                  color: _soft,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (f.source == WeatherSource.openMeteo)
                              const Text(
                                'Open-Meteo · CC BY 4.0',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _soft, fontSize: 10),
                              ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactNotice extends StatelessWidget {
  const _CompactNotice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfff6d3b0),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(text, style: const TextStyle(color: ink, fontSize: 12)),
  );
}

class _EmptyCompact extends StatelessWidget {
  const _EmptyCompact({required this.controller, required this.onPlaces});
  final WeatherController controller;
  final VoidCallback onPlaces;
  @override
  Widget build(BuildContext context) => Card(
    color: _paper,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(Icons.wb_sunny_outlined, color: ink, size: 34),
          const SizedBox(height: 12),
          Text(
            controller.error ?? 'Getting your forecast…',
            textAlign: TextAlign.center,
            style: const TextStyle(color: ink, fontSize: 14),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onPlaces,
            child: const Text('Choose a city'),
          ),
        ],
      ),
    ),
  );
}
