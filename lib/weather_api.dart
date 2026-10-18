import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'models.dart';
import 'storage.dart';

abstract interface class JsonTransport {
  Future<Json> get(Uri uri);
  void close();
}

class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HttpTransport implements JsonTransport {
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  @override
  Future<Json> get(Uri uri) async {
    if (uri.scheme != 'https') {
      throw const WeatherException('An insecure weather link was rejected.');
    }
    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 15));
    request.headers.set(
      'User-Agent',
      'DaybreakWeather/1.0 (personal Android weather client)',
    );
    request.headers.set('Accept', 'application/geo+json, application/json');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw WeatherException(
        'The weather service returned ${response.statusCode}.',
      );
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 15));
    return jsonDecode(body) as Json;
  }

  @override
  void close() => _client.close(force: true);
}

/// Injectable transport keeps provider decoding verifiable without live services.
class WeatherApi {
  WeatherApi(this.http, this.store, {DateTime Function()? clock})
    : now = clock ?? DateTime.now;
  final JsonTransport http;
  final LocalStore store;
  final DateTime Function() now;

  Future<List<Place>> search(String query) async {
    if (query.trim().length < 2) return [];
    final j = await http.get(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': query.trim(),
        'count': '12',
        'language': 'en',
        'format': 'json',
      }),
    );
    return (j['results'] as List? ?? [])
        .map(
          (p) => Place(
            name: p['name'],
            latitude: (p['latitude'] as num).toDouble(),
            longitude: (p['longitude'] as num).toDouble(),
            country: p['country_code'] ?? '',
            timezone: p['timezone'] ?? 'UTC',
            region: p['admin1'] ?? '',
          ),
        )
        .toList();
  }

  Future<String> timezoneAt(double latitude, double longitude) async {
    final data = await http.get(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '$latitude',
        'longitude': '$longitude',
        'timezone': 'auto',
        'current': 'temperature_2m',
        'forecast_days': '1',
      }),
    );
    final timezone = data['timezone'];
    if (timezone is! String || timezone.isEmpty) {
      throw const WeatherException('Timezone unavailable.');
    }
    return timezone;
  }

  Future<Forecast> fetch(Settings settings) async {
    final p = settings.place;
    if (settings.source == WeatherSource.openMeteo) return openMeteo(p);
    if (settings.source == WeatherSource.canada) return canada(p);
    if (settings.source == WeatherSource.nws) return nws(p);
    try {
      if (p.country == 'CA') return await canada(p);
      if (p.country == 'US') return await nws(p);
    } catch (_) {
      return openMeteo(
        p,
        notice: 'The national service is unavailable. Using Open-Meteo.',
      );
    }
    return openMeteo(p);
  }

  Future<Forecast> openMeteo(Place p, {String? notice}) async {
    final j = await http.get(
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '${p.latitude}',
        'longitude': '${p.longitude}',
        'timezone': p.timezone,
        'timeformat': 'unixtime',
        'forecast_days': '7',
        'current':
            'temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m',
        'hourly':
            'temperature_2m,relative_humidity_2m,precipitation_probability,weather_code,wind_speed_10m',
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,sunrise,sunset',
      }),
    );
    return parseOpenMeteo(j, p, now(), notice: notice);
  }

  Future<Forecast> canada(Place p) async {
    if (p.country != 'CA') {
      throw const WeatherException(
        'Environment Canada covers Canadian locations.',
      );
    }
    var site = p.canadaSite ?? await store.read('canada.site.${p.id}');
    Json? feature;
    if (site != null) {
      try {
        feature = await http.get(
          Uri.https(
            'api.weather.gc.ca',
            '/collections/citypageweather-realtime/items/$site',
            {'f': 'json'},
          ),
        );
      } catch (_) {
        site = null;
      }
    }
    if (site == null) {
      final lonRadius = math.min(
        3.0,
        .65 / math.cos(p.latitude * math.pi / 180).abs(),
      );
      final j = await http.get(
        Uri.https(
          'api.weather.gc.ca',
          '/collections/citypageweather-realtime/items',
          {
            'f': 'json',
            'limit': '100',
            'bbox':
                '${math.max(-180, p.longitude - lonRadius)},${math.max(-90, p.latitude - .65)},'
                '${math.min(180, p.longitude + lonRadius)},${math.min(90, p.latitude + .65)}',
          },
        ),
      );
      final candidates =
          (j['features'] as List? ?? [])
              .cast<Json>()
              .where((f) => f['geometry']?['coordinates'] is List)
              .toList();
      candidates.sort(
        (a, b) => stationDistance(p, a).compareTo(stationDistance(p, b)),
      );
      if (candidates.isEmpty || stationDistance(p, candidates.first) > 90) {
        throw const WeatherException(
          'No nearby Environment Canada forecast was found. Try Open-Meteo.',
        );
      }
      feature = candidates.first;
      site = feature['properties']['identifier'] ?? feature['id'];
      if (site != null) await store.write('canada.site.${p.id}', site);
    }
    return parseCanada(feature!, now());
  }

  Future<Forecast> nws(Place p) async {
    if (p.country != 'US') {
      throw const WeatherException(
        'The National Weather Service covers US locations.',
      );
    }
    final points = await http.get(
      Uri.https(
        'api.weather.gov',
        '/points/${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
      ),
    );
    final links = points['properties'] as Json;
    Uri forecastLink(String key) {
      final u = Uri.parse(links[key] as String);
      if (u.scheme != 'https' || u.host != 'api.weather.gov') {
        throw const WeatherException(
          'The weather service returned an invalid forecast link.',
        );
      }
      return u.replace(queryParameters: {...u.queryParameters, 'units': 'si'});
    }

    final results = await Future.wait([
      http.get(forecastLink('forecastHourly')),
      http.get(forecastLink('forecast')),
      _alerts(p),
    ]);
    return parseNws(results[0], results[1], results[2], p, now());
  }

  Future<Json> _alerts(Place p) async {
    try {
      return await http.get(
        Uri.https('api.weather.gov', '/alerts/active', {
          'point':
              '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
        }),
      );
    } catch (_) {
      return {'unavailable': true, 'features': []};
    }
  }
}

double stationDistance(Place p, Json feature) {
  final c = feature['geometry']['coordinates'] as List;
  final lat1 = p.latitude * math.pi / 180;
  final lat2 = (c[1] as num).toDouble() * math.pi / 180;
  final dLat = lat2 - lat1;
  final dLon = ((c[0] as num).toDouble() - p.longitude) * math.pi / 180;
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
  return 6371 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
}

DateTime _unix(dynamic n) =>
    DateTime.fromMillisecondsSinceEpoch((n as num).toInt() * 1000, isUtc: true);
dynamic _en(dynamic value) => value is Map ? value['en'] : value;
double? _value(dynamic field) =>
    field is Map ? number(_en(field['value'])) : null;
String _text(dynamic field, [String fallback = '']) =>
    '${_en(field) ?? fallback}';
DateTime? _date(dynamic field) => DateTime.tryParse(_text(field));
List<Json> _objects(dynamic list) => (list as List? ?? []).cast<Json>();

Forecast parseOpenMeteo(Json j, Place p, DateTime now, {String? notice}) {
  final current = j['current'] as Json;
  final h = j['hourly'] as Json;
  final d = j['daily'] as Json;
  final hours = <HourForecast>[];
  for (var i = 0; i < (h['time'] as List).length; i++) {
    final temperature = number(h['temperature_2m'][i]);
    if (temperature == null) continue;
    hours.add(
      HourForecast(
        time: _unix(h['time'][i]),
        temperature: temperature,
        summary: wmoSummary((h['weather_code'][i] as num?)?.toInt() ?? -1),
        rain: number(h['precipitation_probability'][i]),
        wind: number(h['wind_speed_10m'][i]),
        humidity: number(h['relative_humidity_2m'][i]),
      ),
    );
  }
  final days = <DayForecast>[];
  for (var i = 0; i < (d['time'] as List).length; i++) {
    days.add(
      DayForecast(
        label: DateFormat('EEEE').format(p.local(_unix(d['time'][i]))),
        high: number(d['temperature_2m_max'][i]),
        low: number(d['temperature_2m_min'][i]),
        rain: number(d['precipitation_probability_max'][i]),
        windMax: number((d['wind_speed_10m_max'] as List?)?[i]),
        summary: wmoSummary((d['weather_code'][i] as num?)?.toInt() ?? -1),
      ),
    );
  }
  final temperature = number(current['temperature_2m']);
  if (temperature == null || hours.isEmpty) {
    throw const WeatherException('This forecast is incomplete.');
  }
  return Forecast(
    source: WeatherSource.openMeteo,
    fetchedAt: now,
    observedAt: _unix(current['time']),
    temperature: temperature,
    feelsLike: number(current['apparent_temperature']),
    humidity: number(current['relative_humidity_2m']),
    wind: number(current['wind_speed_10m']),
    summary: wmoSummary((current['weather_code'] as num?)?.toInt() ?? -1),
    hours: hours,
    days: days,
    sunrise:
        (d['sunrise'] as List?)?.firstOrNull == null
            ? null
            : _unix(d['sunrise'][0]),
    sunset:
        (d['sunset'] as List?)?.firstOrNull == null
            ? null
            : _unix(d['sunset'][0]),
    notice: notice,
  );
}

Forecast parseCanada(Json feature, DateTime now) {
  final p = feature['properties'] as Json;
  final current = (p['currentConditions'] as Json?) ?? <String, dynamic>{};
  final hours = <HourForecast>[];
  for (final h in _objects(p['hourlyForecastGroup']?['hourlyForecasts'])) {
    final temperature = _value(h['temperature']);
    final time = _date(h['timestamp']);
    if (temperature == null || time == null) continue;
    hours.add(
      HourForecast(
        time: time,
        temperature: temperature,
        summary: _text(h['condition'], 'Weather unavailable'),
        rain: _value(h['lop']),
        wind: _value(h['wind']?['speed']),
      ),
    );
  }
  hours.sort((a, b) => a.time.compareTo(b.time));
  final nearHour =
      hours
          .where((h) => h.time.isAfter(now.subtract(const Duration(hours: 1))))
          .where((h) => h.time.isBefore(now.add(const Duration(hours: 2))))
          .firstOrNull;
  final temperature = _value(current['temperature']) ?? nearHour?.temperature;
  final observedAt =
      _value(current['temperature']) == null
          ? nearHour?.time
          : _date(current['timestamp']);
  if (temperature == null || hours.isEmpty || observedAt == null) {
    throw const WeatherException('The Canadian forecast is incomplete.');
  }
  final days = <DayForecast>[];
  for (final f in _objects(p['forecastGroup']?['forecasts'])) {
    final temps = _objects(f['temperatures']?['temperature']);
    double? high, low;
    for (final t in temps) {
      if (_text(t['class']) == 'high') high = _value(t);
      if (_text(t['class']) == 'low') low = _value(t);
    }
    final windMax = _maximum(
      _objects(f['winds']?['periods']).map((w) => _value(w['speed'])),
    );
    final rain = _canadaProbability(f);
    final label = _text(
      f['period']?['textForecastName'],
      _text(f['period']?['value']),
    );
    if (label.toLowerCase().contains('night') &&
        days.isNotEmpty &&
        low != null) {
      final last = days.removeLast();
      days.add(
        DayForecast(
          label: last.label,
          summary: last.summary,
          high: last.high,
          low: low,
          rain: _maximum([last.rain, rain]),
          windMax: _maximum([last.windMax, windMax]),
        ),
      );
    } else {
      days.add(
        DayForecast(
          label: label,
          high: high,
          low: low,
          summary: _text(
            f['abbreviatedForecast']?['textSummary'],
            _text(f['cloudPrecip']),
          ),
          rain: rain,
          windMax: windMax,
        ),
      );
    }
  }
  double? feelsLike;
  // ECCC can carry a windChill field outside its valid temperature range.
  if (temperature <= 10) feelsLike = _value(current['windChill']);
  if (temperature >= 20) feelsLike = _value(current['humidex']);
  final alerts = <WeatherAlert>[];
  for (final w in _objects(p['warnings'])) {
    final title = _text(w['description'], _text(w['event'], _text(w['title'])));
    final expires = _date(w['expiryTime'] ?? w['expires']);
    if (title.isNotEmpty && (expires == null || expires.isAfter(now))) {
      alerts.add(
        WeatherAlert(
          title,
          _text(w['text'], _text(w['url'])),
          expires: expires,
        ),
      );
    }
  }
  return Forecast(
    source: WeatherSource.canada,
    fetchedAt: now,
    observedAt: observedAt,
    temperature: temperature,
    feelsLike: feelsLike,
    summary: _text(
      current['condition'],
      nearHour?.summary ?? 'Weather unavailable',
    ),
    humidity: _value(current['relativeHumidity']),
    wind: _value(current['wind']?['speed']),
    hours: hours,
    days: days.take(7).toList(),
    alerts: alerts,
    sunrise: _date(p['riseSet']?['sunrise']),
    sunset: _date(p['riseSet']?['sunset']),
    station: _text(p['name']),
    notice:
        _value(current['temperature']) == null
            ? 'Current conditions are an hourly forecast.'
            : null,
  );
}

Forecast parseNws(
  Json hourly,
  Json daily,
  Json alertData,
  Place place,
  DateTime now,
) {
  final hours = <HourForecast>[];
  for (final h in _objects(hourly['properties']?['periods'])) {
    var temperature = number(h['temperature']);
    if (h['temperature'] is Map) {
      temperature = number(h['temperature']['value']);
    }
    if (temperature == null) continue;
    if (h['temperatureUnit'] == 'F' ||
        (h['temperature'] is Map &&
            '${h['temperature']['unitCode']}'.contains('degF'))) {
      temperature = (temperature - 32) * 5 / 9;
    }
    final wind = _windKmh(h['windSpeed']);
    hours.add(
      HourForecast(
        time: DateTime.parse(h['startTime']),
        temperature: temperature,
        summary: h['shortForecast'] ?? 'Weather unavailable',
        wind: wind,
        rain: number(h['probabilityOfPrecipitation']?['value']),
        humidity: number(h['relativeHumidity']?['value']),
      ),
    );
  }
  if (hours.isEmpty) {
    throw const WeatherException('The US forecast is incomplete.');
  }
  final days = <DayForecast>[];
  for (final d in _objects(daily['properties']?['periods'])) {
    var t = number(d['temperature']);
    if (t != null && d['temperatureUnit'] == 'F') t = (t - 32) * 5 / 9;
    final windMax = _windKmh(d['windSpeed']);
    final rain = number(d['probabilityOfPrecipitation']?['value']);
    final isDay = d['isDaytime'] == true;
    final date = place.local(DateTime.parse(d['startTime']));
    final label = DateFormat('EEEE').format(date);
    if (!isDay && days.isNotEmpty && days.last.label == label) {
      final last = days.removeLast();
      days.add(
        DayForecast(
          label: last.label,
          summary: last.summary,
          high: last.high,
          low: t,
          rain: _maximum([last.rain, rain]),
          windMax: _maximum([last.windMax, windMax]),
        ),
      );
    } else {
      days.add(
        DayForecast(
          label: isDay ? label : '${d['name']}',
          summary: d['shortForecast'] ?? '',
          high: isDay ? t : null,
          low: isDay ? null : t,
          rain: rain,
          windMax: windMax,
        ),
      );
    }
  }
  final alerts = <WeatherAlert>[];
  for (final f in _objects(alertData['features'])) {
    final a = f['properties'] as Json;
    final expires = _date(a['expires']);
    if (a['status'] != null && a['status'] != 'Actual') continue;
    if (a['messageType'] == 'Cancel' ||
        (expires != null && !expires.isAfter(now))) {
      continue;
    }
    alerts.add(
      WeatherAlert(
        a['headline'] ?? a['event'] ?? 'Weather alert',
        [a['description'], a['instruction']].whereType<String>().join('\n\n'),
        expires: expires,
      ),
    );
  }
  return Forecast(
    source: WeatherSource.nws,
    fetchedAt: now,
    observedAt: hours.first.time,
    temperature: hours.first.temperature,
    summary: hours.first.summary,
    humidity: hours.first.humidity,
    wind: hours.first.wind,
    hours: hours,
    days: days.take(7).toList(),
    alerts: alerts,
    notice:
        alertData['unavailable'] == true
            ? 'Weather alerts could not be checked.'
            : null,
  );
}

// A provider can omit precipitation probabilities and wind entirely.
double? _maximum(Iterable<double?> values) {
  final valid = values.whereType<double>().toList();
  return valid.isEmpty ? null : valid.reduce(math.max);
}

double? _canadaProbability(Json forecast) {
  final pop =
      forecast['abbreviatedForecast']?['pop'] ??
      forecast['abbreviated_forecast']?['pop'];
  return _value(forecast['precipitation']?['lop']) ??
      _value(pop) ??
      number(_en(pop));
}

double? _windKmh(dynamic field) {
  if (field is Map) {
    final value = number(field['value']);
    if (value == null) return null;
    final unit = '${field['unitCode']}';
    if (unit.contains('m_s-1')) return value * 3.6;
    if (unit.contains('mi_h-1') || unit.contains('mph')) {
      return value * 1.609344;
    }
    return value;
  }
  final text = '$field';
  final speed = _maximum(
    RegExp(r'[\d.]+').allMatches(text).map((m) => number(m.group(0))),
  );
  return speed == null
      ? null
      : text.contains('mph')
      ? speed * 1.609344
      : speed;
}
