import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'forecast_selection.dart';
import 'interaction_juice.dart';
import '../models.dart';
import '../sky.dart';
import 'sky_weather.dart';
import 'flip_weather_card.dart';
import 'forecast_chart_data.dart';
import 'weather_charts.dart';
import 'weather_style.dart';

const _paper = Color(0xffe8f2fc);

class CurrentWeatherCard extends StatefulWidget {
  const CurrentWeatherCard({
    super.key,
    required this.forecast,
    required this.settings,
    required this.now,
    required this.height,
    this.compact = false,
    this.selection,
  });
  final Forecast forecast;
  final Settings settings;
  final DateTime now;
  final double height;
  final bool compact;
  final ForecastSelectionController? selection;
  @override
  State<CurrentWeatherCard> createState() => _CurrentWeatherCardState();
}

class _StepHour extends Intent {
  const _StepHour(this.delta);
  final int delta;
}

class _CurrentWeatherCardState extends State<CurrentWeatherCard> {
  final ownSelection = ForecastSelectionController();
  @override
  void dispose() {
    ownSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.selection ?? ownSelection;
    final forecast = widget.forecast,
        settings = widget.settings,
        now = widget.now;
    final range = upcomingChartRange(now);
    final hours = range.hoursFrom(forecast);
    final identity = forecastSelectionIdentity(settings, forecast);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.selected(identity, hours);
        final time = selected?.time ?? now;
        void choose(HourForecast hour) => controller.choose(identity, hour);
        void step(int delta) {
          if (hours.isEmpty) return;
          final index =
              selected == null ? (delta > 0 ? -1 : 0) : hours.indexOf(selected);
          choose(hours[(index + delta).clamp(0, hours.length - 1)]);
        }

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
          child: FlipWeatherCard(
            id: 'current',
            storageId: '${settings.place.id}-${forecast.source.name}-current',
            title:
                selected == null
                    ? '${forecast.source == WeatherSource.nws ? 'CURRENT FORECAST' : 'RIGHT NOW'} · °${settings.fahrenheit ? 'F' : 'C'}'
                    : 'FORECAST · ${DateFormat('EEE h:mm a').format(settings.place.local(time))} ${settings.place.local(time).timeZoneName}',
            headerAction:
                selected == null
                    ? null
                    : TextButton(
                      onPressed: controller.showNow,
                      style: TextButton.styleFrom(
                        foregroundColor: ink,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(44, 36),
                      ),
                      child: const Text('Now'),
                    ),
            light: true,
            background:
                SkyPalette.at(
                  settings,
                  forecast,
                  time,
                  summary: selected?.summary,
                ).card,
            height: widget.height,
            front: _CurrentFront(
              forecast: forecast,
              settings: settings,
              hours: hours,
              range: range,
              compact: widget.compact,
              now: time,
              selected: selected,
              signal: controller.signal,
              onSelected: choose,
            ),
            back: _PrecipitationBack(
              hours: hours,
              range: range,
              settings: settings,
              selectedTime: selected?.time,
              onSelected: choose,
              probabilityValue:
                  selected == null ? hours.firstOrNull?.rain : selected.rain,
              metrics: [
                CardMetric(
                  'Wind',
                  settings.wind(
                    selected == null ? forecast.wind : selected.wind,
                  ),
                ),
                CardMetric(
                  'Humidity',
                  probability(
                    selected == null ? forecast.humidity : selected.humidity,
                  ),
                ),
                if (selected == null)
                  CardMetric(
                    'Feels like',
                    settings.temperature(forecast.feelsLike),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HourlyForecastStrip extends StatelessWidget {
  const HourlyForecastStrip({
    super.key,
    required this.hours,
    required this.settings,
    this.compact = false,
    this.selectedTime,
    this.onSelected,
  });
  final List<HourForecast> hours;
  final Settings settings;
  final bool compact;
  final DateTime? selectedTime;
  final ValueChanged<HourForecast>? onSelected;
  @override
  Widget build(BuildContext context) {
    final scale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1, 2.5).toDouble();
    final divider = compact ? const Color(0xff3d5972) : const Color(0xffd5e3ee);
    return Container(
      decoration: BoxDecoration(
        color: compact ? const Color(0xff203e59) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      clipBehavior: Clip.antiAlias,
      height: 108 * scale,
      child: ListView.separated(
        key: const PageStorageKey('hourly-pips'),
        scrollDirection: Axis.horizontal,
        itemCount: hours.length,
        separatorBuilder:
            (_, _) => VerticalDivider(
              width: 1,
              thickness: 1,
              indent: 8,
              endIndent: 8,
              color: divider,
            ),
        itemBuilder:
            (_, i) => Semantics(
              selected: selectedTime == hours[i].time,
              button: onSelected != null,
              child: ElasticInteraction(
                enabled: onSelected != null,
                builder:
                    (context, pose) => InkWell(
                      onTap:
                          onSelected == null
                              ? null
                              : () => onSelected!(hours[i]),
                      child: _HourPip(
                        key: ValueKey(
                          'hour-pip-${hours[i].time.toIso8601String()}',
                        ),
                        hour: hours[i],
                        settings: settings,
                        first:
                            selectedTime == null
                                ? i == 0
                                : selectedTime == hours[i].time,
                        dark: compact,
                        width: 60 * scale.clamp(1, 1.8),
                      ),
                    ),
              ),
            ),
      ),
    );
  }
}

class DailyForecastList extends StatelessWidget {
  const DailyForecastList({
    super.key,
    required this.forecast,
    required this.settings,
    this.compact = false,
  });
  final Forecast forecast;
  final Settings settings;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final fg = compact ? _paper : ink;
    final secondary = compact ? _paper.withValues(alpha: .65) : muted;
    final divider = compact ? const Color(0xff3d5972) : const Color(0xffd5e3ee);
    final scale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5).toDouble();
    Widget reading(double? value, {bool low = false}) => SizedBox(
      width: 36 * scale,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          settings.temperature(value),
          style: TextStyle(
            color: low ? secondary : fg,
            fontSize: 16,
            fontWeight: low ? FontWeight.w400 : FontWeight.w600,
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: compact ? const Color(0xff203e59) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < forecast.days.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 12,
                endIndent: 12,
                color: divider,
              ),
            Builder(
              builder: (context) {
                final day = forecast.days[i];
                final date = forecastDayDate(day, forecast, settings.place);
                return Semantics(
                  key: ValueKey('forecast-day-$i'),
                  label:
                      '${forecastDayHeading(day, forecast, settings.place)}, ${day.summary}, high ${settings.temperature(day.high)}, low ${settings.temperature(day.low)}',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 54 * scale,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                date == null
                                    ? day.label
                                    : DateFormat('EEE').format(date),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  height: 1.1,
                                ),
                              ),
                              if (date != null)
                                Text(
                                  DateFormat('MMM d').format(date),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: secondary,
                                    fontSize: 11,
                                    height: 1.1,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          weatherIcon(day.summary),
                          size: 18,
                          color:
                              compact
                                  ? const Color(0xffedbf82)
                                  : const Color(0xffb47b3e),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            day.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: fg, fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        reading(day.high),
                        const SizedBox(width: 6),
                        reading(day.low, low: true),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrentFront extends StatelessWidget {
  const _CurrentFront({
    required this.forecast,
    required this.settings,
    required this.hours,
    required this.range,
    required this.compact,
    required this.now,
    this.selected,
    required this.signal,
    required this.onSelected,
  });
  final HourForecast? selected;
  final int signal;
  final ValueChanged<HourForecast> onSelected;
  final Forecast forecast;
  final Settings settings;
  final List<HourForecast> hours;
  final ForecastChartRange range;
  final bool compact;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final scale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1, 2).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    settings.temperature(
                      selected == null
                          ? forecast.temperature
                          : selected!.temperature.isFinite
                          ? selected!.temperature
                          : null,
                    ),
                    style: TextStyle(
                      color: ink,
                      fontSize: compact ? 72 : 98,
                      fontWeight: FontWeight.w300,
                      height: 1,
                      letterSpacing: -4,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ElasticArt(
                    gain: 2,
                    child: ElasticPulse(
                      signal: signal,
                      child:
                          SolarDay.at(
                                    settings.place,
                                    now,
                                    forecast,
                                  ).nightAt(now) &&
                                  conditionKind(
                                        selected?.summary ?? forecast.summary,
                                      ) ==
                                      'sun'
                              ? MoonDisc(
                                phase: moonPhase(now),
                                southern: settings.place.latitude < 0,
                                size: compact ? 42 : 72,
                              )
                              : Icon(
                                weatherIcon(
                                  selected?.summary ?? forecast.summary,
                                ),
                                size: compact ? 42 : 72,
                                color: const Color(0xff387da9),
                              ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          selected?.summary ?? forecast.summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ink,
            fontSize: compact ? 14 : 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (!compact || selected != null)
          Text(
            selected != null
                ? '${probability(selected!.rain)} rain chance'
                : '${forecast.source == WeatherSource.nws ? 'Forecast for' : 'Observed at'} ${DateFormat('h:mm a').format(settings.place.local(forecast.observedAt))}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        const SizedBox(height: 3),
        SizedBox(
          height: (compact ? 44 : 76) * scale,
          child: TemperatureRangeChart(
            selectedTime: selected?.time,
            onSelected: onSelected,
            hours: hours,
            range: range,
            settings: settings,
          ),
        ),
      ],
    );
  }
}

class CardMetric {
  const CardMetric(this.label, this.value);
  final String label, value;
}

class _PrecipitationBack extends StatelessWidget {
  const _PrecipitationBack({
    required this.hours,
    required this.settings,
    required this.metrics,
    this.range,
    this.probabilityValue,
    this.selectedTime,
    this.onSelected,
  });
  final DateTime? selectedTime;
  final ValueChanged<HourForecast>? onSelected;
  final List<HourForecast> hours;
  final ForecastChartRange? range;
  final Settings settings;
  final List<CardMetric> metrics;
  final double? probabilityValue;
  @override
  Widget build(BuildContext context) {
    const fg = ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.water_drop_outlined,
              size: 13,
              color: fg.withValues(alpha: .65),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                'Precipitation chance',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg.withValues(alpha: .75),
                  fontSize: 10,
                ),
              ),
            ),
            Text(
              probability(probabilityValue),
              style: TextStyle(
                color: fg,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: WeatherChart(
            key: const ValueKey('precipitation-graph'),
            selectedTime: selectedTime,
            onSelected: onSelected,
            hours: hours,
            range: range,
            settings: settings,
            kind: WeatherChartKind.precipitation,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final metric in metrics)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg.withValues(alpha: .65),
                          fontSize: 9,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          metric.value,
                          style: TextStyle(
                            color: fg,
                            fontSize: metrics.length > 3 ? 13 : 17,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (metric.value == '—')
                        Text(
                          'Not reported',
                          maxLines: 1,
                          style: TextStyle(
                            color: fg.withValues(alpha: .65),
                            fontSize: 8,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HourPip extends StatelessWidget {
  const _HourPip({
    super.key,
    required this.hour,
    required this.settings,
    required this.first,
    required this.dark,
    required this.width,
  });
  final HourForecast hour;
  final Settings settings;
  final bool first, dark;
  final double width;
  @override
  Widget build(BuildContext context) {
    final lightText = first || dark;
    final fg = lightText ? _paper : ink;
    final secondary = lightText ? _paper.withValues(alpha: .7) : muted;
    return Semantics(
      label: '${hour.summary}, precipitation chance ${probability(hour.rain)}',
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        color: first ? ink : Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat(
                'ha',
              ).format(settings.place.local(hour.time)).toLowerCase(),
              style: TextStyle(fontSize: 11, color: secondary),
            ),
            ElasticArt(
              child:
                  SolarDay.at(settings.place, hour.time).nightAt(hour.time) &&
                          conditionKind(hour.summary) == 'sun'
                      ? ExcludeSemantics(
                        child: MoonDisc(
                          phase: moonPhase(hour.time),
                          southern: settings.place.latitude < 0,
                          size: 20,
                        ),
                      )
                      : Icon(
                        weatherIcon(hour.summary),
                        size: 20,
                        color:
                            lightText
                                ? const Color(0xffffcb88)
                                : const Color(0xffc29154),
                      ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                hour.temperature.isFinite
                    ? settings.temperature(hour.temperature)
                    : '—',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            Text(
              probability(hour.rain),
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}
