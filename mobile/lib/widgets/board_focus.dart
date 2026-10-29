import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A native board-only route. Pass the game controller as [listenable] and
/// construct the board from its current state in [boardBuilder].
class BoardFocus extends StatefulWidget {
  const BoardFocus({
    super.key,
    required this.boardBuilder,
    this.listenable,
    this.restoreMode = SystemUiMode.edgeToEdge,
    this.restoreOverlays,
  });

  final WidgetBuilder boardBuilder;
  final Listenable? listenable;
  final SystemUiMode restoreMode;
  final List<SystemUiOverlay>? restoreOverlays;

  @override
  State<BoardFocus> createState() => _BoardFocusState();
}

class _BoardFocusState extends State<BoardFocus> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_setSystemMode(SystemUiMode.immersiveSticky));
  }

  Future<void> _setSystemMode(
    SystemUiMode mode, {
    List<SystemUiOverlay>? overlays,
  }) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        mode,
        overlays: mode == SystemUiMode.manual
            ? overlays ?? SystemUiOverlay.values
            : null,
      );
    } on PlatformException {
      // The route remains a full-window board if the platform declines.
    } on MissingPluginException {
      // Some desktop/test hosts do not expose system UI controls.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_setSystemMode(SystemUiMode.immersiveSticky));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
      _setSystemMode(widget.restoreMode, overlays: widget.restoreOverlays),
    );
    super.dispose();
  }

  Widget _liveBoard(BuildContext context) => widget.listenable == null
      ? widget.boardBuilder(context)
      : AnimatedBuilder(
          animation: widget.listenable!,
          builder: (context, _) => widget.boardBuilder(context),
        );

  @override
  Widget build(BuildContext context) => Semantics(
    namesRoute: true,
    label: 'دۆخی تەنیا تەختە',
    child: Scaffold(
      backgroundColor: const Color(0xFF102219),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.15),
            radius: 1,
            colors: [Color(0xFF2A4032), Color(0xFF102219)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = math.max(
                    0.0,
                    math.min(
                      constraints.maxWidth - 16,
                      constraints.maxHeight - 56,
                    ),
                  );
                  return Center(
                    child: SizedBox.square(
                      dimension: size,
                      child: _liveBoard(context),
                    ),
                  );
                },
              ),
              PositionedDirectional(
                top: 5,
                end: 7,
                child: IconButton.filledTonal(
                  tooltip: 'دەرچوون لە دۆخی تەنیا تەختە',
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFE3EBD9),
                    backgroundColor: const Color(0x662B4333),
                    minimumSize: const Size(40, 40),
                    maximumSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 21),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
