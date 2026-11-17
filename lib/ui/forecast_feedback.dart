import 'dart:async';
import 'package:flutter/material.dart';
import '../models.dart';

/// A changed reading from a newer forecast, never a loading/success surrogate.
class ForecastRefreshFeedback extends StatefulWidget {
  const ForecastRefreshFeedback({
    super.key,
    required this.forecast,
    required this.child,
  });
  final Forecast forecast;
  final Widget child;
  @override
  State<ForecastRefreshFeedback> createState() =>
      _ForecastRefreshFeedbackState();
}

class _ForecastRefreshFeedbackState extends State<ForecastRefreshFeedback>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  Timer? clear;
  bool active = false;
  bool reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) animation.value = 0;
  }

  @override
  void didUpdateWidget(covariant ForecastRefreshFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.forecast;
    final after = widget.forecast;
    if (before.source != after.source ||
        !after.fetchedAt.isAfter(before.fetchedAt)) {
      return;
    }
    if (before.temperature == after.temperature &&
        before.summary == after.summary &&
        before.feelsLike == after.feelsLike &&
        before.wind == after.wind &&
        before.humidity == after.humidity) {
      return;
    }
    clear?.cancel();
    active = true;
    animation.value = reduced ? 0 : 1;
    if (!reduced) animation.reverse();
    clear = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => active = false);
    });
  }

  @override
  void dispose() {
    clear?.cancel();
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: widget.child,
    builder:
        (context, child) => Stack(
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('forecast-refresh-accent'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      width: 2,
                      color: const Color(0xffa8dafa).withValues(
                        alpha:
                            reduced ? (active ? .9 : 0) : animation.value * .9,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
  );
}
