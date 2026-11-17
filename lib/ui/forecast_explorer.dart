import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../sky.dart';
import 'forecast_cards.dart';
import 'forecast_chart_data.dart';
import 'sky_weather.dart';
import 'weather_charts.dart';
import 'weather_style.dart';

/// A view-only selection: exploring the forecast never requests or edits data.
class ForecastExplorer extends StatefulWidget {
  const ForecastExplorer({
    super.key,
    required this.forecast,
    required this.settings,
    required this.now,
    this.compact = false,
  });
  final Forecast forecast;
  final Settings settings;
  final DateTime now;
  final bool compact;

  @override
  State<ForecastExplorer> createState() => _ForecastExplorerState();
}

class _StepHour extends Intent {
  const _StepHour(this.delta);
  final int delta;
}

class _ForecastExplorerState extends State<ForecastExplorer> {
  DateTime? selected;
  String get storageKey =>
      'forecast-hour-${widget.settings.place.id}-${widget.forecast.source.name}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    selected ??=
        PageStorage.maybeOf(context)?.readState(context, identifier: storageKey)
            as DateTime?;
  }

  @override
  void didUpdateWidget(covariant ForecastExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.place.id != widget.settings.place.id ||
        oldWidget.forecast.source != widget.forecast.source) {
      selected = null;
    }
  }

  void choose(HourForecast hour) {
    if (selected == hour.time) return;
    setState(() => selected = hour.time);
    PageStorage.maybeOf(
      context,
    )?.writeState(context, hour.time, identifier: storageKey);
  }

  @override
  Widget build(BuildContext context) {
    final range = upcomingChartRange(widget.now);
    final hours = range.hoursFrom(widget.forecast);
    if (hours.isEmpty) return const SizedBox.shrink();
    final index = math.max(0, hours.indexWhere((h) => h.time == selected));
    final hour = hours[index];
    void step(int delta) =>
        choose(hours[(index + delta).clamp(0, hours.length - 1)]);
    final local = widget.settings.place.local(hour.time);
    final time =
        '${DateFormat('EEE, h:mm a').format(local)} ${local.timeZoneName}';
    final reading =
        '${hour.temperature.isFinite ? widget.settings.temperature(hour.temperature) : '—'} · '
        '${hour.rain == null || !hour.rain!.isFinite ? 'Rain chance unavailable' : '${probability(hour.rain)} rain'}';
    final fg = widget.compact ? const Color(0xffe8f2fc) : ink;
    final secondary = widget.compact ? const Color(0xffbfd6ea) : muted;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final night = SolarDay.at(
      widget.settings.place,
      hour.time,
      widget.forecast,
    ).nightAt(hour.time);
    final progress = local.hour / 24 + local.minute / 1440;
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowLeft): _StepHour(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): _StepHour(1),
      },
      actions: {
        _StepHour: CallbackAction<_StepHour>(
          onInvoke: (intent) {
            step(intent.delta);
            return null;
          },
        ),
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Earlier forecast hour',
                color: fg,
                onPressed: index > 0 ? () => step(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: '$time, $reading, ${hour.summary}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        time,
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                      Text(
                        reading,
                        style: TextStyle(
                          color: fg,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ExcludeSemantics(
                child: SizedBox(
                  width: 48,
                  height: 38,
                  child: CustomPaint(
                    painter: _HourArc(secondary),
                    child: Align(
                      alignment: Alignment(
                        2 * progress - 1,
                        .6 - 1.3 * math.sin(math.pi * progress),
                      ),
                      child:
                          night
                              ? MoonDisc(
                                phase: moonPhase(hour.time),
                                southern: widget.settings.place.latitude < 0,
                                size: 18,
                              )
                              : Icon(
                                Icons.wb_sunny_outlined,
                                color: fg,
                                size: 18,
                              ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Later forecast hour',
                color: fg,
                onPressed: index < hours.length - 1 ? () => step(1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SizedBox(
              height: 96 * scale,
              child: WeatherChart(
                key: const ValueKey('forecast-explorer-chart'),
                hours: hours,
                settings: widget.settings,
                kind: WeatherChartKind.temperature,
                dark: widget.compact,
                range: range,
                selectedTime: hour.time,
                onSelected: choose,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 10),
            child: Text(
              'Drag the forecast or choose an hour',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
          ),
          HourlyForecastStrip(
            hours: hours,
            settings: widget.settings,
            compact: widget.compact,
            selectedTime: hour.time,
            onSelected: choose,
          ),
        ],
      ),
    );
  }
}

/// A small time-of-day illustration, not a predicted sky position.
class _HourArc extends CustomPainter {
  _HourArc(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p =
        Paint()
          ..color = color.withValues(alpha: .35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    canvas.drawArc(
      Rect.fromLTWH(9, 12, size.width - 18, 26),
      math.pi,
      math.pi,
      false,
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _HourArc old) => old.color != color;
}
