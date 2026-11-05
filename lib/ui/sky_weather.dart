import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../sky.dart';

class SkyPalette {
  const SkyPalette(this.background, this.card, this.deep);
  final Color background, card, deep;
  factory SkyPalette.at(Settings settings, Forecast? forecast, DateTime now) {
    final kind = conditionKind(forecast?.summary ?? '');
    if (kind == 'rain' || kind == 'storm') {
      return const SkyPalette(
        Color(0xffe7e9ec),
        Color(0xffd1d7dd),
        Color(0xff3a4652),
      );
    }
    if (kind == 'cloud' || kind == 'fog' || kind == 'snow') {
      return const SkyPalette(
        Color(0xffe6edf3),
        Color(0xffcedde9),
        Color(0xff2c465e),
      );
    }
    if (SolarDay.at(settings.place, now, forecast).nightAt(now)) {
      return const SkyPalette(
        Color(0xffe2e9f3),
        Color(0xffc6d6ed),
        Color(0xff111f38),
      );
    }
    return const SkyPalette(
      Color(0xffe9f5ff),
      Color(0xffb5dffa),
      Color(0xff205a85),
    );
  }
}

class SkyDetails extends StatelessWidget {
  const SkyDetails({
    super.key,
    required this.settings,
    required this.forecast,
    required this.now,
    this.dark = false,
  });
  final Settings settings;
  final Forecast forecast;
  final DateTime now;
  final bool dark;
  @override
  Widget build(BuildContext context) {
    final solar = SolarDay.at(settings.place, now, forecast);
    final phase = moonPhase(now);
    final clearNight =
        solar.nightAt(now) && conditionKind(forecast.summary) == 'sun';
    final color = dark ? const Color(0xffd5e9fa) : const Color(0xff244e70);
    String time(DateTime? value) =>
        value == null
            ? '—'
            : DateFormat('h:mm a').format(settings.place.local(value));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Sunrise ${time(solar.sunrise)}',
            style: TextStyle(color: color, fontSize: 12),
          ),
          Text(
            'Sunset ${time(solar.sunset)}',
            style: TextStyle(color: color, fontSize: 12),
          ),
          if (solar.sunrise == null)
            Text(
              solar.polarDay ? 'Midnight sun' : 'Polar night',
              style: TextStyle(color: color, fontSize: 12),
            ),
          if (clearNight)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MoonDisc(
                  phase: phase,
                  southern: settings.place.latitude < 0,
                  size: 22,
                ),
                const SizedBox(width: 7),
                Text(
                  '${moonPhaseName(phase)} · approx.',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class MoonDisc extends StatelessWidget {
  const MoonDisc({
    super.key,
    required this.phase,
    this.southern = false,
    this.size = 64,
  });
  final double phase, size;
  final bool southern;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${moonPhaseName(phase)}, approximate moon phase',
    child: CustomPaint(
      size: Size.square(size),
      painter: _MoonPainter(phase, southern),
    ),
  );
}

class _MoonPainter extends CustomPainter {
  const _MoonPainter(this.phase, this.southern);
  final double phase;
  final bool southern;
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - 1;
    canvas.translate(size.width / 2, size.height / 2);
    if (southern) canvas.rotate(math.pi);
    canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0xff244663));
    final path = Path();
    final terminator = math.cos(2 * math.pi * phase);
    final side = phase < .5 ? 1.0 : -1.0;
    for (var i = 0; i <= 80; i++) {
      final y = -r + 2 * r * i / 80;
      final x = side * math.sqrt(math.max(0, r * r - y * y));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    for (var i = 80; i >= 0; i--) {
      final y = -r + 2 * r * i / 80;
      path.lineTo(side * terminator * math.sqrt(math.max(0, r * r - y * y)), y);
    }
    canvas.drawPath(path..close(), Paint()..color = const Color(0xfff1f5ff));
    canvas.drawCircle(
      Offset.zero,
      r,
      Paint()
        ..color = const Color(0xff8caac6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_MoonPainter old) =>
      phase != old.phase || southern != old.southern;
}

/// Decorative, stationary edges leave controls and text unobscured and tappable.
class WarningEdges extends StatelessWidget {
  const WarningEdges({super.key, required this.hazards, required this.child});
  final Set<String> hazards;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      if (hazards.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: CustomPaint(
                key: const ValueKey('warning-edges'),
                painter: _WarningPainter(hazards),
              ),
            ),
          ),
        ),
    ],
  );
}

class _WarningPainter extends CustomPainter {
  const _WarningPainter(this.hazards);
  final Set<String> hazards;
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [
      if (hazards.contains('frost')) const Color(0xff75cef5),
      if (hazards.contains('wind')) const Color(0xff7ba6ca),
      if (hazards.contains('thunder')) const Color(0xffc39af3),
    ];
    for (var side = 0; side < 2; side++) {
      canvas.save();
      if (side == 1) {
        canvas.translate(size.width, size.height);
        canvas.rotate(math.pi);
      }
      canvas.scale(.5, .5);
      final edgeHeight = size.height * 2;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, 22, edgeHeight),
        Paint()
          ..shader = LinearGradient(
            colors: [
              colors[side % colors.length].withValues(alpha: .6),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(0, 0, 22, edgeHeight)),
      );
      var index = 0;
      for (final hazard in hazards.toList()..sort()) {
        final paint =
            Paint()
              ..color = (hazard == 'thunder'
                      ? const Color(0xffd6b8ff)
                      : const Color(0xffa0ddfa))
                  .withValues(alpha: .85)
              ..strokeWidth = 1.6
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round;
        for (double y = 42 + index * 46; y < edgeHeight; y += 138) {
          if (hazard == 'frost') {
            for (var angle = 0; angle < 3; angle++) {
              final dx = math.cos(angle * math.pi / 3) * 7;
              final dy = math.sin(angle * math.pi / 3) * 7;
              canvas.drawLine(
                Offset(9 - dx, y - dy),
                Offset(9 + dx, y + dy),
                paint,
              );
            }
          } else if (hazard == 'wind') {
            canvas.drawPath(
              Path()
                ..moveTo(0, y)
                ..quadraticBezierTo(22, y - 10, 12, y - 14)
                ..moveTo(0, y + 5)
                ..quadraticBezierTo(24, y, 17, y + 12),
              paint,
            );
          } else {
            canvas.drawPath(
              Path()
                ..moveTo(14, y - 10)
                ..lineTo(4, y + 2)
                ..lineTo(13, y + 1)
                ..lineTo(5, y + 13),
              paint,
            );
          }
        }
        index++;
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WarningPainter old) =>
      old.hazards.length != hazards.length || !old.hazards.containsAll(hazards);
}
