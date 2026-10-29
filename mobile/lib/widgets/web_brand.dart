import 'dart:math' as math;
import 'package:flutter/material.dart';

class WebBrand extends StatelessWidget {
  const WebBrand({super.key});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final copper = Theme.of(context).colorScheme.secondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: -7 * math.pi / 180,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Column(
              children: [
                for (var row = 0; row < 2; row++) ...[
                  if (row == 1) const SizedBox(height: 3),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var col = 0; col < 2; col++) ...[
                          if (col == 1) const SizedBox(width: 3),
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: switch (row * 2 + col) {
                                  1 => copper,
                                  2 => const Color(0xffd9ba91),
                                  _ => color,
                                },
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 11),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                maxLines: 1,
                overflow: TextOverflow.clip,
                textScaler: TextScaler.noScaling,
                TextSpan(
                  children: [
                    const TextSpan(text: 'دامە'),
                    TextSpan(
                      text: '.',
                      style: TextStyle(color: copper),
                    ),
                  ],
                ),
                style: TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.4,
                  height: 1.3,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'DAMA · FRIENDS EDITION',
                textScaler: TextScaler.noScaling,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 6,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
