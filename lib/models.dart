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
  });

  final String id;
  final String username;
  final String title;

  factory Costume.fromJson(Map<String, dynamic> json) => Costume(
        id: _string(json, 'id'),
        username: _string(json, 'username'),
        title: _string(json, 'title'),
      );
}

class ContestState {
  const ContestState({
    required this.title,
    required this.stage,
    required this.votesPerPerson,
    required this.costumes,
  });

  final String title;
  final ContestStage stage;
  final int votesPerPerson;
  final List<Costume> costumes;

  factory ContestState.fromJson(Map<String, dynamic> json) => ContestState(
        title: _string(json, 'title'),
        stage: ContestStage.fromJson(json['stage']),
        votesPerPerson: _integer(json, 'votes_per_person'),
        costumes: List<Costume>.unmodifiable(
          _objects(json, 'costumes').map(Costume.fromJson),
        ),
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
    required this.votes,
  });

  final int votes;

  factory CostumeResult.fromJson(Map<String, dynamic> json) => CostumeResult(
        id: _string(json, 'id'),
        username: _string(json, 'username'),
        title: _string(json, 'title'),
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
  });

  final String title;
  final ContestStage stage;
  final int votesPerPerson;
  final int registeredCount;
  final int ballotCount;
  final List<CostumeResult> results;

  factory AdminSnapshot.fromJson(Map<String, dynamic> json) => AdminSnapshot(
        title: _string(json, 'title'),
        stage: ContestStage.fromJson(json['stage']),
        votesPerPerson: _integer(json, 'votes_per_person'),
        registeredCount: _integer(json, 'registered_count'),
        ballotCount: _integer(json, 'ballot_count'),
        results: List<CostumeResult>.unmodifiable(
          _objects(json, 'results').map(CostumeResult.fromJson),
        ),
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
