import 'package:intl/intl.dart';
import '../models.dart';

class ForecastChartRange {
  ForecastChartRange(this.start, this.end) : assert(end.isAfter(start));
  final DateTime start, end;

  List<HourForecast> hoursFrom(Forecast forecast) =>
      forecast.hours
          .where(
            (hour) => !hour.time.isBefore(start) && !hour.time.isAfter(end),
          )
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
}

ForecastChartRange upcomingChartRange(DateTime now) =>
    ForecastChartRange(now, now.add(const Duration(hours: 24)));

DateTime? forecastDayDate(DayForecast day, Forecast forecast, Place place) {
  final explicit = DateTime.tryParse(day.date ?? '');
  if (explicit != null) {
    return DateTime.utc(explicit.year, explicit.month, explicit.day);
  }
  // Support caches created before provider calendar dates were stored.
  final issued = place.local(forecast.fetchedAt);
  final base = DateTime.utc(issued.year, issued.month, issued.day);
  final label = day.label.toLowerCase();
  if (label == 'today' || label == 'tonight' || label.startsWith('this ')) {
    return base;
  }
  const weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final index = weekdays.indexWhere((name) => label.startsWith(name));
  return index < 0
      ? null
      : base.add(Duration(days: (index + 1 - base.weekday + 7) % 7));
}

String forecastDayHeading(DayForecast day, Forecast forecast, Place place) {
  final date = forecastDayDate(day, forecast, place);
  return date == null ? day.label : DateFormat('EEEE · MMM d').format(date);
}

bool sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

DayForecast? todayForecast(Forecast forecast, Place place, DateTime now) {
  final local = place.local(now);
  for (final day in forecast.days) {
    final date = forecastDayDate(day, forecast, place);
    if (date != null && sameCalendarDay(date, local)) return day;
  }
  return null;
}

List<HourForecast> upcomingChartHours(Forecast forecast, DateTime now) =>
    upcomingChartRange(now).hoursFrom(forecast);

String probability(double? value) => value == null ? '—' : '${value.round()}%';
