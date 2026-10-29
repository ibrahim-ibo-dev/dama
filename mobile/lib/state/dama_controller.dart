import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../game/bot.dart';
import '../game/game.dart';
import '../models/room.dart';
import '../services/api.dart';
import '../services/session_store.dart';

enum GameMode { lobby, online, hotseat, bot }

typedef BotRunner =
    Future<BotAnalysis> Function(
      Board board,
      PlayerColor color,
      BotLevel level,
    );

Future<BotAnalysis> runBotInIsolate(
  Board board,
  PlayerColor color,
  BotLevel level,
) => compute<Map<String, dynamic>, BotAnalysis>(analyzeBot, {
  'board': board,
  'color': color.name,
  'level': level.name,
}, debugLabel: 'DamaBot');

/// One state owner for the native client. Every async result is scoped to its
/// server/room generation; leaving or switching server invalidates old work.
class DamaController extends ChangeNotifier with WidgetsBindingObserver {
  DamaController({
    DamaApi? api,
    SessionStore? store,
    BotRunner? botRunner,
    this.pollInterval = const Duration(seconds: 2),
    this.autoPoll = true,
    bool observeLifecycle = true,
  }) : _api = api ?? DamaApi(),
       _store = store ?? SecureSessionStore(),
       _botRunner = botRunner ?? runBotInIsolate,
       _observesLifecycle = observeLifecycle {
    if (_observesLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  final DamaApi _api;
  final SessionStore _store;
  final BotRunner _botRunner;
  final Duration pollInterval;
  final bool autoPoll;
  final bool _observesLifecycle;
  Future<void>? _initialization;
  Timer? _pollTimer;
  Timer? _botTimer;
  bool _disposed = false, _foreground = true, _refreshing = false;
  bool _initializing = true,
      _busy = false,
      _chatBusy = false,
      _connected = true;
  bool _sessionExpired = false, _networkError = false, _botThinking = false;
  int _epoch = 0, _botEpoch = 0, _serverGeneration = 0;
  int _nameRevision = 0, _levelRevision = 0;
  bool _statusRefreshing = false;
  final Map<String, String> _identities = {};
  DateTime? _lastHeartbeat;
  String _serverUrl = defaultServerUrl, _name = '', _savedRoomCode = '';
  String? _error;
  ServerStatus? _status;
  RoomSnapshot? _room;
  GameState? _solo;
  GameMode _mode = GameMode.lobby;
  BotLevel _botLevel = BotLevel.medium;
  final List<GameState> _undo = [];
  int? _selectionFrom;
  List<int> _selectionPath = [];

  bool get initializing => _initializing;
  bool get busy => _busy;
  bool get chatBusy => _chatBusy;
  bool get connected => _connected;
  bool get botThinking => _botThinking;
  bool get foreground => _foreground;
  bool get sessionExpired => _sessionExpired;
  String? get error => _error;
  String get serverUrl => _serverUrl;
  String get name => _name;
  String get savedRoomCode => _savedRoomCode;
  ServerStatus? get status => _status;
  RoomSnapshot? get room => _room;
  GameState? get game => _room?.game ?? _solo;
  GameMode get mode => _mode;
  BotLevel get botLevel => _botLevel;
  RoomMember? get me => _room?.self;
  String get role => _mode == GameMode.online
      ? me?.role ?? 'spectator'
      : _solo != null
      ? 'white'
      : 'spectator';
  PlayerColor? get myColor => _mode == GameMode.online
      ? me?.color
      : _solo != null
      ? PlayerColor.white
      : null;
  bool get isSpectator => _mode == GameMode.online && myColor == null;
  bool get canUndo => _solo != null && _undo.isNotEmpty;
  int? get selectionFrom => _selectionFrom;
  List<int> get selectionPath => List.unmodifiable(_selectionPath);
  List<DamaMove> get moves => game == null || game!.winner != null
      ? const []
      : legalMoves(game!.board, game!.turn);
  List<DamaMove> get _selectionMoves => _selectionFrom == null
      ? const []
      : moves
            .where(
              (move) =>
                  move.from == _selectionFrom &&
                  _selectionPath.asMap().entries.every(
                    (entry) =>
                        entry.key < move.path.length &&
                        move.path[entry.key] == entry.value,
                  ),
            )
            .toList();
  Set<int> get legalTargets => {
    for (final move in _selectionMoves)
      if (move.path.length > _selectionPath.length)
        move.path[_selectionPath.length],
  };
  Board get displayBoard {
    final current = game;
    if (current == null) return initialBoard();
    if (_selectionPath.isEmpty || _selectionMoves.isEmpty) return current.board;
    return previewMove(
      current.board,
      _selectionMoves.first,
      _selectionPath.length,
    );
  }

  bool get canPlay {
    final current = game;
    if (current == null ||
        current.winner != null ||
        _busy ||
        _chatBusy ||
        !_foreground) {
      return false;
    }
    if (_mode == GameMode.online) {
      return _connected &&
          !_sessionExpired &&
          _room!.started &&
          myColor == current.turn;
    }
    if (_mode == GameMode.bot) {
      return current.turn == PlayerColor.white && !_botThinking;
    }
    return _mode == GameMode.hotseat;
  }

  String playerName(PlayerColor color) {
    if (_mode == GameMode.online) {
      return _room!.members
              .where((member) => member.color == color)
              .firstOrNull
              ?.name ??
          'چاوەڕوانی هاوڕێکەت…';
    }
    if (_mode == GameMode.bot && color == PlayerColor.black) return 'بۆتی دامە';
    if (color == PlayerColor.white && _name.trim().isNotEmpty) {
      return _name.trim();
    }
    return color == PlayerColor.white ? 'یاریزانی سپی' : 'یاریزانی ڕەش';
  }

  String get opponentName => playerName(
    myColor == PlayerColor.black ? PlayerColor.white : PlayerColor.black,
  );
  String get inviteUrl =>
      _room == null ? '' : '$_serverUrl/?room=${_room!.code}';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch, [String? code]) =>
      !_disposed && _epoch == epoch && (code == null || _room?.code == code);
  bool _sameServer(int generation) =>
      !_disposed && _serverGeneration == generation;
  void clearError() {
    _error = null;
    _networkError = false;
    _notify();
  }

  void _setError(Object error) {
    _error = error is ApiException
        ? error.message
        : error is FormatException
        ? error.message
        : 'هەڵەیەک ڕوویدا. دووبارە هەوڵ بدەوە.';
    _networkError = error is ApiException && error.isNetworkError;
  }

  void _clearSelection() {
    _selectionFrom = null;
    _selectionPath = [];
  }

  void cancelSelection() {
    _clearSelection();
    _notify();
  }

  Future<void> initialize() => _initialization ??= _initialize();
  Future<String?> _readPreference(String key) async {
    try {
      return await _store.read(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistPreference(
    String key,
    String? value, {
    required int epoch,
  }) async {
    try {
      if (value == null) {
        await _store.remove(key);
      } else {
        await _store.write(key, value);
      }
    } catch (_) {
      if (_current(epoch)) {
        _error = 'گۆڕانکارییەکە کار دەکات، بەڵام لەسەر ئامێرەکە هەڵنەگیرا.';
        _networkError = false;
      }
    }
  }

  Future<void> _initialize() async {
    final epoch = _epoch, serverGeneration = _serverGeneration;
    final nameRevision = _nameRevision, levelRevision = _levelRevision;
    try {
      final savedServer = await _readPreference('dama.server');
      if (_sameServer(serverGeneration)) {
        try {
          _serverUrl = normalizeServerUrl(savedServer ?? _api.serverUrl);
        } on ApiException {
          _serverUrl = normalizeServerUrl(_api.serverUrl);
        }
      }
      final savedName = await _readPreference('dama.name');
      if (!_disposed && _nameRevision == nameRevision) _name = savedName ?? '';
      final level = await _readPreference('dama.botLevel');
      if (!_disposed && _levelRevision == levelRevision) {
        _botLevel =
            BotLevel.values.where((item) => item.name == level).firstOrNull ??
            BotLevel.medium;
      }
      if (!_sameServer(serverGeneration) ||
          !await _loadIdentity(serverGeneration)) {
        return;
      }
      final savedRoom = await _readPreference('dama.room') ?? '';
      if (!_sameServer(serverGeneration)) return;
      if (_current(epoch)) _savedRoomCode = savedRoom;
      try {
        final next = await _api.getStatus();
        if (_sameServer(serverGeneration)) _status = next;
      } catch (error) {
        if (_sameServer(serverGeneration) && _current(epoch)) {
          _setError(error);
          _connected = false;
        }
      }
      if (savedRoom.isNotEmpty &&
          _sameServer(serverGeneration) &&
          _current(epoch)) {
        try {
          final next = await _api.getRoom(savedRoom);
          if (_sameServer(serverGeneration) && _current(epoch)) {
            _accept(next);
            _mode = GameMode.online;
          }
        } catch (error) {
          if (_sameServer(serverGeneration) && _current(epoch)) {
            if (error is ApiException && error.sessionMissing) {
              _savedRoomCode = '';
              await _persistPreference('dama.room', null, epoch: epoch);
            }
            _setError(error);
          }
        }
      }
    } catch (error) {
      if (_sameServer(serverGeneration) && _current(epoch)) _setError(error);
    } finally {
      // Local play may have changed the room epoch while storage/network was
      // pending. Readiness still has to settle when that background work ends.
      if (!_disposed) {
        _initializing = false;
        _notify();
        _schedulePoll();
      }
    }
  }

  Future<bool> _loadIdentity(int serverGeneration) async {
    final server = _serverUrl;
    String? saved;
    var persisted = true;
    var canPersist = true;
    try {
      saved = await _store.readToken(server);
    } catch (_) {
      persisted = false;
      canPersist = false;
    }
    if (!_sameServer(serverGeneration)) return false;
    final validSaved =
        saved != null && RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(saved);
    final token =
        _identities[server] ?? (validSaved ? saved : createPlayerToken());
    _identities[server] = token;
    _api.configure(serverUrl: server, token: token);
    if (token != saved && canPersist) {
      try {
        await _store.writeToken(server, token);
      } catch (_) {
        persisted = false;
      }
    }
    if (!_sameServer(serverGeneration)) return false;
    if (!persisted && _mode == GameMode.lobby) {
      _error =
          'ناسنامەی یاری لە بیرگەی کاتییە؛ دوای داخستنی ئەپ لەوانەیە نەگەڕێیتەوە بۆ هەمان شوێن.';
      _networkError = false;
    }
    return true;
  }

  void setName(String value) {
    _nameRevision++;
    _name = value;
    unawaited(_store.write('dama.name', value).catchError((_) {}));
    _notify();
  }

  Future<bool> setServerUrl(String value) async {
    if (_busy || _chatBusy || game != null) return false;
    try {
      final next = normalizeServerUrl(value);
      if (next == _serverUrl) return true;
      _busy = true;
      _epoch++;
      _serverGeneration++;
      _initializing = false;
      _cancelPoll();
      _cancelBot();
      _status = null;
      _serverUrl = next;
      _savedRoomCode = '';
      _error = null;
      _notify();
      final epoch = _epoch;
      final serverGeneration = _serverGeneration;
      await _persistPreference('dama.server', next, epoch: epoch);
      await _persistPreference('dama.room', null, epoch: epoch);
      if (!await _loadIdentity(serverGeneration)) return false;
      try {
        final status = await _api.getStatus();
        if (_current(epoch)) {
          _status = status;
          _connected = true;
        }
      } catch (error) {
        if (_current(epoch)) {
          _setError(error);
          _connected = false;
        }
      }
      return _current(epoch);
    } catch (error) {
      _setError(error);
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _accept(RoomSnapshot next) {
    if (_room?.code == next.code && _room!.revision > next.revision) return;
    final changedGame =
        _room?.game.id != next.game.id || _room?.game.ply != next.game.ply;
    _room = next;
    _solo = null;
    _mode = GameMode.online;
    _connected = true;
    _sessionExpired = false;
    if (_networkError) {
      _error = null;
      _networkError = false;
    }
    if (changedGame) _clearSelection();
  }

  Future<bool> _enter(Future<RoomSnapshot> Function() request) async {
    if (_busy || _chatBusy || game != null || _initializing) return false;
    if (_name.trim().isEmpty || _name.trim().length > 24) {
      _error = 'ناوەکەت لە ١ بۆ ٢٤ پیت بێت.';
      _notify();
      return false;
    }
    _busy = true;
    _error = null;
    _notify();
    final epoch = ++_epoch;
    try {
      final next = await request();
      if (!_current(epoch)) return false;
      _accept(next);
      _savedRoomCode = next.code;
      _lastHeartbeat = null;
      await _persistPreference('dama.room', next.code, epoch: epoch);
      return true;
    } catch (error) {
      if (_current(epoch)) _setError(error);
      return false;
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _notify();
        _schedulePoll();
      }
    }
  }

  Future<bool> createRoom({String password = ''}) =>
      _enter(() => _api.createRoom(name: _name.trim(), password: password));
  Future<bool> joinRoom(
    String code, {
    String password = '',
    bool spectator = false,
  }) => _enter(
    () => _api.joinRoom(
      code,
      name: _name.trim(),
      password: password,
      spectator: spectator,
    ),
  );

  Future<bool> _action(Map<String, dynamic> body, {bool chat = false}) async {
    final current = _room;
    if (current == null || _busy || _chatBusy || _sessionExpired) return false;
    final epoch = _epoch, code = current.code;
    if (chat) {
      _chatBusy = true;
    } else {
      _busy = true;
    }
    _error = null;
    _notify();
    try {
      final next = await _api.action(code, body);
      if (!_current(epoch, code)) return false;
      _accept(next);
      return true;
    } catch (error) {
      if (_current(epoch, code)) {
        _setError(error);
        if (error is ApiException && error.sessionMissing) {
          _sessionExpired = true;
          _connected = false;
          _cancelPoll();
        } else {
          try {
            final next = await _api.getRoom(code);
            if (_current(epoch, code)) _accept(next);
          } catch (_) {
            if (_current(epoch, code)) _connected = false;
          }
        }
      }
      return false;
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _chatBusy = false;
        _notify();
        _schedulePoll();
      }
    }
  }

  Future<bool> play(DamaMove move) async {
    if (!canPlay) return false;
    final current = game!;
    if (_mode == GameMode.online) {
      return _action({
        'type': 'move',
        'from': move.from,
        'path': move.path,
        'ply': current.ply,
        'gameId': current.id,
      });
    }
    try {
      final next = playMove(current, move.from, move.path);
      _undo.add(current);
      if (_undo.length > 80) _undo.removeAt(0);
      _solo = next;
      _clearSelection();
      _error = null;
      _notify();
      _scheduleBot();
      return true;
    } catch (error) {
      _setError(error);
      _notify();
      return false;
    }
  }

  void tapSquare(int square) {
    if (!canPlay || square < 0 || square >= 64) return;
    if (_selectionFrom != null && legalTargets.contains(square)) {
      final path = [..._selectionPath, square];
      final complete = _selectionMoves
          .where(
            (move) =>
                move.path.length == path.length &&
                move.path.asMap().entries.every(
                  (entry) => path[entry.key] == entry.value,
                ),
          )
          .firstOrNull;
      if (complete != null) {
        unawaited(play(complete));
      } else {
        _selectionPath = path;
        _notify();
      }
    } else if (_selectionPath.isEmpty &&
        moves.any((move) => move.from == square)) {
      _selectionFrom = _selectionFrom == square ? null : square;
      _selectionPath = [];
      _notify();
    }
  }

  void startSolo({BotLevel level = BotLevel.medium}) {
    if (_room != null || _busy || _chatBusy) return;
    _startLocal(GameMode.bot, level);
  }

  void startHotseat() {
    if (_room != null || _busy || _chatBusy) return;
    _startLocal(GameMode.hotseat, _botLevel);
  }

  void _startLocal(GameMode mode, BotLevel level) {
    _epoch++;
    _cancelPoll();
    _cancelBot();
    _room = null;
    _mode = mode;
    _levelRevision++;
    _botLevel = level;
    _solo = newGame(
      'native-${DateTime.now().microsecondsSinceEpoch}-${createPlayerToken().substring(0, 8)}',
    );
    _undo.clear();
    _clearSelection();
    _error = null;
    _connected = true;
    _notify();
    unawaited(_store.write('dama.botLevel', level.name).catchError((_) {}));
  }

  void setBotLevel(BotLevel level) {
    if (_botLevel == level) return;
    _levelRevision++;
    _cancelBot();
    _botLevel = level;
    _error = null;
    _notify();
    _scheduleBot();
    unawaited(_store.write('dama.botLevel', level.name).catchError((_) {}));
  }

  void undo() {
    if (!canUndo || _busy) return;
    _cancelBot();
    var index = _undo.length - 1;
    if (_mode == GameMode.bot) {
      while (index > 0 && _undo[index].turn != PlayerColor.white) {
        index--;
      }
    }
    _solo = _undo[index];
    _undo.removeRange(index, _undo.length);
    _clearSelection();
    _error = null;
    _notify();
    _scheduleBot();
  }

  void _cancelBot() {
    _botEpoch++;
    _botTimer?.cancel();
    _botTimer = null;
    _botThinking = false;
  }

  void _scheduleBot() {
    final current = _solo;
    if (_disposed ||
        !_foreground ||
        _mode != GameMode.bot ||
        current == null ||
        current.winner != null ||
        current.turn != PlayerColor.black) {
      return;
    }
    _cancelBot();
    final epoch = _botEpoch, session = _epoch, level = _botLevel;
    _botThinking = true;
    _notify();
    _botTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final analysis = await _botRunner(current.board, current.turn, level);
        if (!_current(session) ||
            epoch != _botEpoch ||
            !_foreground ||
            _solo?.id != current.id ||
            _solo?.ply != current.ply) {
          return;
        }
        final move = analysis.move;
        if (move != null) {
          final next = playMove(current, move.from, move.path);
          _undo.add(current);
          if (_undo.length > 80) _undo.removeAt(0);
          _solo = next;
          _clearSelection();
        } else {
          _error = 'بۆتەکە جووڵەیەکی نەدۆزییەوە؛ یارییەکە نوێ بکەرەوە.';
        }
      } catch (error) {
        if (_current(session) && epoch == _botEpoch) _setError(error);
      } finally {
        if (_current(session) && epoch == _botEpoch) {
          _botThinking = false;
          _notify();
        }
      }
    });
  }

  void retryBot() {
    _error = null;
    _scheduleBot();
  }

  Future<bool> sendMessage(String text) => text.trim().isEmpty
      ? Future.value(false)
      : _action({'type': 'message', 'text': text}, chat: true);
  Future<bool> offerDraw() => game == null
      ? Future.value(false)
      : _action({'type': 'draw', 'gameId': game!.id});
  Future<bool> declineDraw() => game == null
      ? Future.value(false)
      : _action({'type': 'decline-draw', 'gameId': game!.id});
  Future<bool> resign() async {
    final current = game;
    if (current == null || current.winner != null) return false;
    if (_mode == GameMode.online) {
      return _action({'type': 'resign', 'gameId': current.id});
    }
    _cancelBot();
    final loser = _mode == GameMode.bot ? PlayerColor.white : current.turn;
    _solo = current.copyWith(winner: opposite(loser).name, reason: 'resign');
    _clearSelection();
    _notify();
    return true;
  }

  Future<bool> rematch() async {
    if (game == null || game!.winner == null) return false;
    if (_mode == GameMode.online) {
      return _action({'type': 'rematch', 'gameId': game!.id});
    }
    _startLocal(_mode, _botLevel);
    return true;
  }

  void restartLocal() {
    if (_solo != null) _startLocal(_mode, _botLevel);
  }

  Future<bool> leave() async {
    if (_busy) return false;
    final current = _room;
    final epoch = ++_epoch;
    _cancelBot();
    _cancelPoll();
    _busy = true;
    _chatBusy = false;
    _notify();
    try {
      if (current != null) {
        try {
          await _api.leaveRoom(current.code);
        } on ApiException catch (error) {
          if (!error.sessionMissing) rethrow;
        }
      }
      if (!_current(epoch)) return false;
      _room = null;
      _solo = null;
      _mode = GameMode.lobby;
      _undo.clear();
      _clearSelection();
      _error = null;
      _sessionExpired = false;
      _connected = true;
      _savedRoomCode = '';
      await _persistPreference('dama.room', null, epoch: epoch);
      return true;
    } catch (error) {
      if (_current(epoch)) _setError(error);
      return false;
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _notify();
        _schedulePoll();
      }
    }
  }

  void _cancelPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _schedulePoll() {
    _cancelPoll();
    if (!autoPoll ||
        _disposed ||
        !_foreground ||
        _room == null ||
        _sessionExpired) {
      return;
    }
    _pollTimer = Timer(pollInterval, () => unawaited(refresh()));
  }

  Future<void> refresh() async {
    final current = _room;
    if (_disposed || !_foreground) return;
    if (current == null) {
      await refreshStatus();
      return;
    }
    if (_refreshing) {
      _schedulePoll();
      return;
    }
    if (_busy || _chatBusy) {
      _schedulePoll();
      return;
    }
    _refreshing = true;
    final epoch = _epoch, code = current.code;
    try {
      final heartbeat =
          _lastHeartbeat == null ||
          DateTime.now().difference(_lastHeartbeat!) >=
              const Duration(seconds: 20);
      final next = heartbeat
          ? await _api.action(code, {'type': 'heartbeat'})
          : await _api.getRoom(code);
      if (_current(epoch, code)) {
        if (heartbeat) _lastHeartbeat = DateTime.now();
        _accept(next);
        _notify();
      }
    } catch (error) {
      if (_current(epoch, code)) {
        _connected = false;
        _setError(error);
        if (error is ApiException && error.sessionMissing) {
          _sessionExpired = true;
        }
        _notify();
      }
    } finally {
      _refreshing = false;
      if (_current(epoch, code)) _schedulePoll();
    }
  }

  Future<void> refreshStatus() async {
    if (_disposed ||
        !_foreground ||
        _initializing ||
        _busy ||
        _statusRefreshing ||
        _mode != GameMode.lobby) {
      return;
    }
    final generation = _serverGeneration, epoch = _epoch;
    _statusRefreshing = true;
    try {
      final next = await _api.getStatus();
      if (_sameServer(generation) && _current(epoch)) {
        _status = next;
        _connected = true;
        if (_networkError) {
          _error = null;
          _networkError = false;
        }
        if (_savedRoomCode.isNotEmpty) {
          try {
            final room = await _api.getRoom(_savedRoomCode);
            if (_sameServer(generation) && _current(epoch)) {
              _accept(room);
              _lastHeartbeat = null;
              _schedulePoll();
            }
          } catch (error) {
            if (_sameServer(generation) && _current(epoch)) {
              if (error is ApiException && error.sessionMissing) {
                _savedRoomCode = '';
                await _persistPreference('dama.room', null, epoch: epoch);
              }
              _setError(error);
              _connected = false;
            }
          }
        }
      }
    } catch (error) {
      if (_sameServer(generation) && _current(epoch)) {
        _setError(error);
        _connected = false;
      }
    } finally {
      _statusRefreshing = false;
      if (_sameServer(generation) && _current(epoch)) _notify();
    }
  }

  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _cancelPoll();
      _cancelBot();
    } else {
      if (_room != null) unawaited(refresh());
      _scheduleBot();
    }
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _serverGeneration++;
    _cancelPoll();
    _cancelBot();
    if (_observesLifecycle) WidgetsBinding.instance.removeObserver(this);
    _api.close();
    super.dispose();
  }
}
