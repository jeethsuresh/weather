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
    final hours = upcomingChartHours(forecast, now);
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
        today: today,
        compact: compact,
      ),
      back: _PrecipitationBack(
        hours: hours,
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

class HoursWeatherCard extends StatelessWidget {
  const HoursWeatherCard({
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
    final hours = upcomingChartHours(forecast, now);
    return FlipWeatherCard(
      id: 'hours',
      storageId: '${settings.place.id}-${forecast.source.name}-hours',
      title: 'THE NEXT 12 HOURS',
      paper: !compact,
      height: height,
      front: Column(
        children: [
          Expanded(
            child: TemperatureRangeChart(
              hours: hours,
              settings: settings,
              high: highestHour(hours),
              low: lowestHour(hours),
              dark: compact,
            ),
          ),
          const SizedBox(height: 6),
          _HourReadings(
            hours: hours.take(4).toList(),
            settings: settings,
            dark: compact,
          ),
        ],
      ),
      back: _PrecipitationBack(
        hours: hours,
        settings: settings,
        dark: compact,
        probabilityValue: hours.firstOrNull?.rain,
        metrics:
            hours
                .take(4)
                .map(
                  (h) => CardMetric(
                    DateFormat(
                      'ha',
                    ).format(settings.place.local(h.time)).toLowerCase(),
                    settings.wind(h.wind),
                  ),
                )
                .toList(),
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
    final hours = chartHoursForDay(forecast, day, settings.place, now);
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
    required this.today,
    required this.compact,
  });
  final Forecast forecast;
  final Settings settings;
  final List<HourForecast> hours;
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
    this.probabilityValue,
    this.dark = false,
    this.daily = false,
  });
  final List<HourForecast> hours;
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

class _HourReadings extends StatelessWidget {
  const _HourReadings({
    required this.hours,
    required this.settings,
    required this.dark,
  });
  final List<HourForecast> hours;
  final Settings settings;
  final bool dark;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final hour in hours)
        Expanded(
          child: Column(
            children: [
              Text(
                DateFormat(
                  'ha',
                ).format(settings.place.local(hour.time)).toLowerCase(),
                style: TextStyle(
                  color: dark ? _paper.withValues(alpha: .65) : muted,
                  fontSize: 9,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  settings.temperature(hour.temperature),
                  style: TextStyle(
                    color: dark ? _paper : ink,
                    fontSize: 17,
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
