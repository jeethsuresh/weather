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
          '${forecast.source == WeatherSource.nws ? 'CURRENT FORECAST' : 'RIGHT NOW'} · °${settings.fahrenheit ? 'F' : 'C'}',
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
    return SizedBox(
      height: (compact ? 132 : 150) * scale,
      child: ListView.separated(
        key: const PageStorageKey('hourly-pips'),
        scrollDirection: Axis.horizontal,
        itemCount: hours.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder:
            (_, i) => _HourPip(
              key: ValueKey('hour-pip-${hours[i].time.toIso8601String()}'),
              hour: hours[i],
              settings: settings,
              first: i == 0,
              dark: compact,
              width: 72 * scale.clamp(1, 1.5),
            ),
      ),
    );
  }
}

class DailyWeatherCard extends StatelessWidget {
  const DailyWeatherCard({
    super.key,
    required this.forecast,
    required this.day,
    required this.index,
    required this.settings,
    required this.now,
    required this.height,
    this.compact = false,
  });
  final Forecast forecast;
  final DayForecast day;
  final int index;
  final Settings settings;
  final DateTime now;
  final double height;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final range = chartRangeForDay(forecast, day, settings.place, now);
    final hours = range?.hoursFrom(forecast) ?? <HourForecast>[];
    final fg = compact ? _paper : ink;
    final date = forecastDayDate(day, forecast, settings.place);
    return FlipWeatherCard(
      id: 'day-$index',
      storageId:
          '${settings.place.id}-${forecast.source.name}-day-${date ?? day.label}',
      title: forecastDayHeading(day, forecast, settings.place).toUpperCase(),
      paper: !compact,
      height: height,
      front: Column(
        children: [
          Row(
            children: [
              Icon(
                weatherIcon(day.summary),
                size: 26,
                color:
                    compact ? const Color(0xffedbf82) : const Color(0xffb47b3e),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  day.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TemperatureRangeChart(
              hours: hours,
              range: range,
              settings: settings,
              high: day.high,
              low: day.low,
              dark: compact,
            ),
          ),
        ],
      ),
      back: _PrecipitationBack(
        hours: hours,
        range: range,
        settings: settings,
        dark: compact,
        probabilityValue: day.rain,
        daily: true,
        metrics: [
          CardMetric('Peak wind', settings.wind(day.windMax)),
          CardMetric('Forecast chance', probability(day.rain)),
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
    this.dark = false,
    this.daily = false,
  });
  final List<HourForecast> hours;
  final ForecastChartRange? range;
  final Settings settings;
  final List<CardMetric> metrics;
  final double? probabilityValue;
  final bool dark, daily;
  @override
  Widget build(BuildContext context) {
    final fg = dark ? _paper : ink;
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
                daily ? 'Daily precipitation chance' : 'Precipitation chance',
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
            dark: dark,
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
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
        decoration: BoxDecoration(
          color:
              first
                  ? ink
                  : dark
                  ? const Color(0xff233d36)
                  : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border:
              first
                  ? null
                  : Border.all(
                    color:
                        dark
                            ? const Color(0xff385149)
                            : const Color(0xffe9ede5),
                  ),
        ),
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
              size: 24,
              color:
                  lightText ? const Color(0xffffcb88) : const Color(0xffc29154),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                settings.temperature(hour.temperature),
                style: TextStyle(
                  fontSize: 22,
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
