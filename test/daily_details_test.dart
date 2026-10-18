import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_weather/models.dart';
import 'package:local_weather/weather_api.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'support.dart';

void main() {
  tzdata.initializeTimeZones();
  final now = DateTime.utc(2026, 10, 18, 16, 30);
  test(
    'Canada daily details merge peak wind and precipitation across day and night',
    () {
      final j = fixture('canada');
      final days = j['properties']['forecastGroup']['forecasts'];
      days[0]['abbreviated_forecast'] = {'pop': 30};
      days[1]['abbreviated_forecast'] = {'pop': 60};
      days[1]['winds'] = {
        'periods': [
          {
            'speed': {
              'value': {'en': 40},
            },
          },
        ],
      };
      final f = parseCanada(j, now);
      expect(f.days.first.rain, 60);
      expect(f.days.first.windMax, 40);
      final cached = Forecast.fromJson(jsonDecode(jsonEncode(f.toJson())));
      expect(cached.days.first.windMax, 40);
    },
  );
  test('NWS daily peak wind uses upper end of range and converts mph', () {
    final h = fixture('nws_hourly');
    final d = fixture('nws_daily');
    for (final p in d['properties']['periods']) {
      p['windSpeed'] = '10 to 20 mph';
    }
    final f = parseNws(
      h,
      d,
      {'features': []},
      const Place(
        name: 'New York',
        latitude: 40.71,
        longitude: -74,
        country: 'US',
        timezone: 'America/New_York',
      ),
      now,
    );
    expect(f.days.first.windMax, closeTo(32.18688, .0001));
  });
  test(
    'Open-Meteo daily wind remains available after caching and older caches still decode',
    () {
      final j = fixture('open_meteo');
      j['daily']['wind_speed_10m_max'] = List.filled(7, 28.5);
      final f = parseOpenMeteo(j, Place.toronto, now);
      expect(f.days.first.windMax, 28.5);
      expect(
        Forecast.fromJson(
          jsonDecode(jsonEncode(f.toJson())),
        ).days.first.windMax,
        28.5,
      );
      expect(
        DayForecast.fromJson({'label': 'Monday', 'summary': 'Sunny'}).windMax,
        isNull,
      );
    },
  );
}
