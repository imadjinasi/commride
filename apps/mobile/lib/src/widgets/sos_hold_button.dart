import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/commride_theme.dart';

class SosHoldButton extends StatefulWidget {
  const SosHoldButton({
    required this.onCompleted,
    this.enabled = true,
    this.active = false,
    this.working = false,
    this.duration = CommRideDurations.sosHold,
    super.key,
  });

  final Future<void> Function() onCompleted;
  final bool enabled;
  final bool active;
  final bool working;
  final Duration duration;

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  bool _holding = false;
  bool _triggered = false;

  bool get _canHold =>
      widget.enabled && !widget.active && !widget.working && !_triggered;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener(_onProgressStatus);
  }

  @override
  void didUpdateWidget(SosHoldButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _progress.duration = widget.duration;
    }
    if (widget.active || widget.working || !widget.enabled) {
      _reset();
    }
  }

  @override
  void dispose() {
    _progress
      ..removeStatusListener(_onProgressStatus)
      ..dispose();
    super.dispose();
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed ||
        !_holding ||
        _triggered ||
        !_canHold) {
      return;
    }

    _triggered = true;
    if (mounted) {
      setState(() {});
    }
    unawaited(widget.onCompleted());
  }

  void _beginHold(TapDownDetails details) {
    if (!_canHold) {
      return;
    }
    _holding = true;
    _triggered = false;
    _progress.forward(from: 0);
    setState(() {});
  }

  void _endHold() {
    if (!_holding) {
      return;
    }

    _holding = false;
    if (!_triggered) {
      _progress.animateBack(
        0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _reset() {
    _holding = false;
    _triggered = false;
    _progress.stop();
    _progress.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final Color background = Theme.of(context).colorScheme.error;
    final Color foreground = Theme.of(context).colorScheme.onError;
    final String label = widget.active
        ? 'SOS aktif'
        : widget.working
        ? 'Mengirim SOS…'
        : _holding
        ? 'Tetap tahan…'
        : 'SOS · tahan 3 dtk';

    return Semantics(
      button: true,
      enabled: _canHold,
      liveRegion: widget.active || widget.working,
      label: label,
      hint: widget.active
          ? 'SOS sudah aktif untuk Ride ini.'
          : 'Tekan dan tahan selama tiga detik untuk mengirim SOS.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _canHold ? _beginHold : null,
        onTapUp: _canHold ? (_) => _endHold() : null,
        onTapCancel: _canHold ? _endHold : null,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (BuildContext context, Widget? child) {
            final int secondsLeft =
                ((1 - _progress.value) * 3).ceil().clamp(1, 3) as int;
            return ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: CommRideTargets.sos,
                minWidth: CommRideTargets.sos,
              ),
              child: Material(
                color: background,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(CommRideRadii.md),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (_holding && !_triggered)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _progress.value,
                          child: ColoredBox(
                            color: foreground.withValues(alpha: 0.18),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CommRideSpacing.xs,
                        vertical: CommRideSpacing.xs,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.sos, color: foreground, size: 28),
                          const SizedBox(height: CommRideSpacing.xxs),
                          Text(
                            _holding && !_triggered
                                ? 'SOS · $secondsLeft dtk'
                                : label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: foreground,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
