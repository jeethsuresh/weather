import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import '../controller.dart';
import '../models.dart';
import '../location.dart';

import 'compact_weather.dart';
import 'weather_style.dart';
import 'forecast_cards.dart';

class WeatherScreen extends StatelessWidget {
  const WeatherScreen({super.key, required this.controller});
  final WeatherController controller;

  void _places(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => PlaceSheet(controller: controller),
  );
  void _settings(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => SettingsSheet(controller: controller),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final s = controller.settings;
      final f = controller.forecast;
      final now = DateTime.now();
      final hours = f?.upcoming(now) ?? [];
      final scale =
          MediaQuery.textScalerOf(context).scale(1).clamp(1, 2).toDouble();
      if (useCompactWeatherLayout(MediaQuery.sizeOf(context))) {
        return CompactWeatherView(
          controller: controller,
          onPlaces: () => _places(context),
          onSettings: () => _settings(context),
        );
      }
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () => controller.refresh(force: true),
            color: ink,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: ink,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.wb_sunny_outlined,
                            color: Color(0xffffd8a5),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text(
                            'DAYBREAK',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                        if (controller.loading)
                          const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else
                          IconButton(
                            tooltip: 'Refresh forecast',
                            onPressed: () => controller.refresh(force: true),
                            icon: const Icon(Icons.refresh, size: 22),
                          ),
                        IconButton(
                          tooltip: 'Weather settings',
                          onPressed: () => _settings(context),
                          icon: const Icon(Icons.tune, size: 22),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _places(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 23,
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    s.place.name,
                                    style: const TextStyle(
                                      fontSize: 29,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.expand_more, size: 23),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          '${s.place.subtitle}  ·  ${DateFormat('EEE, MMM d').format(s.place.local(now))}',
                          style: const TextStyle(color: muted, fontSize: 13),
                        ),
                        const SizedBox(height: 22),
                        if (f == null)
                          _EmptyForecast(
                            controller: controller,
                            onChoosePlace: () => _places(context),
                          )
                        else ...[
                          CurrentWeatherCard(
                            key: ValueKey('card-current-${s.place.id}'),
                            forecast: f,
                            settings: s,
                            now: now,
                            height: 330 * scale,
                          ),
                          const SizedBox(height: 18),
                          if (controller.error != null || f.staleAt(now))
                            _Notice(
                              controller.error ??
                                  'Saved forecast · updated ${age(f.fetchedAt, now)}. Pull down to refresh.',
                              icon: Icons.cloud_off_outlined,
                            ),
                          if (f.notice != null)
                            _Notice(f.notice!, icon: Icons.info_outline),
                          if (controller.backgroundError != null)
                            _Notice(
                              controller.backgroundError!,
                              icon: Icons.schedule,
                            ),
                          for (final alert in f.alerts.where(
                            (a) => a.expires == null || a.expires!.isAfter(now),
                          ))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _AlertCard(alert: alert),
                            ),
                          const SizedBox(height: 6),
                          _SectionTitle(
                            'The hours ahead',
                            trailing: '12 HOURS',
                          ),
                          const SizedBox(height: 14),
                          if (hours.isEmpty)
                            const _Card(
                              child: Padding(
                                padding: EdgeInsets.all(22),
                                child: Text(
                                  'Your saved hourly forecast has ended. Refresh when you’re online.',
                                ),
                              ),
                            )
                          else
                            HoursWeatherCard(
                              key: ValueKey('card-hours-${s.place.id}'),
                              forecast: f,
                              settings: s,
                              now: now,
                              height: 255 * scale,
                            ),
                          const SizedBox(height: 28),
                          const _SectionTitle(
                            'A little further out',
                            trailing: 'TAP TO FLIP',
                          ),
                          const SizedBox(height: 14),
                          for (var i = 0; i < f.days.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: DailyWeatherCard(
                                key: ValueKey(
                                  'card-day-${f.days[i].date ?? f.days[i].label}-${s.place.id}',
                                ),
                                forecast: f,
                                day: f.days[i],
                                index: i,
                                settings: s,
                                now: now,
                                height: 240 * scale,
                              ),
                            ),
                          const SizedBox(height: 28),
                          const _SectionTitle('Outside, in detail'),
                          const SizedBox(height: 14),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final tiles = [
                                _Metric(
                                  icon: Icons.thermostat_outlined,
                                  label: 'FEELS LIKE',
                                  value: s.temperature(f.feelsLike),
                                  detail:
                                      f.feelsLike == null
                                          ? 'Not reported by source'
                                          : 'Apparent temperature',
                                ),
                                _Metric(
                                  icon: Icons.air,
                                  label: 'WIND',
                                  value: s.wind(f.wind),
                                  detail: 'Near the surface',
                                ),
                                _Metric(
                                  icon: Icons.water_drop_outlined,
                                  label: 'HUMIDITY',
                                  value:
                                      f.humidity == null
                                          ? '—'
                                          : '${f.humidity!.round()}%',
                                  detail: 'Relative humidity',
                                ),
                                _Metric(
                                  icon: Icons.wb_twilight,
                                  label:
                                      f.sunset == null
                                          ? 'PRECIPITATION'
                                          : 'SUNSET',
                                  value:
                                      f.sunset == null
                                          ? (hours.firstOrNull?.rain == null
                                              ? '—'
                                              : '${hours.first.rain!.round()}%')
                                          : DateFormat(
                                            'h:mm a',
                                          ).format(s.place.local(f.sunset!)),
                                  detail:
                                      f.sunset == null
                                          ? 'Chance in the next hour'
                                          : 'Local time in ${s.place.name}',
                                ),
                              ];
                              return Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children:
                                    tiles
                                        .map(
                                          (t) => SizedBox(
                                            width:
                                                (constraints.maxWidth - 12) / 2,
                                            child: t,
                                          ),
                                        )
                                        .toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          _SourceCard(
                            forecast: f,
                            settings: s,
                            onTap: () => _settings(context),
                          ),
                        ],
                        const SizedBox(height: 24),
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.phonelink_lock_outlined,
                                size: 14,
                                color: muted,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  s.hourly
                                      ? 'Stored on your phone · hourly checks'
                                      : 'Stored on your phone · manual updates',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });
  final IconData icon;
  final String label, value, detail;
  @override
  Widget build(BuildContext context) => _Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: muted),
          const SizedBox(height: 18),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: muted,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w500,
                letterSpacing: -.6,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(detail, style: const TextStyle(fontSize: 10, color: muted)),
        ],
      ),
    ),
  );
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.forecast,
    required this.settings,
    required this.onTap,
  });
  final Forecast forecast;
  final Settings settings;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(22),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: mint,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.public, size: 22, color: Color(0xff4d7566)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  forecast.source.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Updated ${age(forecast.fetchedAt, DateTime.now())}'
                  '${forecast.station == null ? '' : ' · ${forecast.station}'}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                if (forecast.source == WeatherSource.openMeteo)
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Text(
                      'Open-Meteo · CC BY 4.0 · official alerts unavailable',
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_outward, size: 16, color: muted),
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -.3,
          ),
        ),
      ),
      if (trailing != null)
        Text(
          trailing!,
          style: const TextStyle(fontSize: 9, color: muted, letterSpacing: .6),
        ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xffe9ede5)),
    ),
    child: child,
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xffffefd9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xff8a6236)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Color(0xff775a35)),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final WeatherAlert alert;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xffffe8df),
      borderRadius: BorderRadius.circular(16),
    ),
    child: ExpansionTile(
      shape: const Border(),
      leading: const Icon(Icons.warning_amber, color: Color(0xffa54d35)),
      title: Text(
        alert.title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SelectableText(
            alert.detail,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
      ],
    ),
  );
}

class _EmptyForecast extends StatelessWidget {
  const _EmptyForecast({required this.controller, required this.onChoosePlace});
  final WeatherController controller;
  final VoidCallback onChoosePlace;
  @override
  Widget build(BuildContext context) => _Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.wb_sunny_outlined, size: 65, color: orange),
          const SizedBox(height: 24),
          Text(
            controller.loading
                ? 'Looking at the sky…'
                : 'Let’s check the weather',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),
          Text(
            controller.error ??
                'Getting a forecast directly from the weather service.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed:
                controller.loading
                    ? null
                    : () => controller.refresh(force: true),
            child: const Text('Try again'),
          ),
          TextButton(
            onPressed: onChoosePlace,
            child: const Text('Choose a different city'),
          ),
        ],
      ),
    ),
  );
}

class PlaceSheet extends StatefulWidget {
  const PlaceSheet({super.key, required this.controller});
  final WeatherController controller;
  @override
  State<PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<PlaceSheet> {
  final input = TextEditingController();
  Timer? debounce;
  int generation = 0;
  List<Place> results = [];
  bool searching = false;
  String? error;
  static const suggested = [
    Place.toronto,
    Place(
      name: 'Vancouver',
      latitude: 49.2827,
      longitude: -123.1207,
      country: 'CA',
      timezone: 'America/Vancouver',
      region: 'British Columbia',
    ),
    Place(
      name: 'Montréal',
      latitude: 45.5017,
      longitude: -73.5673,
      country: 'CA',
      timezone: 'America/Toronto',
      region: 'Quebec',
    ),
    Place(
      name: 'New York',
      latitude: 40.7128,
      longitude: -74.006,
      country: 'US',
      timezone: 'America/New_York',
      region: 'New York',
    ),
  ];
  void search(String query) {
    debounce?.cancel();
    final token = ++generation;
    if (query.trim().length < 2) {
      setState(() {
        results = [];
        searching = false;
        error = null;
      });
      return;
    }
    setState(() {
      searching = true;
      error = null;
    });
    debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final found = await widget.controller.repository.api.search(query);
        if (!mounted || token != generation) return;
        setState(() {
          results = found;
          searching = false;
        });
      } catch (_) {
        if (!mounted || token != generation) return;
        setState(() {
          error =
              'City search needs a connection. You can still choose a city below.';
          searching = false;
        });
      }
    });
  }

  @override
  void dispose() {
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final places =
        input.text.trim().length < 2 || error != null ? suggested : results;
    final media = MediaQuery.of(context);
    final available = math.max(
      0.0,
      media.size.height - media.viewInsets.bottom - media.padding.top - 44,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, media.viewInsets.bottom),
      child: SizedBox(
        height: math.min(520.0, available),
        child: ListView(
          key: const ValueKey('city-search-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            Text(
              'Find your sky',
              style: TextStyle(
                fontSize: available < 300 ? 21 : 27,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (available >= 300) ...[
              const SizedBox(height: 8),
              const Text(
                'Use your location, or choose a city.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            _LocationChoice(
              controller: widget.controller,
              onSelected: () => Navigator.pop(context),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: input,
              onChanged: search,
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Search a city or postal code',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                suffixIcon:
                    searching
                        ? const Padding(
                          padding: EdgeInsets.all(15),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                        : null,
              ),
            ),
            const SizedBox(height: 10),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error!,
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ),
            if (places.isEmpty && !searching)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No cities found. Try a nearby larger city.'),
              ),
            for (final place in places)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_city_outlined),
                title: Text(place.name),
                subtitle: Text(place.subtitle),
                trailing: const Icon(Icons.north_east, size: 18),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(
                    widget.controller.update(
                      widget.controller.settings.copyWith(
                        place: place,
                        source: WeatherSource.auto,
                      ),
                    ),
                  );
                },
              ),
            const Text(
              'City search by Open-Meteo / GeoNames',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.controller});
  final WeatherController controller;
  Future<void> openLink(String url) async {
    await const MethodChannel(
      'dev.jeeth.daybreak/actions',
    ).invokeMethod<void>('openLink', {'url': url});
  }

  Future<void> addWidget(BuildContext context, String provider) async {
    try {
      if (await HomeWidget.isRequestPinWidgetSupported() != true) {
        throw UnsupportedError('Launcher pinning unavailable');
      }
      await HomeWidget.requestPinWidget(androidName: provider);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Long-press your home screen, choose Widgets, then Daybreak.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final s = controller.settings;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        minChildSize: .5,
        builder:
            (_, scrollController) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
              children: [
                const Text(
                  'Make it yours',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A small forecast. A lighter footprint.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 18),
                _LocationChoice(controller: controller),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Fahrenheit'),
                  subtitle: const Text(
                    'Temperature in °F · wind in mph',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: s.fahrenheit,
                  onChanged:
                      (v) => controller.update(s.copyWith(fahrenheit: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hourly background checks'),
                  subtitle: const Text(
                    'Android may delay checks to save battery. Opening the app catches up.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: s.hourly,
                  onChanged: (v) => controller.update(s.copyWith(hourly: v)),
                ),
                const Divider(height: 36),
                const Text(
                  'Weather source',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final source in WeatherSource.values)
                  RadioListTile<WeatherSource>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      source.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      source.description,
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: source,
                    groupValue: s.source,
                    onChanged:
                        (source == WeatherSource.canada &&
                                    s.place.country != 'CA') ||
                                (source == WeatherSource.nws &&
                                    s.place.country != 'US')
                            ? null
                            : (v) {
                              if (v != null) {
                                unawaited(
                                  controller.update(s.copyWith(source: v)),
                                );
                              }
                            },
                  ),
                const Divider(height: 36),
                const Text(
                  'Home-screen widgets',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final option in const [
                  ('1×1', 'Temperature + icon', 'TemperatureWidgetProvider'),
                  (
                    '2×1',
                    'Temperature, icon + weather',
                    'SummaryWidgetProvider',
                  ),
                  (
                    '2×2',
                    'Weather, wind + precipitation',
                    'WeatherWidgetProvider',
                  ),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 48,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        option.$1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    title: Text(
                      option.$2,
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.add_circle_outline, size: 22),
                    onTap: () => addWidget(context, option.$3),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'Your phone is the whole app',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No account, ads, analytics, or app server. Settings and forecasts are stored locally and excluded from Android backup. '
                  'Forecast coordinates go directly to the selected weather service; city searches and location timezone lookup go to Open-Meteo. Area names use Android’s geocoder. Location is optional and requested only while the app is in use. The saved area is used for background weather checks.',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Sources & attribution',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                TextButton(
                  onPressed:
                      () => openLink('https://eccc-msc.github.io/open-data/'),
                  child: const Text('Environment and Climate Change Canada'),
                ),
                TextButton(
                  onPressed:
                      () => openLink(
                        'https://www.weather.gov/documentation/services-web-api',
                      ),
                  child: const Text('NOAA / National Weather Service'),
                ),
                TextButton(
                  onPressed: () => openLink('https://open-meteo.com/'),
                  child: const Text('Weather data by Open-Meteo · CC BY 4.0'),
                ),
                TextButton(
                  onPressed: () => openLink('https://www.geonames.org/'),
                  child: const Text('Location data by GeoNames · CC BY 4.0'),
                ),
                const Text(
                  'Open-Meteo’s free endpoint is for non-commercial use. National alerts are shown when supplied by the selected national service; '
                  'Open-Meteo does not supply official alerts. Background checks and the widget are not an emergency warning system.',
                  style: TextStyle(fontSize: 10, color: muted, height: 1.5),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'DAYBREAK  /  1.4',
                    style: TextStyle(
                      fontSize: 10,
                      color: muted,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
      );
    },
  );
}

class _LocationChoice extends StatelessWidget {
  const _LocationChoice({required this.controller, this.onSelected});
  final WeatherController controller;
  final VoidCallback? onSelected;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder:
        (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  controller.locating
                      ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.my_location),
              title: Text(
                controller.locating
                    ? 'Finding your location…'
                    : 'Use current location',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                controller.settings.place.isCurrentLocation
                    ? 'Using ${controller.settings.place.name}${controller.settings.place.accuracyMeters == null ? '' : ' · ±${controller.settings.place.accuracyMeters!.round()} m'}'
                    : 'Share location while using Daybreak, or choose a city.',
                style: const TextStyle(fontSize: 11),
              ),
              enabled: !controller.locating,
              onTap: () async {
                if (await controller.useCurrentLocation() && context.mounted) {
                  onSelected?.call();
                }
              },
            ),
            if (controller.locationError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  controller.locationError!,
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ),
            if (controller.locationIssue == LocationIssue.disabled ||
                controller.locationIssue == LocationIssue.deniedForever)
              TextButton(
                onPressed:
                    () => controller.locationLookup.openSettings(
                      controller.locationIssue!,
                    ),
                child: Text(
                  controller.locationIssue == LocationIssue.disabled
                      ? 'Open location settings'
                      : 'Open app permissions',
                ),
              ),
          ],
        ),
  );
}
