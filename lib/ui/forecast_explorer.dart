import 'package:flutter/material.dart';
import '../models.dart';
import 'forecast_cards.dart';
import 'forecast_chart_data.dart';
import 'forecast_selection.dart';
export 'forecast_selection.dart';

/// The hour strip steers the existing hero; it needs no second chart or readout.
class ForecastExplorer extends StatefulWidget {
  const ForecastExplorer({
    super.key,
    required this.forecast,
    required this.settings,
    required this.now,
    this.compact = false,
    this.selection,
  });
  final Forecast forecast;
  final Settings settings;
  final DateTime now;
  final bool compact;
  final ForecastSelectionController? selection;
  @override
  State<ForecastExplorer> createState() => _ForecastExplorerState();
}

class _ForecastExplorerState extends State<ForecastExplorer> {
  final ownSelection = ForecastSelectionController();
  @override
  void dispose() {
    ownSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.selection ?? ownSelection;
    final hours = upcomingChartRange(widget.now).hoursFrom(widget.forecast);
    final identity = forecastSelectionIdentity(
      widget.settings,
      widget.forecast,
    );
    return ListenableBuilder(
      listenable: controller,
      builder:
          (context, _) => HourlyForecastStrip(
            hours: hours,
            settings: widget.settings,
            compact: widget.compact,
            selectedTime: controller.selected(identity, hours)?.time,
            onSelected: (hour) => controller.choose(identity, hour),
          ),
    );
  }
}
