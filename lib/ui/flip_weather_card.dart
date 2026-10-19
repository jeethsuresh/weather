import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'weather_style.dart';

/// Only the visible face is built, so its sibling never receives focus or
/// contributes hidden readings to accessibility. Swipes remain scroll gestures.
class FlipWeatherCard extends StatefulWidget {
  const FlipWeatherCard({
    super.key,
    required this.id,
    required this.title,
    required this.front,
    required this.back,
    required this.height,
    this.light = false,
    this.paper = false,
    this.storageId,
  });
  final String id, title;
  final Widget front, back;
  final double height;
  final bool light, paper;
  final String? storageId;
  @override
  State<FlipWeatherCard> createState() => _FlipWeatherCardState();
}

class _FlipWeatherCardState extends State<FlipWeatherCard>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  bool back = false;
  bool restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!restored) {
      back =
          PageStorage.maybeOf(
            context,
          )?.readState(context, identifier: widget.storageId ?? widget.id) ==
          true;
      animation.value = back ? 1 : 0;
      restored = true;
    }
  }

  void flip() {
    setState(() => back = !back);
    PageStorage.maybeOf(
      context,
    )?.writeState(context, back, identifier: widget.storageId ?? widget.id);
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.value = back ? 1 : 0;
    } else {
      animation.animateTo(back ? 1 : 0, curve: Curves.easeInOutCubic);
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final angle = animation.value * math.pi;
          final showingBack = animation.value >= .5;
          final foreground =
              widget.light || widget.paper ? ink : const Color(0xffe7f0df);
          return Transform(
            alignment: Alignment.center,
            transform:
                Matrix4.identity()
                  ..setEntry(3, 2, .001)
                  ..rotateY(angle - (showingBack ? math.pi : 0)),
            child: Semantics(
              button: true,
              label:
                  '${widget.title}, ${showingBack ? 'weather details' : 'forecast'}. Tap to flip.',
              child: Material(
                color:
                    widget.light
                        ? const Color(0xffdcebd8)
                        : widget.paper
                        ? Colors.white
                        : const Color(0xff1e3d34),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color:
                        widget.light
                            ? Colors.transparent
                            : widget.paper
                            ? const Color(0xffe0e8df)
                            : const Color(0xff33554a),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('flip-${widget.id}'),
                  onTap: flip,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground.withValues(alpha: .8),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey(
                              '${widget.id}-${showingBack ? 'back' : 'front'}',
                            ),
                            child: showingBack ? widget.back : widget.front,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.flip,
                              size: 14,
                              color: foreground.withValues(alpha: .6),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                showingBack
                                    ? 'Tap for forecast'
                                    : 'Tap for rain & wind',
                                style: TextStyle(
                                  color: foreground.withValues(alpha: .7),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
