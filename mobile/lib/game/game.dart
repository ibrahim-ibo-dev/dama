/// Pure Dart Turkish / Kurdish dama rules. JSON matches the web game's API.
library;

typedef Board = List<int>;

enum PlayerColor { white, black }

PlayerColor opposite(PlayerColor color) =>
    color == PlayerColor.white ? PlayerColor.black : PlayerColor.white;

PlayerColor? pieceColor(int piece) => piece > 0
    ? PlayerColor.white
    : piece < 0
    ? PlayerColor.black
    : null;

PlayerColor playerColorFromName(String value) => switch (value) {
  'white' => PlayerColor.white,
  'black' => PlayerColor.black,
  _ => throw FormatException('Unknown player color: $value'),
};

String coordinate(int square) => '${'abcdefgh'[square % 8]}${8 - square ~/ 8}';

bool _sameList(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<int> _jsonInts(dynamic value) =>
    (value as List).map((item) => (item as num).toInt()).toList();

Map<String, dynamic> _jsonMap(dynamic value) =>
    (value as Map).cast<String, dynamic>();

class DamaMove {
  DamaMove({
    required this.from,
    required List<int> path,
    List<int> captures = const [],
  }) : path = List<int>.unmodifiable(path),
       captures = List<int>.unmodifiable(captures);

  final int from;
  final List<int> path;
  final List<int> captures;

  factory DamaMove.fromJson(Map<String, dynamic> json) => DamaMove(
    from: (json['from'] as num).toInt(),
    path: _jsonInts(json['path']),
    captures: json['captures'] == null ? [] : _jsonInts(json['captures']),
  );

  Map<String, dynamic> toJson() => {
    'from': from,
    'path': path,
    'captures': captures,
  };

  String get label =>
      [from, ...path].map(coordinate).join(captures.isEmpty ? ' → ' : ' × ');

  @override
  bool operator ==(Object other) =>
      other is DamaMove &&
      other.from == from &&
      _sameList(other.path, path) &&
      _sameList(other.captures, captures);

  @override
  int get hashCode =>
      Object.hash(from, Object.hashAll(path), Object.hashAll(captures));

  @override
  String toString() => label;
}

class MoveRecord {
  const MoveRecord({
    required this.color,
    required this.label,
    required this.captures,
  });

  final PlayerColor color;
  final String label;
  final int captures;

  factory MoveRecord.fromJson(Map<String, dynamic> json) => MoveRecord(
    color: playerColorFromName(json['color'] as String),
    label: json['label'] as String,
    captures: (json['captures'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'color': color.name,
    'label': label,
    'captures': captures,
  };
}

const _unset = Object();

class GameState {
  GameState({
    required this.id,
    required Board board,
    required this.turn,
    this.ply = 0,
    this.winner,
    this.reason,
    this.lastMove,
    List<MoveRecord> history = const [],
    Map<String, int> positions = const {},
  }) : board = List<int>.unmodifiable(board),
       history = List<MoveRecord>.unmodifiable(history),
       positions = Map<String, int>.unmodifiable(positions) {
    if (board.length != 64 || board.any((piece) => piece < -2 || piece > 2)) {
      throw const FormatException(
        'A dama board must contain 64 valid squares.',
      );
    }
  }

  final String id;
  final Board board;
  final PlayerColor turn;
  final int ply;
  final String? winner;
  final String? reason;
  final DamaMove? lastMove;
  final List<MoveRecord> history;
  final Map<String, int> positions;

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
    id: json['id'] as String,
    board: _jsonInts(json['board']),
    turn: playerColorFromName(json['turn'] as String),
    ply: (json['ply'] as num?)?.toInt() ?? 0,
    winner: json['winner'] as String?,
    reason: json['reason'] as String?,
    lastMove: json['lastMove'] == null
        ? null
        : DamaMove.fromJson(_jsonMap(json['lastMove'])),
    history: (json['history'] as List? ?? [])
        .map((item) => MoveRecord.fromJson(_jsonMap(item)))
        .toList(),
    // Public online snapshots intentionally omit the private repetition map.
    positions: (json['positions'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), (value as num).toInt()),
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'board': board,
    'turn': turn.name,
    'ply': ply,
    'winner': winner,
    'reason': reason,
    'lastMove': lastMove?.toJson(),
    'history': history.map((record) => record.toJson()).toList(),
    'positions': positions,
  };

  /// Passing null explicitly clears nullable fields; omitted fields are retained.
  GameState copyWith({
    String? id,
    Board? board,
    PlayerColor? turn,
    int? ply,
    Object? winner = _unset,
    Object? reason = _unset,
    Object? lastMove = _unset,
    List<MoveRecord>? history,
    Map<String, int>? positions,
  }) => GameState(
    id: id ?? this.id,
    board: board ?? this.board,
    turn: turn ?? this.turn,
    ply: ply ?? this.ply,
    winner: identical(winner, _unset) ? this.winner : winner as String?,
    reason: identical(reason, _unset) ? this.reason : reason as String?,
    lastMove: identical(lastMove, _unset)
        ? this.lastMove
        : lastMove as DamaMove?,
    history: history ?? this.history,
    positions: positions ?? this.positions,
  );
}

class DamaRuleException implements Exception {
  const DamaRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool _inside(int row, int col) => row >= 0 && row < 8 && col >= 0 && col < 8;

String _positionKey(Board board, PlayerColor turn) =>
    '${board.join(',')}:${turn.name}';

Board initialBoard() => List<int>.generate(64, (square) {
  final row = square ~/ 8;
  return row == 1 || row == 2
      ? -1
      : row == 5 || row == 6
      ? 1
      : 0;
});

GameState newGame(String id) {
  final board = initialBoard();
  return GameState(
    id: id,
    board: board,
    turn: PlayerColor.white,
    positions: {_positionKey(board, PlayerColor.white): 1},
  );
}

typedef _Direction = (int, int);

List<_Direction> _directions(int piece) {
  final forward = piece > 0 ? -1 : 1;
  return piece.abs() == 2
      ? const [(-1, 0), (1, 0), (0, -1), (0, 1)]
      : [(forward, 0), (0, -1), (0, 1)];
}

List<DamaMove> _captureChains(
  Board board,
  int square,
  int piece, [
  _Direction? previous,
]) {
  final result = <DamaMove>[];
  final row = square ~/ 8, col = square % 8;
  for (final (dr, dc) in _directions(piece)) {
    if (previous != null && dr == -previous.$1 && dc == -previous.$2) {
      continue;
    }
    var r = row + dr, c = col + dc;
    final king = piece.abs() == 2;
    if (king) {
      while (_inside(r, c) && board[r * 8 + c] == 0) {
        r += dr;
        c += dc;
      }
    }
    if (!_inside(r, c)) continue;
    final victim = r * 8 + c;
    if (board[victim] == 0 || pieceColor(board[victim]) == pieceColor(piece)) {
      continue;
    }
    r += dr;
    c += dc;
    while (_inside(r, c) && board[r * 8 + c] == 0) {
      final landing = r * 8 + c;
      final next = List<int>.of(board);
      next[square] = 0;
      next[victim] = 0;
      next[landing] = piece;
      final rest = _captureChains(next, landing, piece, (dr, dc));
      if (rest.isEmpty) {
        result.add(DamaMove(from: square, path: [landing], captures: [victim]));
      } else {
        for (final chain in rest) {
          result.add(
            DamaMove(
              from: square,
              path: [landing, ...chain.path],
              captures: [victim, ...chain.captures],
            ),
          );
        }
      }
      if (!king) break;
      r += dr;
      c += dc;
    }
  }
  return result;
}

/// Returns complete legal turns, retaining only globally maximal capture chains.
List<DamaMove> legalMoves(Board board, PlayerColor color) {
  final captures = <DamaMove>[];
  for (var square = 0; square < 64; square++) {
    if (pieceColor(board[square]) == color) {
      captures.addAll(_captureChains(board, square, board[square]));
    }
  }
  if (captures.isNotEmpty) {
    var maximum = 0;
    for (final move in captures) {
      if (move.captures.length > maximum) maximum = move.captures.length;
    }
    return captures.where((move) => move.captures.length == maximum).toList();
  }
  final moves = <DamaMove>[];
  for (var square = 0; square < 64; square++) {
    final piece = board[square];
    if (pieceColor(piece) != color) continue;
    for (final (dr, dc) in _directions(piece)) {
      var r = square ~/ 8 + dr, c = square % 8 + dc;
      while (_inside(r, c) && board[r * 8 + c] == 0) {
        moves.add(DamaMove(from: square, path: [r * 8 + c]));
        if (piece.abs() != 2) break;
        r += dr;
        c += dc;
      }
    }
  }
  return moves;
}

Board previewMove(Board board, DamaMove move, int steps) {
  if (steps < 0 || steps > move.path.length) {
    throw RangeError.range(steps, 0, move.path.length, 'steps');
  }
  final next = List<int>.of(board);
  if (steps == 0) return next;
  final piece = next[move.from];
  next[move.from] = 0;
  for (final captured in move.captures.take(steps)) {
    next[captured] = 0;
  }
  next[move.path[steps - 1]] = piece;
  return next;
}

GameState playMove(GameState game, int from, List<int> path) {
  if (game.winner != null) {
    throw const DamaRuleException('یارییەکە کۆتایی هاتووە.');
  }
  DamaMove? move;
  for (final candidate in legalMoves(game.board, game.turn)) {
    if (candidate.from == from && _sameList(candidate.path, path)) {
      move = candidate;
      break;
    }
  }
  if (move == null) {
    throw const DamaRuleException(
      'ئەم جووڵەیە ڕێگەپێدراو نییە. ئەگەر خواردن هەبێت، زۆرترین بەرد بخۆ.',
    );
  }
  final board = previewMove(game.board, move, move.path.length);
  final destination = move.path.last;
  if (board[destination] == 1 && destination < 8) board[destination] = 2;
  if (board[destination] == -1 && destination >= 56) board[destination] = -2;
  final turn = opposite(game.turn);
  final history = [
    ...game.history,
    MoveRecord(
      color: game.turn,
      label: move.label,
      captures: move.captures.length,
    ),
  ];
  if (history.length > 100) history.removeRange(0, history.length - 100);
  final resetPositions =
      move.captures.isNotEmpty ||
      board[destination] != game.board[from] ||
      (game.board[from].abs() == 1 && from ~/ 8 != destination ~/ 8);
  final positions = resetPositions ? <String, int>{} : Map.of(game.positions);
  final key = _positionKey(board, turn);
  positions[key] = (positions[key] ?? 0) + 1;

  String? winner, reason;
  if (!board.any((piece) => pieceColor(piece) == turn)) {
    winner = game.turn.name;
    reason = 'pieces';
  } else if (legalMoves(board, turn).isEmpty) {
    winner = game.turn.name;
    reason = 'blocked';
  } else {
    final white = board.where((piece) => piece > 0).toList();
    final black = board.where((piece) => piece < 0).toList();
    if (white.length == 1 && black.length == 1) {
      winner = white.first.abs() == black.first.abs()
          ? 'draw'
          : white.first == 2
          ? 'white'
          : 'black';
      reason = 'single-piece';
    } else if ((positions[key] ?? 0) >= 3) {
      winner = 'draw';
      reason = 'repetition';
    }
  }
  return game.copyWith(
    board: board,
    turn: turn,
    ply: game.ply + 1,
    lastMove: move,
    history: history,
    positions: positions,
    winner: winner,
    reason: reason,
  );
}

int countPieces(Board board, PlayerColor color) =>
    board.where((piece) => pieceColor(piece) == color).length;
