import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ServiceConfiguration {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const isDemoEnabled =
      bool.fromEnvironment('DEMO_MODE', defaultValue: false);

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;
}

class ServiceException implements Exception {
  const ServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Keeps a guest's preferred capitalization while giving repeated whitespace
/// one consistent display form. Identity lookup additionally ignores case.
String normalizeParticipantName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ');

String _validatedParticipantName(String name) {
  final normalized = normalizeParticipantName(name);
  if (_hasControlCharacters(name) ||
      normalized.runes.length < 2 ||
      normalized.runes.length > 32) {
    throw const ServiceException('Use a name of 2 to 32 characters.');
  }
  return normalized;
}

bool _hasControlCharacters(String value) =>
    value.runes.any((rune) => rune < 32 || (rune >= 127 && rune <= 159));

abstract class ContestService {
  bool get isDemo;
  bool get isAdminAuthenticated;

  Future<ContestState> fetchContest();
  Future<ParticipantSession> loginParticipant(String username);
  Future<ParticipantSession> registerParticipant(
    String username,
    String costume, {
    bool hideUntilReveal = false,
  });
  Future<void> submitBallot(String username, List<String> ids);
  Future<void> loginAdmin(String email, String password);
  Future<void> logoutAdmin();
  Future<AdminSnapshot> fetchAdmin();
  Future<void> deleteEntry(String costumeId);
  Future<void> setStage(ContestStage stage);
  Future<void> setTitle(String title);
  void dispose();
}

/// Calls only the deliberately exposed database functions. No table reads,
/// service-role keys, or participant access to host totals are needed.
class LiveContestService implements ContestService {
  LiveContestService({
    http.Client? client,
    String? supabaseUrl,
    String? supabaseAnonKey,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _baseUrl = (supabaseUrl ?? ServiceConfiguration.supabaseUrl)
            .trim()
            .replaceFirst(RegExp(r'/+$'), ''),
        _anonKey =
            (supabaseAnonKey ?? ServiceConfiguration.supabaseAnonKey).trim();

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final String _anonKey;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  Future<void>? _pendingRefresh;
  int _authGeneration = 0;
  static const _timeout = Duration(seconds: 18);

  @override
  bool get isDemo => false;

  @override
  bool get isAdminAuthenticated => _accessToken != null;

  @override
  Future<ContestState> fetchContest() async =>
      _parse(() async => ContestState.fromJson(await _rpc('contest_public')));

  @override
  Future<ParticipantSession> loginParticipant(String username) async => _parse(
        () async => ParticipantSession.fromJson(
          await _rpc('participant_session',
              {'p_username': _validatedParticipantName(username)}),
        ),
      );

  @override
  Future<ParticipantSession> registerParticipant(
    String username,
    String costume, {
    bool hideUntilReveal = false,
  }) async =>
      _parse(
        () async => ParticipantSession.fromJson(
          await _rpc('register_participant', {
            'p_username': _validatedParticipantName(username),
            'p_costume': costume.trim(),
            'p_hide_until_reveal': hideUntilReveal,
          }),
        ),
      );

  @override
  Future<void> submitBallot(String username, List<String> ids) async {
    final response = await _rpc('submit_ballot', {
      'p_username': _validatedParticipantName(username),
      'p_costume_ids': ids,
    });
    if (response['accepted'] != true) {
      throw const ServiceException(
        'The server did not confirm your ballot. Sign in again to check its status.',
      );
    }
  }

  @override
  Future<void> loginAdmin(String email, String password) async {
    _clearAdmin();
    final generation = _authGeneration;
    final response = await _request(
      '/auth/v1/token?grant_type=password',
      {'email': email.trim(), 'password': password},
      isAuth: true,
    );
    if (generation != _authGeneration) {
      throw const ServiceException(
          'Host sign-in was canceled. Please sign in again.');
    }
    _setTokens(response);
    try {
      // An ordinary authenticated account is not necessarily the contest host.
      await fetchAdmin();
    } catch (_) {
      if (generation == _authGeneration) _clearAdmin();
      rethrow;
    }
  }

  @override
  Future<void> logoutAdmin() async {
    final token = _accessToken;
    _clearAdmin();
    if (token == null) return;
    try {
      await _request('/auth/v1/logout', {}, bearer: token, isAuth: true);
    } on ServiceException {
      // Local credentials are already cleared even if the network is offline.
    }
  }

  @override
  Future<AdminSnapshot> fetchAdmin() async => _parse(
        () async => AdminSnapshot.fromJson(
          await _rpc('admin_snapshot', const {}, true),
        ),
      );

  @override
  Future<void> deleteEntry(String costumeId) async {
    final response =
        await _rpc('admin_delete_entry', {'p_costume_id': costumeId}, true);
    if (response['deleted'] != true) {
      throw const ServiceException(
          'The server did not confirm the deletion. Refresh the host view before trying again.');
    }
  }

  @override
  Future<void> setStage(ContestStage stage) async {
    await _rpc('admin_set_stage', {'p_stage': stage.wireValue}, true);
  }

  @override
  Future<void> setTitle(String title) async {
    await _rpc('admin_set_title', {'p_title': title.trim()}, true);
  }

  Future<Map<String, dynamic>> _rpc(
    String name, [
    Map<String, dynamic> arguments = const {},
    bool admin = false,
  ]) async {
    if (admin) await _ensureAdminSession();
    return _request(
      '/rest/v1/rpc/$name',
      arguments,
      bearer: admin ? _accessToken : null,
    );
  }

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, dynamic> payload, {
    String? bearer,
    bool isAuth = false,
  }) async {
    final base = Uri.tryParse(_baseUrl);
    if (base == null ||
        base.host.isEmpty ||
        !['https', 'http'].contains(base.scheme) ||
        _anonKey.isEmpty) {
      throw const ServiceException(
        'The live contest is not configured yet. Add the Supabase settings before deployment.',
      );
    }
    final headers = <String, String>{
      'apikey': _anonKey,
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (bearer != null)
        'Authorization': 'Bearer $bearer'
      else if (_anonKey.startsWith('eyJ'))
        // Legacy anon keys are JWTs. New publishable keys are not bearer tokens.
        'Authorization': 'Bearer $_anonKey',
    };
    try {
      final response = await _client
          .post(Uri.parse('$_baseUrl$path'),
              headers: headers, body: jsonEncode(payload))
          .timeout(_timeout);
      Map<String, dynamic>? decoded;
      if (response.body.isNotEmpty) {
        try {
          final value = jsonDecode(response.body);
          if (value is Map<String, dynamic>) decoded = value;
        } on FormatException {
          // Never display an HTML proxy error, raw SQL detail, or response body.
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _responseError(response.statusCode, decoded, isAuth: isAuth);
      }
      if (response.statusCode == 204 || response.body.isEmpty) return {};
      if (decoded == null) {
        throw const ServiceException(
          'The contest server returned an unexpected response. Please try again.',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const ServiceException(
        'The request timed out. Check your connection. If you submitted a ballot, sign in again to check whether it was saved.',
      );
    } on http.ClientException {
      throw const ServiceException(
        'Unable to reach the contest. Check your connection and try again.',
      );
    } on FormatException {
      throw const ServiceException(
          'The contest connection is not configured correctly.');
    }
  }

  ServiceException _responseError(
    int status,
    Map<String, dynamic>? body, {
    required bool isAuth,
  }) {
    if (isAuth) {
      if (status == 400 || status == 401 || status == 403) {
        return const ServiceException(
          'Host sign-in failed. Check your email and password, then try again.',
        );
      }
    }
    // P0001 is used by the database's intentional, user-facing validations.
    final message = body?['message'];
    if (body?['code'] == 'P0001' &&
        message is String &&
        message.isNotEmpty &&
        message.length <= 240 &&
        !message.contains(RegExp(r'[\r\n<>]'))) {
      return ServiceException(message);
    }
    if (status == 401 || status == 403) {
      return const ServiceException(
        'Your host session has expired or this account is not the host. Sign in again.',
      );
    }
    if (status == 429) {
      return const ServiceException(
          'Too many requests. Wait a moment and try again.');
    }
    if (status == 404 || body?['code'] == 'PGRST202') {
      return const ServiceException(
        'The contest database is not ready. Complete the database setup and try again.',
      );
    }
    if (status >= 500) {
      return const ServiceException(
        'The contest server is temporarily unavailable. Please try again shortly.',
      );
    }
    return const ServiceException(
      'The request could not be completed. Refresh the contest and try again.',
    );
  }

  Future<T> _parse<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on FormatException {
      throw const ServiceException(
        'The contest server returned unexpected data. Check that the latest database setup is installed.',
      );
    }
  }

  void _setTokens(Map<String, dynamic> body) {
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    if (access is! String || access.isEmpty || refresh is! String) {
      throw const ServiceException(
          'Host sign-in could not be completed. Please try again.');
    }
    _accessToken = access;
    _refreshToken = refresh;
    final seconds = body['expires_in'];
    _expiresAt = DateTime.now().toUtc().add(
          Duration(seconds: seconds is int ? seconds : 3600),
        );
  }

  Future<void> _ensureAdminSession() async {
    if (_accessToken == null) {
      throw const ServiceException(
          'Sign in as the host to use these controls.');
    }
    if (_expiresAt != null &&
        DateTime.now().toUtc().isBefore(
              _expiresAt!.subtract(const Duration(seconds: 30)),
            )) {
      return;
    }
    final pending = _pendingRefresh;
    if (pending != null) return pending;
    final refresh = _refreshAdmin();
    _pendingRefresh = refresh;
    try {
      await refresh;
    } finally {
      _pendingRefresh = null;
    }
  }

  Future<void> _refreshAdmin() async {
    final generation = _authGeneration;
    final refresh = _refreshToken;
    if (refresh == null) {
      _clearAdmin();
      throw const ServiceException(
          'Your host session has expired. Sign in again.');
    }
    try {
      final response = await _request(
        '/auth/v1/token?grant_type=refresh_token',
        {'refresh_token': refresh},
        isAuth: true,
      );
      if (generation != _authGeneration) {
        throw const ServiceException(
            'Your host session has ended. Sign in again.');
      }
      _setTokens(response);
    } on ServiceException {
      if (generation == _authGeneration) _clearAdmin();
      throw const ServiceException(
          'Your host session has expired. Sign in again.');
    }
  }

  void _clearAdmin() {
    _authGeneration++;
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
  }

  @override
  void dispose() {
    _clearAdmin();
    if (_ownsClient) _client.close();
  }
}

/// Explicitly selected preview data. It never contacts the live database and
/// resets when this instance is discarded or the page is reloaded.
class DemoContestService implements ContestService {
  DemoContestService({DateTime Function()? now, DateTime? revealAt})
      : _now = now ?? DateTime.now,
        _revealAt = (revealAt ?? DateTime.utc(2026, 10, 31, 19)).toUtc() {
    const names = ['Alex', 'Morgan', 'Jamie', 'Casey', 'Riley', 'Sam'];
    const titles = [
      'Disco Wizard',
      'Cosmic Cowgirl',
      'Garden Goblin',
      'Midnight Moth',
      'Retro Robot',
      'Vampire on Vacation',
    ];
    for (var i = 0; i < names.length; i++) {
      final id = 'demo-costume-${i + 1}';
      _costumes.add(Costume(id: id, username: names[i], title: titles[i]));
      _participants[names[i].toLowerCase()] = ParticipantSession(
        participantId: 'demo-participant-${i + 1}',
        username: names[i],
        costumeId: id,
        hasVoted: false,
      );
    }
    _nextParticipantNumber = names.length + 1;
  }

  static const _unregistered = ParticipantSession(
    participantId: null,
    username: null,
    costumeId: null,
    hasVoted: false,
  );
  String _title = 'The Costume Club';
  ContestStage _stage = ContestStage.voting;
  final List<Costume> _costumes = [];
  final Map<String, ParticipantSession> _participants = {};
  final Map<String, int> _voteTotals = {};
  final Set<String> _hiddenUntilRevealIds = {};
  final DateTime Function() _now;
  final DateTime _revealAt;
  int _nextParticipantNumber = 1;
  bool _adminAuthenticated = false;
  int _ballotCount = 0;
  static const _votesPerPerson = 3;

  @override
  bool get isDemo => true;

  @override
  bool get isAdminAuthenticated => _adminAuthenticated;

  @override
  Future<ContestState> fetchContest() async {
    final serverTime = _now().toUtc();
    return ContestState(
      title: _title,
      stage: _stage,
      votesPerPerson: _votesPerPerson,
      costumes: List<Costume>.unmodifiable(_costumes.map((costume) {
        final hidden = _isTitleHidden(costume.id, serverTime);
        return Costume(
            id: costume.id,
            username: costume.username,
            title: hidden ? 'Secret costume' : costume.title,
            titleHidden: hidden);
      })),
      revealAt: _revealAt,
      serverTime: serverTime,
    );
  }

  bool _isTitleHidden(String id, DateTime serverTime) =>
      _hiddenUntilRevealIds.contains(id) && serverTime.isBefore(_revealAt);

  void _requireRevealedCostumes({bool submitting = false}) {
    if (_hiddenUntilRevealIds.isNotEmpty &&
        _now().toUtc().isBefore(_revealAt)) {
      throw ServiceException(submitting
          ? 'Voting is paused until secret costumes are revealed.'
          : 'Voting cannot open while secret costumes are hidden.');
    }
  }

  ParticipantSession _session(String username) =>
      _participants[_validatedParticipantName(username).toLowerCase()] ??
      _unregistered;

  @override
  Future<ParticipantSession> loginParticipant(String username) async =>
      _session(username);

  @override
  Future<ParticipantSession> registerParticipant(
    String username,
    String costume, {
    bool hideUntilReveal = false,
  }) async {
    final name = _validatedParticipantName(username);
    final session = _session(name);
    if (session.isRegistered) {
      throw const ServiceException(
          'That name is already registered. Confirm it is yours to continue.');
    }
    if (_stage != ContestStage.registration) {
      throw const ServiceException('Registration is not open.');
    }
    final title = costume.trim();
    if (title.runes.length < 2 ||
        title.runes.length > 80 ||
        _hasControlCharacters(title)) {
      throw const ServiceException('Use a costume name of 2 to 80 characters.');
    }
    final number = _nextParticipantNumber++;
    final id = 'demo-costume-$number';
    _costumes.add(Costume(id: id, username: name, title: title));
    if (hideUntilReveal) _hiddenUntilRevealIds.add(id);
    final registered = ParticipantSession(
      participantId: 'demo-participant-$number',
      username: name,
      costumeId: id,
      hasVoted: false,
    );
    _participants[name.toLowerCase()] = registered;
    return registered;
  }

  @override
  Future<void> submitBallot(String username, List<String> ids) async {
    final name = _validatedParticipantName(username);
    final session = _session(name);
    if (_stage != ContestStage.voting) {
      throw const ServiceException('Voting is not open.');
    }
    _requireRevealedCostumes(submitting: true);
    if (!session.isRegistered) {
      throw const ServiceException(
          'Register your name and costume before voting.');
    }
    if (session.hasVoted) {
      throw const ServiceException('You have already submitted your ballot.');
    }
    if (ids.length != _votesPerPerson ||
        ids.toSet().length != _votesPerPerson) {
      throw const ServiceException('Choose exactly three different costumes.');
    }
    if (ids.contains(session.costumeId)) {
      throw const ServiceException('You cannot vote for your own costume.');
    }
    if (ids.any((id) => !_costumes.any((costume) => costume.id == id))) {
      throw const ServiceException(
          'One of those costumes is unavailable. Refresh and try again.');
    }
    for (final id in ids) {
      _voteTotals[id] = (_voteTotals[id] ?? 0) + 1;
    }
    _ballotCount++;
    _participants[name.toLowerCase()] = ParticipantSession(
      participantId: session.participantId,
      username: session.username,
      costumeId: session.costumeId,
      hasVoted: true,
    );
  }

  @override
  Future<void> loginAdmin(String email, String password) async {
    // Demo controls intentionally need no real credentials. This bypass exists
    // only in this isolated, explicitly selected in-memory implementation.
    _adminAuthenticated = true;
  }

  @override
  Future<void> logoutAdmin() async {
    _adminAuthenticated = false;
  }

  void _requireAdmin() {
    if (!_adminAuthenticated) {
      throw const ServiceException(
          'Open the demo host view to use these controls.');
    }
  }

  @override
  Future<AdminSnapshot> fetchAdmin() async {
    _requireAdmin();
    final serverTime = _now().toUtc();
    final results = _costumes
        .map((entry) => CostumeResult(
              id: entry.id,
              username: entry.username,
              title: entry.title,
              titleHidden: _isTitleHidden(entry.id, serverTime),
              votes: _voteTotals[entry.id] ?? 0,
            ))
        .toList()
      ..sort((a, b) {
        final byVotes = b.votes.compareTo(a.votes);
        return byVotes != 0 ? byVotes : a.username.compareTo(b.username);
      });
    return AdminSnapshot(
      title: _title,
      stage: _stage,
      votesPerPerson: _votesPerPerson,
      registeredCount: _costumes.length,
      ballotCount: _ballotCount,
      results: List<CostumeResult>.unmodifiable(results),
      revealAt: _revealAt,
      serverTime: serverTime,
    );
  }

  @override
  Future<void> deleteEntry(String costumeId) async {
    _requireAdmin();
    if (_stage != ContestStage.registration) {
      throw const ServiceException(
          'Entries can only be deleted while registration is open.');
    }
    if (_ballotCount != 0) {
      throw const ServiceException(
          'Entries cannot be deleted after a ballot has been submitted.');
    }
    final index = _costumes.indexWhere((costume) => costume.id == costumeId);
    if (index < 0) throw const ServiceException('That entry no longer exists.');
    final deleted = _costumes.removeAt(index);
    _participants
        .remove(normalizeParticipantName(deleted.username).toLowerCase());
    _hiddenUntilRevealIds.remove(deleted.id);
    _voteTotals.remove(deleted.id);
  }

  @override
  Future<void> setStage(ContestStage stage) async {
    _requireAdmin();
    if (stage == ContestStage.registration && _ballotCount > 0) {
      throw const ServiceException(
          'Registration cannot reopen after a ballot is submitted.');
    }
    if (stage == ContestStage.voting &&
        _costumes.length < _votesPerPerson + 1) {
      throw const ServiceException(
          'At least four costumes are needed to open voting.');
    }
    if (stage == ContestStage.voting) _requireRevealedCostumes();
    _stage = stage;
  }

  @override
  Future<void> setTitle(String title) async {
    _requireAdmin();
    final value = title.trim();
    if (value.isEmpty ||
        value.runes.length > 80 ||
        _hasControlCharacters(value)) {
      throw const ServiceException('Use an event title of 1 to 80 characters.');
    }
    _title = value;
  }

  @override
  void dispose() {
    _adminAuthenticated = false;
  }
}
