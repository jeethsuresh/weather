import 'package:flutter/foundation.dart';
import '../models.dart';

String forecastSelectionIdentity(Settings settings, Forecast forecast) =>
    '${settings.place.id}:${forecast.source.name}';

/// View state only. A provider/place change cannot inherit another sky's hour.
class ForecastSelectionController extends ChangeNotifier {
  DateTime? time;
  String? identity;
  int signal = 0;
  HourForecast? selected(String key, List<HourForecast> hours) =>
      key == identity ? hours.where((h) => h.time == time).firstOrNull : null;
  void choose(String key, HourForecast hour) {
    if (identity == key && time == hour.time) return;
    identity = key;
    time = hour.time;
    signal++;
    notifyListeners();
  }

  void showNow() {
    if (time == null) return;
    time = null;
    signal++;
    notifyListeners();
  }
}
