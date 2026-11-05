import 'dart:math' as math;
import 'models.dart';

/// Local, offline solar estimates using NOAA's general solar equations:
/// https://gml.noaa.gov/grad/solcalc/solareqns.PDF
/// Provider rise/set times take precedence for the matching local calendar day.
class SolarDay {
  const SolarDay(this.sunrise, this.sunset, {this.polarDay = false});
  final DateTime? sunrise, sunset;
  final bool polarDay;

  factory SolarDay.at(Place place, DateTime now, [Forecast? forecast]) {
    final local = place.local(now);
    final date = DateTime.utc(local.year, local.month, local.day);
    final day = date.difference(DateTime.utc(local.year)).inDays + 1;
    final yearLength =
        DateTime.utc(
          local.year + 1,
        ).difference(DateTime.utc(local.year)).inDays;
    final g = 2 * math.pi / yearLength * (day - 1);
    final eq =
        229.18 *
        (.000075 +
            .001868 * math.cos(g) -
            .032077 * math.sin(g) -
            .014615 * math.cos(2 * g) -
            .040849 * math.sin(2 * g));
    final decl =
        .006918 -
        .399912 * math.cos(g) +
        .070257 * math.sin(g) -
        .006758 * math.cos(2 * g) +
        .000907 * math.sin(2 * g) -
        .002697 * math.cos(3 * g) +
        .00148 * math.sin(3 * g);
    final lat = place.latitude * math.pi / 180;
    final cosHour =
        math.cos(90.833 * math.pi / 180) / (math.cos(lat) * math.cos(decl)) -
        math.tan(lat) * math.tan(decl);
    if (cosHour.abs() > 1) return SolarDay(null, null, polarDay: cosHour < -1);
    final hour = math.acos(cosHour) * 180 / math.pi;
    DateTime event(double angle) => date.add(
      Duration(
        seconds: ((720 - 4 * (place.longitude + angle) - eq) * 60).round(),
      ),
    );
    DateTime matchingDate(DateTime value) {
      final result = place.local(value);
      final resultDate = DateTime.utc(result.year, result.month, result.day);
      return value.add(date.difference(resultDate));
    }

    DateTime choose(DateTime? supplied, DateTime estimate) {
      if (supplied != null) {
        final value = place.local(supplied);
        if (value.year == local.year &&
            value.month == local.month &&
            value.day == local.day) {
          return supplied;
        }
      }
      return matchingDate(estimate);
    }

    return SolarDay(
      choose(forecast?.sunrise, event(hour)),
      choose(forecast?.sunset, event(-hour)),
    );
  }

  bool nightAt(DateTime now) =>
      sunrise == null || sunset == null
          ? !polarDay
          : now.isBefore(sunrise!) || !now.isBefore(sunset!);
}

/// Approximate phase from the mean synodic month and the 2000-01-06 new moon.
/// Used as a visual phase, not moonrise, visibility, or an ephemeris prediction.
double moonPhase(DateTime now) =>
    (now.toUtc().difference(DateTime.utc(2000, 1, 6, 18, 14)).inSeconds /
        86400 /
        29.530588853) %
    1;

String moonPhaseName(double phase) =>
    const [
      'New moon',
      'Waxing crescent',
      'First quarter',
      'Waxing gibbous',
      'Full moon',
      'Waning gibbous',
      'Last quarter',
      'Waning crescent',
    ][((phase * 8 + .5).floor()) % 8];

Set<String> warningEdges(Iterable<WeatherAlert> alerts, DateTime now) => {
  for (final alert in alerts)
    if (alert.expires == null || alert.expires!.isAfter(now))
      ...hazardEdges('${alert.title} ${alert.type}'),
};

Set<String> hazardEdges(String subject) {
  final text = subject.toLowerCase();
  return {
    if (RegExp(r'\b(frost|freeze|freezing|cold|wind chill)\b').hasMatch(text))
      'frost',
    if (RegExp(
      r'\b(wind|windstorm|gale|hurricane|tropical storm)\b',
    ).hasMatch(text))
      'wind',
    if (text.contains('thunder') || text.contains('lightning')) 'thunder',
  };
}
