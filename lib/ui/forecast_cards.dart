import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import 'flip_weather_card.dart';
import 'forecast_chart_data.dart';
import 'weather_charts.dart';
import 'weather_style.dart';

const _paper = Color(0xffe7f0df);

class CurrentWeatherCard extends StatelessWidget {
  const CurrentWeatherCard({
    super.key,
    required this.forecast,
    required this.settings,
    required this.now,
    required this.height,
    this.compact = false,
  });
  final Forecast forecast;
  final Settings settings;
  final DateTime now;
  final double height;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final range = upcomingChartRange(now);
    final hours = range.hoursFrom(forecast);
    final today = todayForecast(forecast, settings.place, now);
    return FlipWeatherCard(
      id: 'current',
      storageId: '${settings.place.id}-${forecast.source.name}-current',
      title:
          '${forecast.source == WeatherSource.nws ? 'CURRENT FORECAST' : 'RIGHT NOW'} · °${settings.fahrenheit ? 'F' : 'C'} · NEXT 24H',
      light: true,
      height: height,
      front: _CurrentFront(
        forecast: forecast,
        settings: settings,
        hours: hours,
        range: range,
        today: today,
        compact: compact,
      ),
      back: _PrecipitationBack(
        hours: hours,
        range: range,
        settings: settings,
        probabilityValue: hours.firstOrNull?.rain,
        metrics: [
          CardMetric('Wind', settings.wind(forecast.wind)),
          CardMetric('Humidity', probability(forecast.humidity)),
          CardMetric('Feels like', settings.temperature(forecast.feelsLike)),
        ],
      ),
    );
  }
}

class HourlyForecastStrip extends StatelessWidget {
  const HourlyForecastStrip({
    super.key,
    required this.hours,
    required this.settings,
    this.compact = false,
  });
  final List<HourForecast> hours;
  final Settings settings;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final scale =
        MediaQuery.textScalerOf(context).scale(1).clamp(1, 2.5).toDouble();
    final divider = compact ? const Color(0xff385149) : const Color(0xffe0e8df);
    return Container(
      decoration: BoxDecoration(
        color: compact ? const Color(0xff233d36) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      clipBehavior: Clip.antiAlias,
      height: 96 * scale,
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
            (_, i) => _HourPip(
              key: ValueKey('hour-pip-${hours[i].time.toIso8601String()}'),
              hour: hours[i],
              settings: settings,
              first: i == 0,
              dark: compact,
              width: 60 * scale.clamp(1, 1.8),
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
    final divider = compact ? const Color(0xff385149) : const Color(0xffe0e8df);
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
        color: compact ? const Color(0xff233d36) : Colors.white,
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
                                    fontSize: 10,
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
                            style: TextStyle(color: fg, fontSize: 11),
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
    required this.today,
    required this.compact,
  });
  final Forecast forecast;
  final Settings settings;
  final List<HourForecast> hours;
  final ForecastChartRange range;
  final DayForecast? today;
  final bool compact;
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
                    settings.temperature(forecast.temperature),
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
                  child: Icon(
                    weatherIcon(forecast.summary),
                    size: compact ? 42 : 72,
                    color: const Color(0xffa9793d),
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          forecast.summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ink,
            fontSize: compact ? 14 : 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (!compact)
          Text(
            '${forecast.source == WeatherSource.nws ? 'Forecast for' : 'Observed at'} ${DateFormat('h:mm a').format(settings.place.local(forecast.observedAt))}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        const SizedBox(height: 3),
        SizedBox(
          height: (compact ? 44 : 76) * scale,
          child: TemperatureRangeChart(
            hours: hours,
            range: range,
            settings: settings,
            high: today?.high,
            low: today?.low,
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
  });
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
            Icon(
              weatherIcon(hour.summary),
              size: 20,
              color:
                  lightText ? const Color(0xffffcb88) : const Color(0xffc29154),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                settings.temperature(hour.temperature),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            Text(
              probability(hour.rain),
              style: TextStyle(fontSize: 10, color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}
