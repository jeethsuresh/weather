import 'package:timezone/timezone.dart' as tz;

typedef Json = Map<String, dynamic>;

enum WeatherSource {
  auto('Automatic', 'National service first, Open-Meteo as fallback'),
  canada('Environment Canada', 'Canadian observations and forecasts'),
  nws('US National Weather Service', 'Official US forecasts'),
  openMeteo('Open-Meteo', 'Worldwide forecast · free for personal use');

  const WeatherSource(this.label, this.description);
  final String label;
  final String description;
}

class Place {
  const Place({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.country,
    required this.timezone,
    this.region = '',
    this.canadaSite,
    this.isCurrentLocation = false,
    this.accuracyMeters,
  });
  static const toronto = Place(
    name: 'Toronto',
    latitude: 43.6532,
    longitude: -79.3832,
    country: 'CA',
    timezone: 'America/Toronto',
    region: 'Ontario',
    canadaSite: 'on-143',
  );
  final String name, country, timezone, region;
  final String? canadaSite;
  final double latitude, longitude;
  final bool isCurrentLocation;
  final double? accuracyMeters;
  String get id =>
      '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';
  String get subtitle =>
      [region, country].where((s) => s.isNotEmpty).join(', ');
  DateTime local(DateTime date) {
    try {
      return tz.TZDateTime.from(date, tz.getLocation(timezone));
    } catch (_) {
      return date.toUtc();
    }
  }

  Json toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'country': country,
    'timezone': timezone,
    'region': region,
    'canadaSite': canadaSite,
    'isCurrentLocation': isCurrentLocation,
    'accuracyMeters': accuracyMeters,
  };
  factory Place.fromJson(Json j) => Place(
    name: j['name'],
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    country: j['country'],
    timezone: j['timezone'] ?? 'UTC',
    region: j['region'] ?? '',
    canadaSite: j['canadaSite'],
    isCurrentLocation: j['isCurrentLocation'] ?? false,
    accuracyMeters: number(j['accuracyMeters']),
  );
}

class Settings {
  const Settings({
    this.place = Place.toronto,
    this.source = WeatherSource.auto,
    this.fahrenheit = false,
    this.hourly = true,
  });
  final Place place;
  final WeatherSource source;
  final bool fahrenheit, hourly;
  String get cacheKey => 'forecast.v1.${place.id}.${source.name}';
  Settings copyWith({
    Place? place,
    WeatherSource? source,
    bool? fahrenheit,
    bool? hourly,
  }) => Settings(
    place: place ?? this.place,
    source: source ?? this.source,
    fahrenheit: fahrenheit ?? this.fahrenheit,
    hourly: hourly ?? this.hourly,
  );
  String temperature(double? c) =>
      c == null ? '—' : '${(fahrenheit ? c * 9 / 5 + 32 : c).round()}°';
  String wind(double? kmh) =>
      kmh == null
          ? '—'
          : '${(fahrenheit ? kmh / 1.609344 : kmh).round()} ${fahrenheit ? 'mph' : 'km/h'}';
  Json toJson() => {
    'place': place.toJson(),
    'source': source.name,
    'fahrenheit': fahrenheit,
    'hourly': hourly,
  };
  factory Settings.fromJson(Json j) => Settings(
    place: Place.fromJson(j['place']),
    source: WeatherSource.values.firstWhere(
      (s) => s.name == j['source'],
      orElse: () => WeatherSource.auto,
    ),
    fahrenheit: j['fahrenheit'] ?? false,
    hourly: j['hourly'] ?? true,
  );
}

class HourForecast {
  const HourForecast({
    required this.time,
    required this.temperature,
    required this.summary,
    this.rain,
    this.wind,
    this.humidity,
  });
  final DateTime time;
  final double temperature;
  final String summary;
  final double? rain, wind, humidity;
  Json toJson() => {
    'time': time.toIso8601String(),
    'temperature': temperature,
    'summary': summary,
    'rain': rain,
    'wind': wind,
    'humidity': humidity,
  };
  factory HourForecast.fromJson(Json j) => HourForecast(
    time: DateTime.parse(j['time']),
    temperature: (j['temperature'] as num).toDouble(),
    summary: j['summary'],
    rain: number(j['rain']),
    wind: number(j['wind']),
    humidity: number(j['humidity']),
  );
}

class DayForecast {
  const DayForecast({
    required this.label,
    required this.summary,
    this.high,
    this.low,
    this.rain,
    this.windMax,
  });
  final String label, summary;
  final double? high, low, rain, windMax;
  Json toJson() => {
    'label': label,
    'summary': summary,
    'high': high,
    'low': low,
    'rain': rain,
    'windMax': windMax,
  };
  factory DayForecast.fromJson(Json j) => DayForecast(
    label: j['label'],
    summary: j['summary'],
    high: number(j['high']),
    low: number(j['low']),
    rain: number(j['rain']),
    windMax: number(j['windMax']),
  );
}

class WeatherAlert {
  const WeatherAlert(this.title, this.detail, {this.expires});
  final String title, detail;
  final DateTime? expires;
  Json toJson() => {
    'title': title,
    'detail': detail,
    'expires': expires?.toIso8601String(),
  };
  factory WeatherAlert.fromJson(Json j) => WeatherAlert(
    j['title'],
    j['detail'],
    expires: DateTime.tryParse(j['expires'] ?? ''),
  );
}

class Forecast {
  const Forecast({
    required this.source,
    required this.fetchedAt,
    required this.observedAt,
    required this.temperature,
    required this.summary,
    required this.hours,
    required this.days,
    this.feelsLike,
    this.humidity,
    this.wind,
    this.sunrise,
    this.sunset,
    this.alerts = const [],
    this.notice,
    this.station,
  });
  final WeatherSource source;
  final DateTime fetchedAt, observedAt;
  final double temperature;
  final double? feelsLike, humidity, wind;
  final String summary;
  final List<HourForecast> hours;
  final List<DayForecast> days;
  final List<WeatherAlert> alerts;
  final DateTime? sunrise, sunset;
  final String? notice, station;
  bool staleAt(DateTime now) =>
      now.difference(fetchedAt) > const Duration(hours: 2) ||
      now.difference(observedAt) > const Duration(hours: 3);
  List<HourForecast> upcoming(DateTime now) =>
      hours
          .where(
            (h) => h.time.isAfter(now.subtract(const Duration(minutes: 30))),
          )
          .take(24)
          .toList();
  Json toJson() => {
    'source': source.name,
    'fetchedAt': fetchedAt.toIso8601String(),
    'observedAt': observedAt.toIso8601String(),
    'temperature': temperature,
    'summary': summary,
    'feelsLike': feelsLike,
    'humidity': humidity,
    'wind': wind,
    'hours': hours.map((h) => h.toJson()).toList(),
    'days': days.map((d) => d.toJson()).toList(),
    'alerts': alerts.map((a) => a.toJson()).toList(),
    'sunrise': sunrise?.toIso8601String(),
    'sunset': sunset?.toIso8601String(),
    'notice': notice,
    'station': station,
  };
  factory Forecast.fromJson(Json j) => Forecast(
    source: WeatherSource.values.byName(j['source']),
    fetchedAt: DateTime.parse(j['fetchedAt']),
    observedAt: DateTime.parse(j['observedAt']),
    temperature: (j['temperature'] as num).toDouble(),
    summary: j['summary'],
    feelsLike: number(j['feelsLike']),
    humidity: number(j['humidity']),
    wind: number(j['wind']),
    hours: (j['hours'] as List).map((h) => HourForecast.fromJson(h)).toList(),
    days: (j['days'] as List).map((d) => DayForecast.fromJson(d)).toList(),
    alerts:
        (j['alerts'] as List? ?? [])
            .map((a) => WeatherAlert.fromJson(a))
            .toList(),
    sunrise: DateTime.tryParse(j['sunrise'] ?? ''),
    sunset: DateTime.tryParse(j['sunset'] ?? ''),
    notice: j['notice'],
    station: j['station'],
  );
}

double? number(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
String age(DateTime date, DateTime now) {
  final d = now.difference(date);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

String wmoSummary(int code) => switch (code) {
  0 => 'Clear sky',
  1 => 'Mainly clear',
  2 => 'Partly cloudy',
  3 => 'Overcast',
  45 || 48 => 'Fog',
  51 || 53 || 55 => 'Drizzle',
  56 || 57 => 'Freezing drizzle',
  61 || 63 || 65 => 'Rain',
  66 || 67 => 'Freezing rain',
  71 || 73 || 75 || 77 => 'Snow',
  80 || 81 || 82 => 'Rain showers',
  85 || 86 => 'Snow showers',
  95 || 96 || 99 => 'Thunderstorm',
  _ => 'Weather unavailable',
};

String conditionKind(String summary) {
  final s = summary.toLowerCase();
  if (s.contains('thunder')) return 'storm';
  if (s.contains('snow') || s.contains('flurr') || s.contains('ice pellet')) {
    return 'snow';
  }
  if (s.contains('rain') || s.contains('shower') || s.contains('drizzle')) {
    return 'rain';
  }
  if (s.contains('fog') || s.contains('mist') || s.contains('haze')) {
    return 'fog';
  }
  if (s.contains('partly') || s.contains('mainly') || s.contains('mix of')) {
    return 'partly';
  }
  if (s.contains('cloud') || s.contains('overcast')) return 'cloud';
  if (s.contains('clear') || s.contains('sunny')) return 'sun';
  return 'unknown';
}
