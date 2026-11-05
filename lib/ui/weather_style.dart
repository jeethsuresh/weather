import 'package:flutter/material.dart';
import '../models.dart';

const ink = Color(0xff183c5b);
const muted = Color(0xff526e84);
const mint = Color(0xffe0edf7);
const orange = Color(0xffef9c53);

IconData weatherIcon(String summary) => switch (conditionKind(summary)) {
  'storm' => Icons.thunderstorm_outlined,
  'snow' => Icons.ac_unit,
  'rain' => Icons.water_drop_outlined,
  'fog' => Icons.foggy,
  'cloud' => Icons.cloud_outlined,
  'partly' => Icons.wb_cloudy_outlined,
  'sun' => Icons.wb_sunny_outlined,
  _ => Icons.thermostat_outlined,
};
