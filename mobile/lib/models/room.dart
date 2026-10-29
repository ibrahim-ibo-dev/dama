import '../game/game.dart';

Map<String, dynamic> jsonObject(dynamic value) {
  if (value is! Map) throw const FormatException('Expected an object.');
  return value.cast<String, dynamic>();
}

DateTime _timestamp(dynamic value) => DateTime.fromMillisecondsSinceEpoch(
  (value as num?)?.toInt() ?? 0,
  isUtc: true,
);

class ServerStatus {
  const ServerStatus({required this.mode, required this.passwordRequired});
  final String mode;
  final bool passwordRequired;
  bool get onlineAvailable => mode == 'redis' || mode == 'local';
  factory ServerStatus.fromJson(Map<String, dynamic> json) => ServerStatus(
    mode: json['mode'] as String,
    passwordRequired: json['passwordRequired'] == true,
  );
}

class RoomMember {
  const RoomMember({
    required this.id,
    required this.name,
    required this.role,
    required this.lastSeen,
  });
  final String id;
  final String name;
  final String role;
  final DateTime lastSeen;
  PlayerColor? get color => switch (role) {
    'white' => PlayerColor.white,
    'black' => PlayerColor.black,
    _ => null,
  };
  bool isOnline({DateTime? now}) =>
      lastSeen.millisecondsSinceEpoch > 0 &&
      (now ?? DateTime.now()).difference(lastSeen) <
          const Duration(seconds: 50);
  factory RoomMember.fromJson(Map<String, dynamic> json) {
    final role = json['role'] as String;
    if (!const ['white', 'black', 'spectator'].contains(role)) {
      throw const FormatException('Invalid room role.');
    }
    return RoomMember(
      id: json['id'] as String,
      name: json['name'] as String,
      role: role,
      lastSeen: _timestamp(json['lastSeen']),
    );
  }
}

class RoomMessage {
  const RoomMessage({
    required this.id,
    required this.memberId,
    required this.name,
    required this.text,
    required this.createdAt,
  });
  final String id;
  final String memberId;
  final String name;
  final String text;
  final DateTime createdAt;
  factory RoomMessage.fromJson(Map<String, dynamic> json) => RoomMessage(
    id: json['id'] as String,
    memberId: json['memberId'] as String,
    name: json['name'] as String,
    text: json['text'] as String,
    createdAt: _timestamp(json['createdAt']),
  );
}

class MatchResult {
  const MatchResult({
    required this.gameId,
    required this.winnerId,
    required this.reason,
    required this.finishedAt,
  });
  final String gameId;
  final String? winnerId;
  final String? reason;
  final DateTime finishedAt;
  factory MatchResult.fromJson(Map<String, dynamic> json) => MatchResult(
    gameId: json['gameId'] as String,
    winnerId: json['winnerId'] as String?,
    reason: json['reason'] as String?,
    finishedAt: _timestamp(json['finishedAt']),
  );
}

class RoomSnapshot {
  RoomSnapshot({
    required this.code,
    required this.createdAt,
    required this.updatedAt,
    required this.revision,
    required List<RoomMember> members,
    required this.game,
    required this.started,
    required this.drawOffer,
    required List<String> rematchVotes,
    required this.me,
    List<RoomMessage> messages = const [],
    List<MatchResult> results = const [],
  }) : members = List.unmodifiable(members),
       rematchVotes = List.unmodifiable(rematchVotes),
       messages = List.unmodifiable(messages),
       results = List.unmodifiable(results);
  final String code;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final List<RoomMember> members;
  final GameState game;
  final bool started;
  final String? drawOffer;
  final List<String> rematchVotes;
  final String me;
  final List<RoomMessage> messages;
  final List<MatchResult> results;
  RoomMember? get self =>
      members.where((member) => member.id == me).firstOrNull;
  List<RoomMember> get players =>
      members.where((member) => member.color != null).toList(growable: false);
  List<RoomMember> get spectators => members
      .where((member) => member.role == 'spectator')
      .toList(growable: false);
  int winsFor(String memberId) =>
      results.where((result) => result.winnerId == memberId).length;
  int get draws => results.where((result) => result.winnerId == null).length;
  factory RoomSnapshot.fromJson(Map<String, dynamic> json) {
    final snapshot = RoomSnapshot(
      code: json['code'] as String,
      createdAt: _timestamp(json['createdAt']),
      updatedAt: _timestamp(json['updatedAt']),
      revision: (json['revision'] as num).toInt(),
      members: (json['members'] as List)
          .map((item) => RoomMember.fromJson(jsonObject(item)))
          .toList(),
      game: GameState.fromJson(jsonObject(json['game'])),
      started: json['started'] == true,
      drawOffer: json['drawOffer'] as String?,
      rematchVotes: (json['rematchVotes'] as List? ?? []).cast<String>(),
      me: json['me'] as String,
      messages: (json['messages'] as List? ?? [])
          .map((item) => RoomMessage.fromJson(jsonObject(item)))
          .toList(),
      results: (json['results'] as List? ?? [])
          .map((item) => MatchResult.fromJson(jsonObject(item)))
          .toList(),
    );
    if (snapshot.self == null) {
      throw const FormatException('The room does not contain this player.');
    }
    return snapshot;
  }
}
