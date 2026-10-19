import 'package:intl/intl.dart';
import '../models.dart';

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
    forecast.hours
        .where(
          (hour) =>
              hour.time.isAfter(now.subtract(const Duration(minutes: 30))) &&
              !hour.time.isAfter(now.add(const Duration(hours: 12))),
        )
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));

List<HourForecast> chartHoursForDay(
  Forecast forecast,
  DayForecast day,
  Place place,
  DateTime now,
) {
  final date = forecastDayDate(day, forecast, place);
  if (date == null) return [];
  return forecast.hours
      .where(
        (hour) =>
            hour.time.isAfter(now.subtract(const Duration(minutes: 30))) &&
            sameCalendarDay(place.local(hour.time), date),
      )
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));
}

double? highestHour(Iterable<HourForecast> hours) =>
    hours.isEmpty
        ? null
        : hours.map((h) => h.temperature).reduce((a, b) => a > b ? a : b);
double? lowestHour(Iterable<HourForecast> hours) =>
    hours.isEmpty
        ? null
        : hours.map((h) => h.temperature).reduce((a, b) => a < b ? a : b);
String probability(double? value) => value == null ? '—' : '${value.round()}%';
