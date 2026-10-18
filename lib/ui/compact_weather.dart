import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controller.dart';
import '../models.dart';
import 'weather_style.dart';

/// Use the app window, which changes when a Razr opens or closes, rather than
/// physical display pixels or a manufacturer/model check.
bool useCompactWeatherLayout(Size window) => window.height <= 600;

const _background = Color(0xff102923);
const _surface = Color(0xff1e3d34);
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
                                          : 'Updated ${age(f.fetchedAt, now)}',
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
                            FlipWeatherCard(
                              key: ValueKey(
                                'compact-card-current-${s.place.id}',
                              ),
                              id: 'current',
                              title:
                                  f.source == WeatherSource.nws
                                      ? 'CURRENT FORECAST'
                                      : 'RIGHT NOW',
                              light: true,
                              height: currentHeight * scale,
                              front: _CurrentFront(forecast: f, settings: s),
                              back: _DetailGrid(
                                light: true,
                                items: [
                                  _Detail(
                                    'Precipitation',
                                    probability(hours.firstOrNull?.rain),
                                    Icons.water_drop_outlined,
                                    note: 'Next forecast hour',
                                  ),
                                  _Detail(
                                    'Wind',
                                    s.wind(f.wind),
                                    Icons.air,
                                    note: 'Current conditions',
                                  ),
                                  _Detail(
                                    'Humidity',
                                    probability(f.humidity),
                                    Icons.opacity,
                                  ),
                                  _Detail(
                                    'Feels like',
                                    s.temperature(f.feelsLike),
                                    Icons.thermostat_outlined,
                                  ),
                                ],
                              ),
                            ),
                            if (hours.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              FlipWeatherCard(
                                key: ValueKey(
                                  'compact-card-hours-${s.place.id}',
                                ),
                                id: 'hours',
                                title: 'THE NEXT HOURS',
                                height: 190 * scale,
                                front: _HoursFront(
                                  hours: hours.take(4).toList(),
                                  settings: s,
                                ),
                                back: _HoursBack(
                                  hours: hours.take(4).toList(),
                                  settings: s,
                                ),
                              ),
                            ],
                            if (f.days.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(8, 18, 8, 10),
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
                            for (var i = 0; i < f.days.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: FlipWeatherCard(
                                  key: ValueKey(
                                    'compact-card-day-$i-${s.place.id}',
                                  ),
                                  id: 'day-$i',
                                  title: f.days[i].label.toUpperCase(),
                                  height: 186 * scale,
                                  front: _DayFront(day: f.days[i], settings: s),
                                  back: _DetailGrid(
                                    items: [
                                      _Detail(
                                        'Precipitation',
                                        probability(f.days[i].rain),
                                        Icons.water_drop_outlined,
                                        note: 'Forecast chance',
                                      ),
                                      _Detail(
                                        'Peak wind',
                                        s.wind(f.days[i].windMax),
                                        Icons.air,
                                        note: 'Highest reported speed',
                                      ),
                                    ],
                                  ),
                                ),
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

String probability(double? value) => value == null ? '—' : '${value.round()}%';

/// Only the visible face is built, so its sibling never receives focus or
/// contributes hidden readings to accessibility. Swipes remain scroll gestures.
class FlipWeatherCard extends StatefulWidget {
  const FlipWeatherCard({
    super.key,
    required this.id,
    required this.title,
    required this.front,
    required this.back,
    required this.height,
    this.light = false,
  });
  final String id, title;
  final Widget front, back;
  final double height;
  final bool light;
  @override
  State<FlipWeatherCard> createState() => _FlipWeatherCardState();
}

class _FlipWeatherCardState extends State<FlipWeatherCard>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  bool back = false;
  void flip() {
    setState(() => back = !back);
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.value = back ? 1 : 0;
    } else {
      animation.animateTo(back ? 1 : 0, curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final angle = animation.value * math.pi;
          final showingBack = animation.value >= .5;
          final foreground = widget.light ? ink : _paper;
          return Transform(
            alignment: Alignment.center,
            transform:
                Matrix4.identity()
                  ..setEntry(3, 2, .001)
                  ..rotateY(angle - (showingBack ? math.pi : 0)),
            child: Semantics(
              button: true,
              label:
                  '${widget.title}, ${showingBack ? 'weather details' : 'forecast'}. Tap to flip.',
              child: Material(
                color: widget.light ? const Color(0xffdcebd8) : _surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color:
                        widget.light
                            ? Colors.transparent
                            : const Color(0xff33554a),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('flip-${widget.id}'),
                  onTap: flip,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground.withValues(alpha: .8),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey(
                              '${widget.id}-${showingBack ? 'back' : 'front'}',
                            ),
                            child: showingBack ? widget.back : widget.front,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.flip,
                              size: 14,
                              color: foreground.withValues(alpha: .6),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                showingBack
                                    ? 'Tap for forecast'
                                    : 'Tap for rain & wind',
                                style: TextStyle(
                                  color: foreground.withValues(alpha: .7),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CurrentFront extends StatelessWidget {
  const _CurrentFront({required this.forecast, required this.settings});
  final Forecast forecast;
  final Settings settings;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Expanded(
        child: Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  settings.temperature(forecast.temperature),
                  style: const TextStyle(
                    color: ink,
                    fontSize: 72,
                    fontWeight: FontWeight.w300,
                    height: 1,
                    letterSpacing: -4,
                  ),
                ),
              ),
            ),
            Icon(
              weatherIcon(forecast.summary),
              size: 46,
              color: const Color(0xffa9793d),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      Text(
        forecast.summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: ink,
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
      ),
      if (forecast.days.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            'High ${settings.temperature(forecast.days.first.high)}  ·  Low ${settings.temperature(forecast.days.first.low)}',
            style: const TextStyle(color: Color(0xff4d6a59), fontSize: 11),
          ),
        ),
    ],
  );
}

class _Detail {
  const _Detail(this.label, this.value, this.icon, {this.note});
  final String label, value;
  final IconData icon;
  final String? note;
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.items, this.light = false});
  final List<_Detail> items;
  final bool light;
  @override
  Widget build(BuildContext context) {
    final fg = light ? ink : _paper;
    return LayoutBuilder(
      builder:
          (context, bounds) => Wrap(
            spacing: 12,
            runSpacing: 8,
            children:
                items
                    .map(
                      (item) => SizedBox(
                        width: (bounds.maxWidth - 12) / 2,
                        height:
                            items.length > 2
                                ? (bounds.maxHeight - 8) / 2
                                : bounds.maxHeight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  item.icon,
                                  size: 12,
                                  color: fg.withValues(alpha: .65),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: fg.withValues(alpha: .75),
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                item.value,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (item.value == '—')
                              Text(
                                'Not reported',
                                style: TextStyle(
                                  color: fg.withValues(alpha: .65),
                                  fontSize: 9,
                                ),
                              )
                            else if (items.length == 2 && item.note != null)
                              Text(
                                item.note!,
                                style: TextStyle(
                                  color: fg.withValues(alpha: .65),
                                  fontSize: 9,
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
          ),
    );
  }
}

class _HoursFront extends StatelessWidget {
  const _HoursFront({required this.hours, required this.settings});
  final List<HourForecast> hours;
  final Settings settings;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final h in hours)
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                DateFormat(
                  'ha',
                ).format(settings.place.local(h.time)).toLowerCase(),
                style: const TextStyle(color: _soft, fontSize: 11),
              ),
              Icon(
                weatherIcon(h.summary),
                size: 24,
                color: const Color(0xffedbf82),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  settings.temperature(h.temperature),
                  style: const TextStyle(
                    color: _paper,
                    fontSize: 23,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

class _HoursBack extends StatelessWidget {
  const _HoursBack({required this.hours, required this.settings});
  final List<HourForecast> hours;
  final Settings settings;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      for (final h in hours)
        Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                DateFormat(
                  'ha',
                ).format(settings.place.local(h.time)).toLowerCase(),
                style: const TextStyle(color: _soft, fontSize: 11),
              ),
            ),
            const Icon(Icons.water_drop_outlined, color: _soft, size: 12),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                probability(h.rain),
                style: const TextStyle(color: _paper, fontSize: 12),
              ),
            ),
            const Icon(Icons.air, color: _soft, size: 13),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                settings.wind(h.wind),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _paper, fontSize: 12),
              ),
            ),
          ],
        ),
    ],
  );
}

class _DayFront extends StatelessWidget {
  const _DayFront({required this.day, required this.settings});
  final DayForecast day;
  final Settings settings;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Expanded(
        child: Row(
          children: [
            Icon(
              weatherIcon(day.summary),
              size: 34,
              color: const Color(0xffedbf82),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  settings.temperature(day.high),
                  style: const TextStyle(
                    color: _paper,
                    fontSize: 42,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),
            Text(
              settings.temperature(day.low),
              style: const TextStyle(
                color: _soft,
                fontSize: 25,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
      Text(
        day.summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _paper, fontSize: 13),
      ),
    ],
  );
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
