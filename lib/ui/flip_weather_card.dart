import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'weather_style.dart';
import 'interaction_juice.dart';

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
    this.background,
    this.headerAction,
  });
  final String id, title;
  final Widget front, back;
  final double height;
  final bool light, paper;
  final String? storageId;
  final Color? background;
  final Widget? headerAction;
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
    if (MediaQuery.disableAnimationsOf(context) && animation.isAnimating) {
      animation.value = back ? 1 : 0;
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
      child: ElasticInteraction(
        depth: .035,
        tilt: .012,
        travel: 0,
        builder:
            (context, pose) => AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final angle = animation.value * math.pi;
                final showingBack = animation.value >= .5;
                final foreground =
                    widget.light || widget.paper
                        ? ink
                        : const Color(0xffe8f2fc);
                final shape = RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color:
                        widget.light
                            ? Colors.transparent
                            : widget.paper
                            ? const Color(0xffd5e3ee)
                            : const Color(0xff3c6080),
                  ),
                );
                return Transform(
                  alignment: Alignment.center,
                  transformHitTests: false,
                  transform:
                      Matrix4.identity()
                        ..setEntry(3, 2, .001)
                        ..rotateY(angle - (showingBack ? math.pi : 0))
                        ..rotateZ(pose.energy * .012),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: pose.deform(
                            AnimatedContainer(
                              duration:
                                  MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              decoration: ShapeDecoration(
                                shape: shape,
                                color:
                                    widget.background ??
                                    (widget.light
                                        ? const Color(0xffb5dffa)
                                        : widget.paper
                                        ? Colors.white
                                        : const Color(0xff203e59)),
                              ),
                            ),
                            position: false,
                          ),
                        ),
                      ),
                      Semantics(
                        button: true,
                        label:
                            showingBack
                                ? 'Show temperature forecast'
                                : 'Show rain and wind',
                        child: Material(
                          color: Colors.transparent,
                          shape: shape,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('flip-${widget.id}'),
                            onTap: flip,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          widget.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: foreground.withValues(
                                              alpha: .8,
                                            ),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                      if (widget.headerAction != null)
                                        widget.headerAction!,
                                      ExcludeSemantics(
                                        child: ElasticArt(
                                          gain: 2,
                                          child: Icon(
                                            Icons.flip,
                                            size: 16,
                                            color: foreground.withValues(
                                              alpha: .6,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: KeyedSubtree(
                                      key: ValueKey(
                                        '${widget.id}-${showingBack ? 'back' : 'front'}',
                                      ),
                                      child:
                                          showingBack
                                              ? widget.back
                                              : widget.front,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }
}
