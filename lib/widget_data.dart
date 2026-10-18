import 'package:intl/intl.dart';
import 'models.dart';

/// One cached snapshot shared by all three native widget sizes.
const widgetProviders = [
  'TemperatureWidgetProvider',
  'SummaryWidgetProvider',
  'WeatherWidgetProvider',
];

Json widgetPayload(Settings settings, Forecast? forecast, DateTime now) => {
  'place': settings.place.name,
  'unit': settings.fahrenheit ? 'F' : 'C',
  'temperature': settings.temperature(forecast?.temperature),
  'summary': forecast?.summary ?? 'Tap to set up',
  'source': forecast?.source.label ?? 'Daybreak',
  'wind': settings.wind(forecast?.wind),
  'fetchedAt': forecast?.fetchedAt.millisecondsSinceEpoch ?? 0,
  'observedAt': forecast?.observedAt.millisecondsSinceEpoch ?? 0,
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
              'rain': hour.rain == null ? null : '${hour.rain!.round()}%',
            },
          )
          .toList() ??
      [],
  'kind': forecast == null ? 'unknown' : conditionKind(forecast.summary),
};
