import 'package:intl/intl.dart';
import 'models.dart';

/// One cached snapshot shared by all three native widget sizes.
const widgetProviders = [
  'TemperatureWidgetProvider',
  'SummaryWidgetProvider',
  'WeatherWidgetProvider',
];

Json widgetPayload(Settings settings, Forecast? forecast, DateTime now) {
  final fetchedDay =
      forecast == null ? null : settings.place.local(forecast.fetchedAt);
  final dateFormat = DateFormat('yyyy-MM-dd');
  return {
    'place': settings.place.name,
    'timeZone': settings.place.timezone,
    'unit': settings.fahrenheit ? 'F' : 'C',
    'temperature': settings.temperature(forecast?.temperature),
    'summary': forecast?.summary ?? 'Tap to set up',
    'source': forecast?.source.label ?? 'Daybreak',
    'wind': settings.wind(forecast?.wind),
    'fetchedAt': forecast?.fetchedAt.millisecondsSinceEpoch ?? 0,
    'observedAt': forecast?.observedAt.millisecondsSinceEpoch ?? 0,
    'days':
        forecast?.days.map((day) {
          // Old caches do not carry dates. Only infer the issue day's range when
          // its label explicitly matches; never borrow tomorrow's high or low.
          final label = day.label.toLowerCase();
          final legacyToday =
              fetchedDay != null &&
              (label == 'today' ||
                  label == 'tonight' ||
                  label == DateFormat('EEEE').format(fetchedDay).toLowerCase());
          return {
            'date':
                day.date ??
                (legacyToday ? dateFormat.format(fetchedDay) : null),
            'high': settings.temperature(day.high),
            'low': settings.temperature(day.low),
          };
        }).toList() ??
        [],
    'hours':
        forecast
            ?.upcoming(now)
            .map(
              (hour) => {
                'timestamp': hour.time.millisecondsSinceEpoch,
                'time':
                    DateFormat(
                      'ha',
                    ).format(settings.place.local(hour.time)).toLowerCase(),
                'temperature':
                    settings.fahrenheit
                        ? hour.temperature * 9 / 5 + 32
                        : hour.temperature,
                'temperatureText': settings.temperature(hour.temperature),
                'rain': hour.rain == null ? null : '${hour.rain!.round()}%',
              },
            )
            .toList() ??
        [],
    'alerts': [
      for (final alert in forecast?.alerts ?? <WeatherAlert>[])
        if (alert.expires == null || alert.expires!.isAfter(now))
          widgetAdvisory(alert),
    ],
    'kind': forecast == null ? 'unknown' : conditionKind(forecast.summary),
  };
}

Json widgetAdvisory(WeatherAlert alert) {
  final type = (alert.type.isEmpty ? alert.title : alert.type).toLowerCase();
  final label =
      type.contains('warning')
          ? 'Warning'
          : type.contains('watch')
          ? 'Watch'
          : type.contains('advisory')
          ? 'Advisory'
          : 'Alert';
  final officialColour = alert.colour.trim().toLowerCase();
  final colour =
      const ['red', 'orange', 'yellow'].contains(officialColour)
          ? officialColour
          : switch (label) {
            'Warning' => 'red',
            'Watch' => 'orange',
            'Advisory' => 'yellow',
            _ => 'blue',
          };
  return {
    'title': alert.title,
    'label': label,
    'colour': colour,
    'expires': alert.expires?.millisecondsSinceEpoch,
  };
}
