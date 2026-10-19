import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../models.dart';
import 'forecast_chart_data.dart';
import 'weather_style.dart';

enum WeatherChartKind { temperature, precipitation }

/// The graph always uses real timestamp spacing. Missing values remain gaps.
class WeatherChart extends StatelessWidget {
  const WeatherChart({
    super.key,
    required this.hours,
    required this.settings,
    required this.kind,
    this.dark = false,
    this.low,
    this.high,
    this.range,
  });
  final List<HourForecast> hours;
  final Settings settings;
  final WeatherChartKind kind;
  final bool dark;
  final double? low, high;
  final ForecastChartRange? range;
  @override
  Widget build(BuildContext context) {
    final precipitation = kind == WeatherChartKind.precipitation;
    final values =
        hours
            .map((h) => precipitation ? h.rain : h.temperature)
            .whereType<double>()
            .where((v) => v.isFinite)
            .toList();
    final fg = dark ? const Color(0xffbfd4c8) : muted;
    if (values.isEmpty || (!precipitation && hours.length < 2)) {
      return Center(
        child: Text(
          precipitation
              ? 'Hourly precipitation not available'
              : 'Hourly temperature not available',
          textAlign: TextAlign.center,
          style: TextStyle(color: fg, fontSize: 10),
        ),
      );
    }
    final min = values.reduce(math.min), max = values.reduce(math.max);
    final label =
        precipitation
            ? 'Hourly precipitation chance, from ${min.round()} to ${max.round()} percent. Missing hours are gaps.'
            : 'Hourly temperature, from ${settings.temperature(min)} to ${settings.temperature(max)} ${settings.fahrenheit ? 'Fahrenheit' : 'Celsius'}. Missing hours are gaps.';
    return Semantics(
      label: label,
      image: true,
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _WeatherChartPainter(
            hours,
            settings,
            kind,
            dark,
            low,
            high,
            MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5).toDouble(),
            range,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _WeatherChartPainter extends CustomPainter {
  _WeatherChartPainter(
    this.hours,
    this.settings,
    this.kind,
    this.dark,
    this.low,
    this.high,
    this.scale,
    this.range,
  );
  final List<HourForecast> hours;
  final Settings settings;
  final WeatherChartKind kind;
  final bool dark;
  final double? low, high;
  final double scale;
  final ForecastChartRange? range;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 30 || size.height < 24 || hours.isEmpty) return;
    final precip = kind == WeatherChartKind.precipitation;
    final fg = dark ? const Color(0xffbfd4c8) : muted;
    final accent =
        precip
            ? (dark ? const Color(0xff9ed1e2) : const Color(0xff387d97))
            : (dark ? const Color(0xfff2c18b) : const Color(0xffb47b3e));
    final left = precip ? 29.0 * scale : 3.0;
    final bottom = size.height - 16 * scale;
    if (bottom <= 5 || left >= size.width - 5) return;
    final plot = Rect.fromLTRB(left, 4, size.width - 4, bottom);
    double? value(HourForecast h) => precip ? h.rain : h.temperature;
    final valid =
        hours.map(value).whereType<double>().where((v) => v.isFinite).toList();
    if (valid.isEmpty) return;
    final min =
        precip
            ? 0.0
            : math.min(low ?? valid.reduce(math.min), valid.reduce(math.min));
    final max =
        precip
            ? 100.0
            : math.max(high ?? valid.reduce(math.max), valid.reduce(math.max));
    final span = precip ? 100.0 : math.max(4.0, max - min);
    final mid = (min + max) / 2;
    final startTime = range?.start ?? hours.first.time;
    final endTime = range?.end ?? hours.last.time;
    final start = startTime.millisecondsSinceEpoch;
    final duration = math.max(3600000, endTime.millisecondsSinceEpoch - start);
    double timeX(DateTime time) =>
        plot.left +
        (time.millisecondsSinceEpoch - start) / duration * plot.width;
    double x(HourForecast h) => timeX(h.time);
    double y(double v) =>
        plot.bottom -
        (precip ? v / 100 : (v - mid + span / 2) / span) * plot.height;
    final paint = Paint()..isAntiAlias = true;
    void text(String value, Offset at, {TextAlign align = TextAlign.left}) {
      final tp = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: fg,
            fontFamily: 'Roboto',
            fontSize: 9 * scale,
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx =
          align == TextAlign.right
              ? at.dx - tp.width
              : align == TextAlign.center
              ? at.dx - tp.width / 2
              : at.dx;
      tp.paint(
        canvas,
        Offset(
          dx.clamp(0, math.max(0, size.width - tp.width)).toDouble(),
          at.dy,
        ),
      );
    }

    for (final tick in precip ? [0.0, 50.0, 100.0] : [min]) {
      paint
        ..color = fg.withValues(alpha: .2)
        ..strokeWidth = .7;
      final yy = precip ? y(tick) : plot.bottom;
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), paint);
      if (precip) {
        text(
          '${tick.round()}%',
          Offset(0, (yy - 4 * scale).clamp(0, bottom - 9 * scale).toDouble()),
        );
      }
    }
    if (precip) {
      final barWidth = (plot.width / math.max(2, duration / 3600000 + 1) * .6)
          .clamp(2.0, 18.0);
      for (final h in hours) {
        final v = h.rain;
        if (v == null || !v.isFinite) continue;
        paint
          ..style = PaintingStyle.fill
          ..color = accent.withValues(alpha: .78);
        final top = y(v.clamp(0, 100).toDouble());
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              (x(h) - barWidth / 2).clamp(plot.left, plot.right),
              math.min(top, plot.bottom - 1.5),
              (x(h) + barWidth / 2).clamp(plot.left, plot.right),
              plot.bottom,
            ),
            const Radius.circular(2),
          ),
          paint,
        );
      }
    } else {
      final segments = <List<HourForecast>>[];
      for (final hour in hours) {
        if (!hour.temperature.isFinite) continue;
        if (segments.isEmpty ||
            hour.time.difference(segments.last.last.time) >
                const Duration(minutes: 90)) {
          segments.add([]);
        }
        segments.last.add(hour);
      }
      canvas.save();
      canvas.clipRect(plot.inflate(2));
      for (final segment in segments) {
        final path =
            Path()..moveTo(x(segment.first), y(segment.first.temperature));
        for (final h in segment.skip(1)) {
          path.lineTo(x(h), y(h.temperature));
        }
        if (segment.length > 1) {
          final fill =
              Path.from(path)
                ..lineTo(x(segment.last), plot.bottom)
                ..lineTo(x(segment.first), plot.bottom)
                ..close();
          paint
            ..style = PaintingStyle.fill
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withValues(alpha: .17),
                accent.withValues(alpha: .01),
              ],
            ).createShader(plot);
          canvas.drawPath(fill, paint);
          paint
            ..shader = null
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = accent;
          canvas.drawPath(path, paint);
        }
        paint
          ..style = PaintingStyle.fill
          ..color = accent;
        canvas.drawCircle(
          Offset(x(segment.first), y(segment.first.temperature)),
          2,
          paint,
        );
        canvas.drawCircle(
          Offset(x(segment.last), y(segment.last.temperature)),
          2,
          paint,
        );
      }
      canvas.restore();
    }
    String time(DateTime at) {
      final local = settings.place.local(at);
      return DateFormat(
        local.minute == 0 ? 'ha' : 'h:mma',
      ).format(local).toLowerCase();
    }

    text(time(startTime), Offset(plot.left, plot.bottom + 4));
    if (size.width > 220) {
      final middle = startTime.add(Duration(milliseconds: duration ~/ 2));
      text(
        time(middle),
        Offset(timeX(middle), plot.bottom + 4),
        align: TextAlign.center,
      );
    }
    if (endTime.isAfter(startTime)) {
      text(
        time(endTime),
        Offset(plot.right, plot.bottom + 4),
        align: TextAlign.right,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherChartPainter old) =>
      old.hours != hours ||
      old.kind != kind ||
      old.settings.fahrenheit != settings.fahrenheit ||
      old.settings.place != settings.place ||
      old.dark != dark ||
      old.low != low ||
      old.high != high ||
      old.range?.start != range?.start ||
      old.range?.end != range?.end ||
      old.scale != scale;
}

class TemperatureRangeChart extends StatelessWidget {
  const TemperatureRangeChart({
    super.key,
    required this.hours,
    required this.settings,
    required this.high,
    required this.low,
    this.dark = false,
    this.range,
  });
  final List<HourForecast> hours;
  final Settings settings;
  final double? high, low;
  final bool dark;
  final ForecastChartRange? range;
  @override
  Widget build(BuildContext context) {
    final fg = dark ? const Color(0xffe7f0df) : ink;
    Widget reading(String label, double? value) => SizedBox(
      width: 49,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: fg.withValues(alpha: .65),
              fontSize: 9,
              height: 1.1,
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              settings.temperature(value),
              style: TextStyle(
                color: fg,
                fontSize: 23,
                height: 1.1,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
    return Row(
      children: [
        reading('High', high),
        const SizedBox(width: 5),
        Expanded(
          child: WeatherChart(
            hours: hours,
            settings: settings,
            kind: WeatherChartKind.temperature,
            dark: dark,
            high: high,
            low: low,
            range: range,
          ),
        ),
        const SizedBox(width: 5),
        reading('Low', low),
      ],
    );
  }
}
