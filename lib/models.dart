enum ContestStage {
  registration,
  voting,
  closed;

  String get wireValue => name;

  String get label => switch (this) {
        ContestStage.registration => 'Registration open',
        ContestStage.voting => 'Voting open',
        ContestStage.closed => 'Contest closed',
      };

  static ContestStage fromJson(Object? value) => switch (value) {
        'registration' => ContestStage.registration,
        'voting' => ContestStage.voting,
        'closed' => ContestStage.closed,
        _ => throw const FormatException('Unknown contest stage.'),
      };
}

class Costume {
  const Costume({
    required this.id,
    required this.username,
    required this.title,
    this.titleHidden = false,
  });

  final String id;
  final String username;
  final String title;
  final bool titleHidden;

  factory Costume.fromJson(Map<String, dynamic> json) => Costume(
        id: _string(json, 'id'),
        username: _string(json, 'username'),
        title: _string(json, 'title'),
        titleHidden: _optionalBool(json, 'title_hidden'),
      );
}

class ContestState {
  const ContestState({
    required this.title,
    required this.stage,
    required this.votesPerPerson,
    required this.costumes,
    this.revealAt,
    this.serverTime,
  });

  final String title;
  final ContestStage stage;
  final int votesPerPerson;
  final List<Costume> costumes;
  final DateTime? revealAt;
  final DateTime? serverTime;

  bool get revealPending =>
      revealAt != null && serverTime != null && serverTime!.isBefore(revealAt!);
  bool get hasHiddenCostumes => costumes.any((costume) => costume.titleHidden);

  factory ContestState.fromJson(Map<String, dynamic> json) => ContestState(
        title: _string(json, 'title'),
        stage: ContestStage.fromJson(json['stage']),
        votesPerPerson: _integer(json, 'votes_per_person'),
        costumes: List<Costume>.unmodifiable(
          _objects(json, 'costumes').map(Costume.fromJson),
        ),
        revealAt: _optionalDateTime(json, 'reveal_at'),
        serverTime: _optionalDateTime(json, 'server_time'),
      );
}

/// An unfamiliar valid name can be entered before registering a costume.
class ParticipantSession {
  const ParticipantSession({
    required this.participantId,
    required this.username,
    required this.costumeId,
    required this.hasVoted,
  });

  final String? participantId;
  final String? username;
  final String? costumeId;
  final bool hasVoted;

  bool get isRegistered =>
      participantId != null && username != null && costumeId != null;

  factory ParticipantSession.fromJson(Map<String, dynamic> json) {
    final hasVoted = json['has_voted'];
    if (hasVoted is! bool) {
      throw const FormatException('Invalid participant session.');
    }
    return ParticipantSession(
      participantId: _nullableString(json, 'participant_id'),
      username: _nullableString(json, 'username'),
      costumeId: _nullableString(json, 'costume_id'),
      hasVoted: hasVoted,
    );
  }
}

class CostumeResult extends Costume {
  const CostumeResult({
    required super.id,
    required super.username,
    required super.title,
    super.titleHidden = false,
    required this.votes,
  });

  final int votes;

  factory CostumeResult.fromJson(Map<String, dynamic> json) => CostumeResult(
        id: _string(json, 'id'),
        username: _string(json, 'username'),
        title: _string(json, 'title'),
        titleHidden: _optionalBool(json, 'title_hidden'),
        votes: _integer(json, 'votes'),
      );
}

class AdminSnapshot {
  const AdminSnapshot({
    required this.title,
    required this.stage,
    required this.votesPerPerson,
    required this.registeredCount,
    required this.ballotCount,
    required this.results,
    this.revealAt,
    this.serverTime,
  });

  final String title;
  final ContestStage stage;
  final int votesPerPerson;
  final int registeredCount;
  final int ballotCount;
  final List<CostumeResult> results;
  final DateTime? revealAt;
  final DateTime? serverTime;

  bool get revealPending =>
      revealAt != null && serverTime != null && serverTime!.isBefore(revealAt!);
  bool get hasHiddenCostumes => results.any((costume) => costume.titleHidden);

  factory AdminSnapshot.fromJson(Map<String, dynamic> json) => AdminSnapshot(
        title: _string(json, 'title'),
        stage: ContestStage.fromJson(json['stage']),
        votesPerPerson: _integer(json, 'votes_per_person'),
        registeredCount: _integer(json, 'registered_count'),
        ballotCount: _integer(json, 'ballot_count'),
        results: List<CostumeResult>.unmodifiable(
          _objects(json, 'results').map(CostumeResult.fromJson),
        ),
        revealAt: _optionalDateTime(json, 'reveal_at'),
        serverTime: _optionalDateTime(json, 'server_time'),
      );
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('Invalid $key.');
}

int _integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Invalid $key.');
}

bool _optionalBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return false;
  if (value is bool) return value;
  throw FormatException('Invalid $key.');
}

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $key.');
  return DateTime.parse(value).toUtc();
}

Iterable<Map<String, dynamic>> _objects(
  Map<String, dynamic> json,
  String key,
) sync* {
  final value = json[key];
  if (value is! List) throw FormatException('Invalid $key.');
  for (final item in value) {
    if (item is! Map<String, dynamic>) {
      throw FormatException('Invalid item in $key.');
    }
    yield item;
  }
}
