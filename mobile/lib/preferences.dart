import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  bool _disposed = false;
  int _revision = 0;
  bool dark = false;
  bool coordinates = true;
  bool targets = true;
  bool sound = true;
  bool vibration = true;
  bool coachEnabled = false;
  String boardStyle = 'wood';

  Future<void> load() async {
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed || revision != _revision) return;
      dark = prefs.getBool('dama.dark') ?? false;
      coordinates = prefs.getBool('dama.coordinates') ?? true;
      targets = prefs.getBool('dama.targets') ?? true;
      sound = prefs.getBool('dama.sound') ?? true;
      vibration = prefs.getBool('dama.vibration') ?? true;
      coachEnabled = prefs.getBool('dama.coach') ?? false;
      final style = prefs.getString('dama.board') ?? 'wood';
      boardStyle = ['wood', 'olive', 'slate'].contains(style) ? style : 'wood';
      notifyListeners();
    } catch (_) {
      // Appearance preferences remain usable in memory when storage is unavailable.
    }
  }

  Future<void> update({
    bool? dark,
    bool? coordinates,
    bool? targets,
    bool? sound,
    bool? vibration,
    String? boardStyle,
    bool? coachEnabled,
  }) async {
    if (_disposed) return;
    _revision++;
    this.dark = dark ?? this.dark;
    this.coordinates = coordinates ?? this.coordinates;
    this.targets = targets ?? this.targets;
    this.sound = sound ?? this.sound;
    this.vibration = vibration ?? this.vibration;
    this.boardStyle = boardStyle ?? this.boardStyle;
    this.coachEnabled = coachEnabled ?? this.coachEnabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setBool('dama.dark', this.dark),
        prefs.setBool('dama.coordinates', this.coordinates),
        prefs.setBool('dama.targets', this.targets),
        prefs.setBool('dama.sound', this.sound),
        prefs.setBool('dama.vibration', this.vibration),
        prefs.setBool('dama.coach', this.coachEnabled),
        prefs.setString('dama.board', this.boardStyle),
      ]);
    } catch (_) {
      // A disk error must not prevent changing the current game's appearance.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
