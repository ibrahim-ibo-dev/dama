import 'package:flutter/material.dart';
import '../preferences.dart';
import '../state/dama_controller.dart';

void showWebSettings(
  BuildContext context,
  AppPreferences prefs,
  DamaController controller,
) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 480,
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      child: AnimatedBuilder(
        animation: prefs,
        builder: (context, _) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'بە شێوەی خۆت یاری بکە',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'داخستن',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'ئەو ڕووکار و وردەکارییانە هەڵبژێرە کە بۆ تۆ ئاسوودەترن. هەڵبژاردنەکانت لەسەر ئەم ئامێرە دەپارێزرێن.',
                style: TextStyle(fontSize: 11, height: 2),
              ),
              const SizedBox(height: 22),
              const Text(
                'ڕووناکی ڕووکار',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final option in [
                    (false, 'ڕۆژ', Icons.light_mode_outlined),
                    (true, 'شەو', Icons.dark_mode_outlined),
                  ]) ...[
                    if (option.$1) const SizedBox(width: 10),
                    Expanded(
                      child: _Choice(
                        selected: prefs.dark == option.$1,
                        onTap: () => prefs.update(dark: option.$1),
                        child: Row(
                          children: [
                            Icon(option.$3, size: 19),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                option.$2,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (prefs.dark == option.$1)
                              const Icon(Icons.check_rounded, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 22),
              const Text(
                'شێوەی تەختە',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final board in [
                    (
                      'wood',
                      'داری گوێز',
                      const Color(0xffede2cb),
                      const Color(0xffd2bd99),
                    ),
                    (
                      'olive',
                      'زەیتوون',
                      const Color(0xffeeedda),
                      const Color(0xffbec5a4),
                    ),
                    (
                      'slate',
                      'بەردی شین',
                      const Color(0xffe7e9e0),
                      const Color(0xffb5c4be),
                    ),
                  ]) ...[
                    if (board.$1 != 'wood') const SizedBox(width: 8),
                    Expanded(
                      child: _Choice(
                        selected: prefs.boardStyle == board.$1,
                        onTap: () => prefs.update(boardStyle: board.$1),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 40,
                              height: 32,
                              child: Column(
                                children: [
                                  for (var row = 0; row < 2; row++)
                                    Expanded(
                                      child: Row(
                                        children: [
                                          for (var col = 0; col < 2; col++)
                                            Expanded(
                                              child: ColoredBox(
                                                color: (row + col).isEven
                                                    ? board.$3
                                                    : board.$4,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              board.$2,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),
              _PreferenceSwitch(
                icon: Icons.volume_up_outlined,
                title: 'دەنگی جووڵەکان',
                description: 'دەنگێکی نەرم لەگەڵ هەر جووڵەیەک',
                value: prefs.sound,
                onChanged: (v) => prefs.update(sound: v),
              ),
              _PreferenceSwitch(
                icon: Icons.grid_4x4_rounded,
                title: 'پیت و ژمارەی خانەکان',
                description: 'ئاسانتر شوێنی بەردەکان بناسەوە',
                value: prefs.coordinates,
                onChanged: (v) => prefs.update(coordinates: v),
              ),
              _PreferenceSwitch(
                icon: Icons.lightbulb_outline_rounded,
                title: 'ئاماژەی جووڵەکان',
                description: 'شوێنە ڕێگەپێدراوەکان ڕوون بکەرەوە',
                value: prefs.targets,
                onChanged: (v) => prefs.update(targets: v),
              ),
              _PreferenceSwitch(
                icon: Icons.vibration_rounded,
                title: 'لەرینەوەی سووک',
                description: 'هەستێکی سووک لەگەڵ جووڵەکان',
                value: prefs.vibration,
                onChanged: (v) => prefs.update(vibration: v),
              ),
              if (prefs.coachEnabled)
                TextButton.icon(
                  onPressed: () => prefs.update(coachEnabled: false),
                  icon: const Icon(Icons.visibility_off_outlined, size: 16),
                  label: const Text(
                    'شاردنەوەی یارمەتیدەر',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'ناونیشانی وێبەکە',
                  style: TextStyle(fontSize: 11),
                ),
                children: [
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(
                      controller.serverUrl,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 10,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: controller.mode == GameMode.lobby
                        ? () async {
                            final input = TextEditingController(
                              text: controller.serverUrl,
                            );
                            final url = await showDialog<String>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('ناونیشانی وێب'),
                                content: TextField(
                                  controller: input,
                                  textDirection: TextDirection.ltr,
                                  keyboardType: TextInputType.url,
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                    hintText: 'https://dama.ibrahim-eng.dev',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('پاشگەزبوونەوە'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, input.text),
                                    child: const Text('هەڵگرتن'),
                                  ),
                                ],
                              ),
                            );
                            await Future<void>.delayed(
                              const Duration(milliseconds: 250),
                            );
                            input.dispose();
                            if (url != null) await controller.setServerUrl(url);
                          }
                        : null,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text(
                      'گۆڕینی ناونیشان',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: const Text('تەواو، ئامادەم'),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.onTap,
    required this.child,
  });
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .08)
              : null,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    ),
  );
}

class _PreferenceSwitch extends StatelessWidget {
  const _PreferenceSwitch({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title, description;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(
                  fontSize: 8,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .55),
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ],
    ),
  );
}
