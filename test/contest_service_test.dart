import 'dart:async';
import 'dart:convert';

import 'package:costume_ballot/contest_service.dart';
import 'package:costume_ballot/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
      'name normalization preserves display case and collapses Unicode whitespace',
      () {
    expect(normalizeParticipantName('  Taylor   Moon  '), 'Taylor Moon');
    expect(normalizeParticipantName('\uFEFFÉva\u00A0\u2009Nagy\u3000'),
        'Éva Nagy');
  });

  group('Demo contest rules', () {
    late DemoContestService service;

    setUp(() => service = DemoContestService());
    tearDown(() => service.dispose());

    test('each voter contributes exactly three votes to other costumes',
        () async {
      final contest = await service.fetchContest();
      final alex = await service.loginParticipant('Alex');
      final morgan = await service.loginParticipant('Morgan');
      final alexChoices = contest.costumes
          .where((costume) => costume.id != alex.costumeId)
          .take(3)
          .map((costume) => costume.id)
          .toList();
      final morganChoices = contest.costumes
          .where((costume) => costume.id != morgan.costumeId)
          .take(3)
          .map((costume) => costume.id)
          .toList();

      await service.submitBallot('Alex', alexChoices);
      await service.submitBallot('Morgan', morganChoices);
      expect((await service.loginParticipant('Alex')).hasVoted, isTrue);
      expect((await service.loginParticipant('Morgan')).hasVoted, isTrue);
      expect((await service.loginParticipant('Jamie')).hasVoted, isFalse);

      // Participant access cannot fetch totals, even after submitting a ballot.
      await expectLater(service.fetchAdmin(), _failsWith('demo host'));
      await service.loginAdmin('', '');
      final dashboard = await service.fetchAdmin();
      expect(dashboard.ballotCount, 2);
      expect(dashboard.results.fold<int>(0, (sum, row) => sum + row.votes), 6);
      for (final result in dashboard.results) {
        final expected = [alexChoices, morganChoices]
            .where((choices) => choices.contains(result.id))
            .length;
        expect(result.votes, expected, reason: result.title);
      }
    });

    test('invalid ballots make no partial changes', () async {
      final contest = await service.fetchContest();
      final participant = await service.loginParticipant('Alex');
      final others = contest.costumes
          .where((costume) => costume.id != participant.costumeId)
          .map((costume) => costume.id)
          .toList();
      final rejectedBallots = <List<String>>[
        [],
        others.take(2).toList(),
        others.take(4).toList(),
        [others[0], others[0], others[1]],
        [participant.costumeId!, others[0], others[1]],
        ['missing-costume', others[0], others[1]],
      ];
      for (final ballot in rejectedBallots) {
        await expectLater(
          service.submitBallot('Alex', ballot),
          throwsA(isA<ServiceException>()),
        );
        expect((await service.loginParticipant('Alex')).hasVoted, isFalse);
      }
      await service.loginAdmin('', '');
      final dashboard = await service.fetchAdmin();
      expect(dashboard.ballotCount, 0);
      expect(dashboard.results.every((row) => row.votes == 0), isTrue);
    });

    test('concurrent submissions from the same name accept only one ballot',
        () async {
      final contest = await service.fetchContest();
      final participant = await service.loginParticipant('Alex');
      final choices = contest.costumes
          .where((costume) => costume.id != participant.costumeId)
          .take(3)
          .map((costume) => costume.id)
          .toList();
      final outcomes = await Future.wait([
        _trySubmit(service, 'Alex', choices),
        _trySubmit(service, '  aLeX  ', choices),
      ]);
      expect(outcomes.where((accepted) => accepted), hasLength(1));
      await service.loginAdmin('', '');
      final dashboard = await service.fetchAdmin();
      expect(dashboard.ballotCount, 1);
      expect(dashboard.results.fold<int>(0, (sum, row) => sum + row.votes), 3);
    });

    test('registration gives a normalized name one unique costume', () async {
      expect((await service.loginParticipant('Taylor')).isRegistered, isFalse);
      await expectLater(
        service.registerParticipant('Taylor', 'Moon Witch'),
        _failsWith('Registration'),
      );
      await service.loginAdmin('', '');
      await service.setStage(ContestStage.registration);
      await expectLater(
        service.registerParticipant(' alex ', 'Moon Witch'),
        _failsWith('already registered'),
      );
      await expectLater(
        service.registerParticipant('Taylor\nHost', 'Moon Witch'),
        _failsWith('2 to 32'),
      );
      final registered = await service.registerParticipant(
        ' Taylor   Moon ',
        ' Moon Witch ',
      );
      expect(registered.isRegistered, isTrue);
      expect(registered.username, 'Taylor Moon');
      expect(registered.hasVoted, isFalse);
      expect(
        (await service.fetchContest())
            .costumes
            .singleWhere((costume) => costume.id == registered.costumeId)
            .title,
        'Moon Witch',
      );
      await expectLater(
        service.registerParticipant(' tAYLOR    mOON ', 'Another Costume'),
        _failsWith('already registered'),
      );
      expect((await service.fetchAdmin()).registeredCount, 7);
      final samePerson = await service.loginParticipant(' TAYLOR  MOON ');
      expect(samePerson.participantId, registered.participantId);
      expect(samePerson.costumeId, registered.costumeId);
      expect(samePerson.username, 'Taylor Moon');
    });

    test('closing and resuming voting cannot reopen a spent ballot', () async {
      final participant = await service.loginParticipant('Alex');
      final choices = (await service.fetchContest())
          .costumes
          .where((costume) => costume.id != participant.costumeId)
          .take(3)
          .map((costume) => costume.id)
          .toList();
      await service.loginAdmin('', '');
      await service.setStage(ContestStage.registration);
      await expectLater(
        service.submitBallot('Alex', choices),
        _failsWith('not open'),
      );
      await service.setStage(ContestStage.voting);
      await service.submitBallot('Alex', choices);
      await service.setStage(ContestStage.closed);
      await expectLater(
        service.submitBallot('Jamie', choices),
        _failsWith('not open'),
      );
      await expectLater(
        service.setStage(ContestStage.registration),
        _failsWith('cannot reopen'),
      );
      await service.setStage(ContestStage.voting);
      await expectLater(
        service.submitBallot('Alex', choices),
        _failsWith('already submitted'),
      );
      expect((await service.fetchAdmin()).ballotCount, 1);
    });

    test(
        'case and spacing aliases cannot self-vote or replay a submitted ballot',
        () async {
      await service.loginAdmin('', '');
      await service.setStage(ContestStage.registration);
      final participant =
          await service.registerParticipant('Taylor  Moon', 'Moon Witch');
      await service.setStage(ContestStage.voting);
      final choices = (await service.fetchContest())
          .costumes
          .where((costume) => costume.id != participant.costumeId)
          .take(3)
          .map((costume) => costume.id)
          .toList();
      await expectLater(
        service.submitBallot('  tAYLOR\u00A0MOON ',
            [participant.costumeId!, ...choices.take(2)]),
        _failsWith('own costume'),
      );
      await service.submitBallot('  tAYLOR    MOON  ', choices);
      final aliases = ['Taylor Moon', 'TAYLOR   MOON', ' Taylor\u2009Moon '];
      for (final alias in aliases) {
        expect((await service.loginParticipant(alias)).hasVoted, isTrue);
        await expectLater(service.submitBallot(alias, choices),
            _failsWith('already submitted'));
      }
      final dashboard = await service.fetchAdmin();
      expect(dashboard.ballotCount, 1);
      expect(dashboard.results.fold<int>(0, (sum, row) => sum + row.votes), 3);
    });

    test('concurrent registration claims a canonical name only once', () async {
      await service.loginAdmin('', '');
      await service.setStage(ContestStage.registration);
      Future<bool> register(String name) async {
        try {
          await service.registerParticipant(name, 'Moon Witch');
          return true;
        } on ServiceException {
          return false;
        }
      }

      final outcomes = await Future.wait([
        register('Taylor  Moon'),
        register('  TAYLOR MOON  '),
      ]);
      expect(outcomes.where((accepted) => accepted), hasLength(1));
      expect((await service.fetchAdmin()).registeredCount, 7);
      final first = await service.loginParticipant('Taylor Moon');
      final second = await service.loginParticipant('taylor  moon');
      expect(first.participantId, second.participantId);
      expect(first.costumeId, second.costumeId);
    });

    test('unknown names need registration and invalid names are rejected',
        () async {
      final choices = (await service.fetchContest())
          .costumes
          .take(3)
          .map((costume) => costume.id)
          .toList();
      await expectLater(
        service.submitBallot('Taylor', choices),
        _failsWith('Register'),
      );
      expect((await service.loginParticipant('Unknown guest')).isRegistered,
          isFalse);
      for (final invalid in ['', ' a ', 'Alex\n', 'Ali\tCe', 'A' * 33]) {
        await expectLater(
            service.loginParticipant(invalid), _failsWith('2 to 32'));
      }
    });

    test('host access ends at logout', () async {
      await expectLater(service.setTitle('New party'), _failsWith('demo host'));
      await service.loginAdmin('', '');
      await service.setTitle('New party');
      expect((await service.fetchAdmin()).title, 'New party');
      await service.logoutAdmin();
      await expectLater(service.fetchAdmin(), _failsWith('demo host'));
      await expectLater(
          service.setStage(ContestStage.closed), _failsWith('demo host'));
    });

    test('demo state is isolated to its explicitly selected instance',
        () async {
      await service.loginAdmin('', '');
      await service.setTitle('Temporary preview');
      final anotherDemo = DemoContestService();
      addTearDown(anotherDemo.dispose);
      expect(service.isDemo, isTrue);
      expect(
          (await anotherDemo.fetchContest()).title, isNot('Temporary preview'));
      expect(anotherDemo.isAdminAuthenticated, isFalse);
    });
  });

  group('Live service boundary', () {
    test('invalid names are rejected before any network request', () async {
      var requests = 0;
      final service = _live((request) async {
        requests++;
        return _json(_unclaimedSession);
      });
      for (final name in [
        '',
        ' A ',
        'A' * 33,
        'Taylor\nMoon',
        'Taylor\tMoon',
        'Taylor\u0085Moon'
      ]) {
        await expectLater(
            service.loginParticipant(name), _failsWith('2 to 32'));
        await expectLater(service.registerParticipant(name, 'Moon Witch'),
            _failsWith('2 to 32'));
        await expectLater(
            service.submitBallot(name, ['a', 'b', 'c']), _failsWith('2 to 32'));
      }
      expect(requests, 0);
    });

    for (final key in ['sb_publishable_public', 'eyJlegacy-anon-jwt']) {
      test('uses the correct public authentication headers for $key', () async {
        final service = _live((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/rpc/contest_public');
          expect(jsonDecode(request.body), isEmpty);
          expect(request.headers['apikey'], key);
          expect(
            request.headers['Authorization'],
            key.startsWith('eyJ') ? 'Bearer $key' : isNull,
          );
          return _json(_publicData);
        }, key: key);
        final contest = await service.fetchContest();
        expect(contest.title, 'Costume night');
        expect(contest.stage, ContestStage.voting);
        expect(contest.votesPerPerson, 3);
        expect(service.isDemo, isFalse);
      });
    }

    test(
        'participant calls send only normalized names and intended RPC arguments',
        () async {
      final requests = <http.Request>[];
      final service = _live((request) async {
        requests.add(request);
        switch (request.url.path) {
          case '/rest/v1/rpc/participant_session':
            return _json(_unclaimedSession);
          case '/rest/v1/rpc/register_participant':
            return _json(_registeredSession);
          case '/rest/v1/rpc/submit_ballot':
            return _json({'accepted': true});
          default:
            fail('Unexpected route: ${request.url.path}');
        }
      });
      expect((await service.loginParticipant(' Taylor   Moon ')).isRegistered,
          isFalse);
      expect(
        (await service.registerParticipant(' Taylor   Moon ', ' Witch '))
            .isRegistered,
        isTrue,
      );
      await service.submitBallot(
          ' Taylor   Moon ', ['costume-a', 'costume-b', 'costume-c']);
      expect(jsonDecode(requests[0].body), {'p_username': 'Taylor Moon'});
      expect(jsonDecode(requests[1].body), {
        'p_username': 'Taylor Moon',
        'p_costume': 'Witch',
      });
      expect(jsonDecode(requests[2].body), {
        'p_username': 'Taylor Moon',
        'p_costume_ids': ['costume-a', 'costume-b', 'costume-c'],
      });
      expect(requests.every((request) => !request.url.hasQuery), isTrue);
      expect(
          requests.every((request) => request.headers['Authorization'] == null),
          isTrue);
    });

    test('host calls without a host session never reach the network', () async {
      var requestCount = 0;
      final service = _live((request) async {
        requestCount++;
        return _json(_hostData);
      });
      await expectLater(
          service.fetchAdmin(), _failsWith('Sign in as the host'));
      await expectLater(
          service.setTitle('Party'), _failsWith('Sign in as the host'));
      await expectLater(service.setStage(ContestStage.closed),
          _failsWith('Sign in as the host'));
      expect(requestCount, 0);
    });

    test('successful authentication still needs owner authorization', () async {
      final service = _live((request) async {
        if (request.url.path == '/auth/v1/token') {
          return _json(_tokens());
        }
        expect(request.url.path, '/rest/v1/rpc/admin_snapshot');
        expect(request.headers['Authorization'], 'Bearer owner-access');
        return _json(
            {'code': '42501', 'message': 'Organizer access required.'}, 403);
      });
      await expectLater(
        service.loginAdmin('visitor@example.com', 'password'),
        _failsWith('not the host'),
      );
      expect(service.isAdminAuthenticated, isFalse);
    });

    test('host token is used only on host calls and is cleared by logout',
        () async {
      final requests = <http.Request>[];
      final service = _live((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path == '/auth/v1/token') return _json(_tokens());
        if (path == '/auth/v1/logout') return http.Response('', 204);
        if (path == '/rest/v1/rpc/contest_public') return _json(_publicData);
        if (path == '/rest/v1/rpc/admin_set_stage') {
          return _json({'stage': 'closed'});
        }
        if (path == '/rest/v1/rpc/admin_set_title') {
          return _json({'title': 'New title'});
        }
        return _json(_hostData);
      });
      await service.loginAdmin(' host@example.com ', 'password');
      expect(service.isAdminAuthenticated, isTrue);
      await service.fetchContest();
      await service.setStage(ContestStage.closed);
      await service.setTitle(' New title ');
      await service.logoutAdmin();
      expect(service.isAdminAuthenticated, isFalse);
      await expectLater(
          service.fetchAdmin(), _failsWith('Sign in as the host'));

      expect(jsonDecode(requests.first.body),
          {'email': 'host@example.com', 'password': 'password'});
      for (final request
          in requests.where((r) => r.url.path.contains('/admin_'))) {
        expect(request.headers['Authorization'], 'Bearer owner-access');
      }
      expect(
        requests
            .singleWhere((r) => r.url.path.endsWith('/contest_public'))
            .headers['Authorization'],
        isNull,
      );
      expect(
          jsonDecode(requests
              .singleWhere((r) => r.url.path.endsWith('/admin_set_stage'))
              .body),
          {'p_stage': 'closed'});
      expect(
          jsonDecode(requests
              .singleWhere((r) => r.url.path.endsWith('/admin_set_title'))
              .body),
          {'p_title': 'New title'});
      expect(requests.last.headers['Authorization'], 'Bearer owner-access');
    });

    test('concurrent host requests share one token refresh', () async {
      var refreshCount = 0;
      final refreshStarted = Completer<void>();
      final refreshResponse = Completer<http.Response>();
      final service = _live((request) async {
        if (request.url.path == '/auth/v1/token') {
          if (request.url.queryParameters['grant_type'] == 'password') {
            return _json(_tokens(expiresIn: 0));
          }
          refreshCount++;
          if (refreshCount == 1) return _json(_tokens(expiresIn: 0));
          if (!refreshStarted.isCompleted) refreshStarted.complete();
          return refreshResponse.future;
        }
        return _json(_hostData);
      });
      await service.loginAdmin('host@example.com', 'password');
      final first = service.fetchAdmin();
      await refreshStarted.future;
      final second = service.fetchAdmin();
      refreshResponse.complete(_json(_tokens(accessToken: 'refreshed-access')));
      final snapshots = await Future.wait([first, second]);
      expect(snapshots, hasLength(2));
      expect(refreshCount, 2,
          reason: 'One login refresh and one shared subsequent refresh.');
      expect(service.isAdminAuthenticated, isTrue);
    });

    test('logout during a pending sign-in cannot restore host access',
        () async {
      final loginStarted = Completer<void>();
      final loginResponse = Completer<http.Response>();
      var hostRequests = 0;
      final service = _live((request) async {
        if (request.url.path == '/auth/v1/token') {
          loginStarted.complete();
          return loginResponse.future;
        }
        hostRequests++;
        return _json(_hostData);
      });
      final login = service.loginAdmin('host@example.com', 'password');
      final rejectedLogin = expectLater(login, _failsWith('canceled'));
      await loginStarted.future;
      await service.logoutAdmin();
      loginResponse.complete(_json(_tokens()));
      await rejectedLogin;
      expect(service.isAdminAuthenticated, isFalse);
      expect(hostRequests, 0);
    });

    test('logout during refresh cannot restore an expired host session',
        () async {
      final refreshStarted = Completer<void>();
      final refreshResponse = Completer<http.Response>();
      var hostRequests = 0;
      final service = _live((request) async {
        if (request.url.path == '/auth/v1/token') {
          if (request.url.queryParameters['grant_type'] == 'password') {
            return _json(_tokens(expiresIn: 0));
          }
          refreshStarted.complete();
          return refreshResponse.future;
        }
        if (request.url.path == '/auth/v1/logout') {
          return http.Response('', 204);
        }
        hostRequests++;
        return _json(_hostData);
      });
      final login = service.loginAdmin('host@example.com', 'password');
      final rejectedLogin = expectLater(login, _failsWith('expired'));
      await refreshStarted.future;
      await service.logoutAdmin();
      refreshResponse.complete(_json(_tokens(accessToken: 'too-late')));
      await rejectedLogin;
      expect(service.isAdminAuthenticated, isFalse);
      expect(hostRequests, 0);
    });

    test('only deliberate validation errors are shown verbatim', () async {
      final validation = _live((request) async => _json({
            'code': 'P0001',
            'message': 'You cannot vote for your own costume.',
          }, 400));
      await expectLater(
        validation.submitBallot('Taylor', ['a', 'b', 'c']),
        _failsWith('You cannot vote for your own costume.'),
      );
      final internalError = _live((request) async => _json({
            'code': 'XX000',
            'message': 'secret internal database details',
          }, 500));
      await expectLater(
        internalError.fetchContest(),
        throwsA(isA<ServiceException>().having(
          (error) => error.message,
          'sanitized message',
          allOf(contains('temporarily unavailable'), isNot(contains('secret'))),
        )),
      );
    });

    test('malformed data and unconfirmed ballots fail visibly', () async {
      final invalidJson = _live(
          (request) async => http.Response('<html>proxy failure</html>', 200));
      await expectLater(
          invalidJson.fetchContest(), _failsWith('unexpected response'));
      final invalidModel = _live((request) async => _json({'title': 'Party'}));
      await expectLater(
          invalidModel.fetchContest(), _failsWith('unexpected data'));
      final missingConfirmation = _live((request) async => _json({}));
      await expectLater(
        missingConfirmation.submitBallot('Taylor', ['a', 'b', 'c']),
        _failsWith('did not confirm'),
      );
    });

    test('offline or missing configuration never selects demo data', () async {
      final offline =
          _live((request) async => throw http.ClientException('unreachable'));
      await expectLater(offline.fetchContest(), _failsWith('Unable to reach'));
      expect(offline.isDemo, isFalse);
      final missingConfiguration = LiveContestService(
        supabaseUrl: '',
        supabaseAnonKey: '',
        client: MockClient((request) async =>
            fail('Unconfigured calls must not reach network.')),
      );
      addTearDown(missingConfiguration.dispose);
      await expectLater(
          missingConfiguration.fetchContest(), _failsWith('not configured'));
      expect(missingConfiguration.isDemo, isFalse);
    });
  });
}

Matcher _failsWith(String message) => throwsA(
      isA<ServiceException>()
          .having((error) => error.message, 'message', contains(message)),
    );

Future<bool> _trySubmit(
    DemoContestService service, String username, List<String> choices) async {
  try {
    await service.submitBallot(username, choices);
    return true;
  } on ServiceException {
    return false;
  }
}

LiveContestService _live(
  Future<http.Response> Function(http.Request) handler, {
  String key = 'sb_publishable_public',
}) {
  final service = LiveContestService(
    supabaseUrl: 'https://example.supabase.co/',
    supabaseAnonKey: key,
    client: MockClient(handler),
  );
  addTearDown(service.dispose);
  return service;
}

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json'});

Map<String, Object> _tokens(
        {int expiresIn = 3600, String accessToken = 'owner-access'}) =>
    {
      'access_token': accessToken,
      'refresh_token': 'owner-refresh',
      'expires_in': expiresIn,
    };

const _publicData = {
  'title': 'Costume night',
  'stage': 'voting',
  'votes_per_person': 3,
  'costumes': [
    {'id': 'costume-a', 'username': 'Taylor', 'title': 'Moon Witch'},
  ],
};

const _hostData = {
  'title': 'Costume night',
  'stage': 'voting',
  'votes_per_person': 3,
  'registered_count': 6,
  'ballot_count': 1,
  'results': [
    {
      'id': 'costume-a',
      'username': 'Taylor',
      'title': 'Moon Witch',
      'votes': 1
    },
  ],
};

const _unclaimedSession = {
  'participant_id': null,
  'username': null,
  'costume_id': null,
  'has_voted': false,
};

const _registeredSession = {
  'participant_id': 'participant-a',
  'username': 'Taylor',
  'costume_id': 'costume-a',
  'has_voted': false,
};
