import 'dart:async';

import 'package:flutter/material.dart';

import 'contest_service.dart';
import 'models.dart';

const ink = Color(0xFF142B28);
const paper = Color(0xFFF7F5EF);
const lime = Color(0xFFD6EF82);
const muted = Color(0xFF60706A);
const line = Color(0xFFDFE3D8);

String _revealLabel(DateTime date) {
  final cet = date.toUtc().add(const Duration(hours: 1));
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  final hour = cet.hour.toString().padLeft(2, '0');
  final minute = cet.minute.toString().padLeft(2, '0');
  return '${cet.day} ${months[cet.month - 1]} ${cet.year} at $hour:$minute CET';
}

Duration? _revealDelay(DateTime? revealAt, DateTime? serverTime) {
  if (revealAt == null ||
      serverTime == null ||
      !serverTime.isBefore(revealAt)) {
    return null;
  }
  // Fetch the newly public title from the server; never preload a secret title.
  return revealAt.difference(serverTime) + const Duration(milliseconds: 150);
}

void main() => runApp(const CostumeClubApp());

class CostumeClubApp extends StatelessWidget {
  const CostumeClubApp({this.service, super.key});
  final ContestService? service;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Costume Club',
        debugShowCheckedModeBanner: false,
        initialRoute: '/',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: paper,
          colorScheme: ColorScheme.fromSeed(
              seedColor: ink,
              primary: ink,
              secondary: lime,
              surface: paper,
              error: const Color(0xFFAE3B2E)),
          textTheme: ThemeData.light()
              .textTheme
              .apply(bodyColor: ink, displayColor: ink),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: line)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: line)),
          ),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
            minimumSize: const Size(48, 54),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          )),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          )),
        ),
        home: ContestPage(service: service),
      );
}

class ContestPage extends StatefulWidget {
  const ContestPage({this.service, super.key});
  final ContestService? service;
  @override
  State<ContestPage> createState() => _ContestPageState();
}

class _ContestPageState extends State<ContestPage> with WidgetsBindingObserver {
  ContestService? _service;
  ContestState? _contest;
  ParticipantSession? _participant;
  final _entryNameController = TextEditingController();
  final _nameController = TextEditingController();
  final _costumeController = TextEditingController();
  final _searchController = TextEditingController();
  final _entryForm = GlobalKey<FormState>();
  final Set<String> _selected = {};
  String _username = '';
  String? _error;
  bool _busy = false;
  bool _loading = true;
  bool _hideUntilReveal = true;
  Timer? _refreshTimer;
  Timer? _revealTimer;
  int _sessionEpoch = 0;
  int _loadEpoch = 0;

  bool get _registered => _participant?.isRegistered ?? false;
  bool get _voted => _participant?.hasVoted ?? false;
  bool get _isDemo => _service?.isDemo ?? false;
  bool get _voting =>
      _contest?.stage == ContestStage.voting &&
      !(_contest?.costumes.any((c) => c.titleHidden) ?? false);
  bool get _revealPending => _contest?.revealPending ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.service != null) {
      _service = widget.service;
    } else if (ServiceConfiguration.isDemoEnabled) {
      _service = DemoContestService();
    } else if (ServiceConfiguration.isConfigured) {
      _service = LiveContestService();
    }
    if (_service != null) {
      _load();
    } else {
      _loading = false;
    }
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_busy && _service != null) _load(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _revealTimer?.cancel();
    for (final controller in [
      _entryNameController,
      _nameController,
      _costumeController,
      _searchController
    ]) {
      controller.dispose();
    }
    _service?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _service != null) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false}) async {
    final epoch = _sessionEpoch;
    final loadEpoch = ++_loadEpoch;
    try {
      final contest = await _service!.fetchContest();
      final session =
          _registered ? await _service!.loginParticipant(_username) : null;
      if (!mounted || epoch != _sessionEpoch || loadEpoch != _loadEpoch) return;
      setState(() {
        _contest = contest;
        if (session != null) _participant = session;
        _selected.removeWhere((id) => !contest.costumes.any((c) => c.id == id));
        _loading = false;
        if (!silent) _error = null;
      });
      _revealTimer?.cancel();
      final delay = _revealDelay(contest.revealAt, contest.serverTime);
      if (delay != null) {
        _revealTimer = Timer(delay, () => _load(silent: true));
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _error = _message(e);
        });
      }
    }
  }

  String _message(Object error) => error is ServiceException
      ? error.message
      : 'Something went wrong. Please try again.';

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = _message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmIdentity(String name, String costume,
      {bool hasVoted = false,
      bool registering = false,
      bool secret = false}) async {
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text('Is this you?'),
                  scrollable: true,
                  content: SizedBox(
                      width: 340,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Text(costume,
                                style: const TextStyle(
                                    fontSize: 17, color: muted)),
                            if (secret && _contest?.revealAt != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                  'Hidden from guests until ${_revealLabel(_contest!.revealAt!)}. Your name stays visible; the host can see your costume.',
                                  style: const TextStyle(
                                      color: muted, height: 1.5)),
                            ],
                            const SizedBox(height: 20),
                            Text(
                                hasVoted
                                    ? 'A ballot has already been submitted for this name. You can see its confirmation, but cannot vote again.'
                                    : registering
                                        ? 'Confirm this is your name and costume. Use a surname or nickname if someone else shares your name.'
                                        : 'Please confirm this is your own name and costume. Each name gets one ballot with three votes.',
                                style: const TextStyle(height: 1.6)),
                          ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('That’s not me')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Yes, that’s me')),
                  ],
                )) ??
        false;
  }

  Future<void> _enterName() => _action(() async {
        final epoch = ++_sessionEpoch;
        final name = normalizeParticipantName(_entryNameController.text);
        if (name.isEmpty) {
          throw const ServiceException('Enter your name to continue.');
        }
        final participant =
            await _service!.loginParticipant(_entryNameController.text);
        if (!mounted || epoch != _sessionEpoch) return;
        if (participant.isRegistered) {
          final entries =
              _contest!.costumes.where((c) => c.id == participant.costumeId);
          if (entries.isEmpty) {
            throw const ServiceException(
                'Refresh the lineup and try your name again.');
          }
          final confirmed = await _confirmIdentity(
              participant.username!, entries.first.title,
              hasVoted: participant.hasVoted,
              secret: entries.first.titleHidden);
          if (!confirmed || !mounted || epoch != _sessionEpoch) return;
        }
        setState(() {
          _username = participant.username ?? name;
          _nameController.text = _username;
          _participant = participant;
          _selected.clear();
        });
      });

  Future<void> _register() async {
    if (!(_entryForm.currentState?.validate() ?? false)) return;
    await _action(() async {
      final name = normalizeParticipantName(_nameController.text);
      final costume = _costumeController.text.trim();
      final secret = _hideUntilReveal && _revealPending;
      final confirmed = await _confirmIdentity(name, costume,
          registering: true, secret: secret);
      if (!confirmed || !mounted) return;
      final participant = await _service!.registerParticipant(
          _nameController.text, costume,
          hideUntilReveal: secret);
      if (!mounted) return;
      setState(() {
        _participant = participant;
        _username = participant.username!;
        _costumeController.clear();
        _hideUntilReveal = true;
      });
      await _load();
    });
  }

  void _signOut() => setState(() {
        _sessionEpoch++;
        _username = '';
        _participant = null;
        _selected.clear();
        _entryNameController.clear();
        _nameController.clear();
        _costumeController.clear();
        _hideUntilReveal = true;
        _error = null;
      });

  Future<void> _reviewBallot() async {
    final choices =
        _contest!.costumes.where((c) => _selected.contains(c.id)).toList();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Your final three'),
              content: SizedBox(
                  width: 360,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Voting as ${_participant!.username}. One vote for each of these costumes:'),
                        const SizedBox(height: 16),
                        ...choices.map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(children: [
                              const Icon(Icons.check_circle_outline, size: 21),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text('${c.title}\n${c.username}',
                                      style: const TextStyle(height: 1.5)))
                            ]))),
                        const SizedBox(height: 8),
                        const Text(
                            'Once submitted, your ballot cannot be changed.',
                            style: TextStyle(color: muted, height: 1.5)),
                      ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep choosing')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Submit my 3 votes'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    await _action(() async {
      await _service!
          .submitBallot(_username, choices.map((c) => c.id).toList());
      if (!mounted) return;
      // Mark success locally before refreshing, so a failed refresh never invites a resubmit.
      setState(() {
        _participant = ParticipantSession(
            participantId: _participant!.participantId,
            username: _participant!.username,
            costumeId: _participant!.costumeId,
            hasVoted: true);
        _selected.clear();
      });
      await _load(silent: true);
    });
  }

  Future<void> _openHost() async {
    if (_service == null) return;
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => HostPage(service: _service!)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      bottomNavigationBar:
          _registered && _voting && !_voted ? _ballotDock(narrow) : null,
      body: SafeArea(
          child: Column(children: [
        if (_isDemo)
          Container(
              width: double.infinity,
              color: lime,
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
              child: const Text(
                  'PREVIEW  ·  Sample entries. No real votes are saved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        Expanded(
            child: SingleChildScrollView(
                child: Center(
                    child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 22 : 40),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _header(narrow),
              if (_error != null) _errorNotice(_error!, onRetry: () => _load()),
              if (_loading)
                const Padding(
                    padding: EdgeInsets.all(90),
                    child: Center(child: CircularProgressIndicator())),
              if (!_loading && _service == null) _setupView(),
              if (!_loading && _contest != null) ...[
                const SizedBox(height: 28),
                _hero(narrow),
                const SizedBox(height: 38),
                _rules(narrow),
                const SizedBox(height: 44),
                _lineup(narrow),
                const SizedBox(height: 42),
                const Divider(color: line),
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 25),
                    child: Text(
                        'A good costume deserves a little applause.\n${_contest!.title} · Made for a memorable night.',
                        style: const TextStyle(
                            color: muted, fontSize: 12, height: 1.8))),
              ],
            ]),
          ),
        )))),
      ])),
    );
  }

  Widget _header(bool narrow) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Row(children: [
        Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
                color: ink, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.auto_awesome, color: lime, size: 23)),
        const SizedBox(width: 10),
        const Text('COSTUME\nCLUB',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
                height: 1.3)),
        const Spacer(),
        if (_registered && !narrow)
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
        TextButton.icon(
            onPressed: _service == null ? null : _openHost,
            icon: const Icon(Icons.lock_outline, size: 16),
            label: Text(narrow ? 'Host' : 'Host sign in')),
      ]));

  Widget _hero(bool narrow) {
    final copy =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stagePill(),
      const SizedBox(height: 24),
      Text(
          _registered
              ? (_voted ? 'Good taste.\nGreat choices.' : 'Who wore\nit best?')
              : 'A little disguise.\nA lot of glory.',
          style: TextStyle(
              fontSize: narrow ? 46 : 65,
              fontWeight: FontWeight.w800,
              letterSpacing: -2.6,
              height: 1.06)),
      const SizedBox(height: 20),
      ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Text(
              _registered
                  ? (_voted
                      ? 'Your three votes are in. Now get back to the party — the host will reveal the winners.'
                      : 'Welcome, ${_participant!.username}. Find your favourites and give three brilliant costumes their moment.')
                  : 'Bring your alter ego. Meet the contenders.\nGive your three favourites a moment in the spotlight.',
              style:
                  const TextStyle(fontSize: 16, height: 1.65, color: muted))),
      const SizedBox(height: 24),
      Wrap(spacing: 18, runSpacing: 10, children: [
        _miniFact(
            Icons.people_outline, '${_contest!.costumes.length} costumes'),
        _miniFact(Icons.favorite_border, '3 votes per person'),
      ]),
    ]);
    final card = _participant == null
        ? _nameCard()
        : !_registered
            ? _registrationCard()
            : _welcomeCard();
    return narrow
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            copy,
            const SizedBox(height: 30),
            card,
          ])
        : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(flex: 6, child: copy),
            const SizedBox(width: 46),
            Expanded(flex: 4, child: card),
          ]);
  }

  Widget _stagePill() => DecoratedBox(
      decoration: BoxDecoration(
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(30)),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                    color: _voting
                        ? const Color(0xFF688733)
                        : const Color(0xFFC98C56),
                    shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(
                _contest!.stage == ContestStage.registration
                    ? 'REGISTRATION IS OPEN'
                    : _voting
                        ? 'THE BALLOT IS OPEN'
                        : 'VOTING HAS CLOSED',
                style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800)),
          ])));

  Widget _miniFact(IconData icon, String text) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17),
        const SizedBox(width: 7),
        Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))
      ]);

  Widget _nameCard() => Container(
      padding: const EdgeInsets.all(28),
      decoration:
          BoxDecoration(color: ink, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.person_outline, color: lime, size: 30),
          const Spacer(),
          Text('YOUR MOMENT',
              style: TextStyle(
                  color: lime.withValues(alpha: .8),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2))
        ]),
        const SizedBox(height: 26),
        const Text('Let’s get you in.',
            style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w700,
                letterSpacing: -.6)),
        const SizedBox(height: 10),
        const Text(
            'Enter your name to join or return.\nOne name. Three different favourites.',
            style:
                TextStyle(color: Color(0xFFB8C8BE), fontSize: 14, height: 1.6)),
        const SizedBox(height: 23),
        TextField(
            controller: _entryNameController,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _enterName(),
            decoration: const InputDecoration(
                labelText: 'Your name',
                hintText: 'e.g. Alex Smith',
                prefixIcon: Icon(Icons.person_outline, size: 19))),
        const SizedBox(height: 12),
        SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
                onPressed: _busy ? null : _enterName,
                style: FilledButton.styleFrom(
                    backgroundColor: lime, foregroundColor: ink),
                icon: _busy
                    ? _spinner()
                    : const Icon(Icons.arrow_forward, size: 19),
                iconAlignment: IconAlignment.end,
                label: const Text('Join the party'))),
        const SizedBox(height: 18),
        const Text('Already entered? Use the same name to return.',
            style:
                TextStyle(color: Color(0xFFB8C8BE), fontSize: 11, height: 1.5)),
        if (_isDemo) ...[
          const SizedBox(height: 14),
          TextButton(
              onPressed: () {
                _entryNameController.text = 'Alex';
                _enterName();
              },
              style: TextButton.styleFrom(foregroundColor: lime),
              child: const Text('Try the demo as Alex →')),
        ],
      ]));

  Widget _registrationCard() => _lightCard(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.theater_comedy_outlined, size: 32),
        const SizedBox(height: 15),
        const Text('Meet your alter ego.',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (_contest!.stage != ContestStage.registration) ...[
          const Text(
              'Registration is closed. Ask your host if you need help joining.',
              style: TextStyle(color: muted, height: 1.6)),
        ] else
          Form(
              key: _entryForm,
              child: Column(children: [
                const Text(
                    'Your name will appear in the lineup. If someone shares your name, add your surname or a nickname.',
                    style: TextStyle(color: muted, height: 1.6)),
                const SizedBox(height: 20),
                TextFormField(
                    controller: _nameController,
                    maxLength: 32,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                        labelText: 'Your name / nickname',
                        hintText: 'e.g. Alex'),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? 'Use at least 2 characters.'
                        : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _costumeController,
                    maxLength: 80,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                        labelText: 'Your costume',
                        hintText: 'e.g. The midnight magician'),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? 'Tell us your costume.'
                        : null),
                const SizedBox(height: 12),
                if (_revealPending) ...[
                  Material(
                    color: Colors.transparent,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _hideUntilReveal,
                      onChanged: _busy
                          ? null
                          : (value) =>
                              setState(() => _hideUntilReveal = value ?? false),
                      title: const Text('Keep my costume secret'),
                      subtitle: Text(
                          'Reveal on ${_revealLabel(_contest!.revealAt!)}. Your name stays visible; the host can see your costume.'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: _busy ? null : _register,
                        child: _busy
                            ? _spinner()
                            : const Text('Enter my costume'))),
              ])),
        const SizedBox(height: 8),
        TextButton(
            onPressed: _busy ? null : _signOut,
            child: const Text('Use a different name')),
      ]));

  Widget _welcomeCard() => _lightCard(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 54,
            height: 54,
            decoration:
                const BoxDecoration(color: lime, shape: BoxShape.circle),
            child: Icon(_voted ? Icons.check : Icons.theater_comedy_outlined,
                size: 27)),
        const SizedBox(height: 20),
        Text(_voted ? 'You’re all voted.' : 'You’re on the list.',
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -.7)),
        const SizedBox(height: 12),
        Text(
            _voted
                ? 'A ballot has been received for this name. You cannot submit another. Only the host can view the totals.'
                : _contest!.stage == ContestStage.registration
                    ? 'Your costume is entered. Voting will appear here when the host opens the ballot.'
                    : _contest!.stage == ContestStage.closed
                        ? 'The ballot is closed. Stay tuned for the winner announcement from your host.'
                        : 'Pick three different costumes below. Your own entry is marked and cannot be selected.',
            style: const TextStyle(color: muted, height: 1.65)),
        const SizedBox(height: 18),
        const Divider(color: line),
        Row(children: [
          Expanded(
              child: Text('Voting as ${_participant!.username}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: _busy ? null : _signOut, child: const Text('Sign out'))
        ]),
      ]));

  Widget _lightCard(Widget child) => Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(24)),
      child: child);

  Widget _rules(bool narrow) {
    final rules = [
      _rule('01', 'Make it a trio', 'Three votes. Three different costumes.'),
      _rule('02', 'Share the spotlight', 'Save your votes for someone else.'),
      _rule('03', 'Keep the suspense', 'Only your host can see the totals.'),
    ];
    return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
            border: Border.all(color: line),
            borderRadius: BorderRadius.circular(18)),
        child: narrow
            ? Column(children: [
                for (var i = 0; i < rules.length; i++) ...[
                  if (i > 0) const SizedBox(height: 22),
                  rules[i],
                ]
              ])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: rules.map((rule) => Expanded(child: rule)).toList()));
  }

  Widget _rule(String number, String title, String subtitle) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(number,
            style: const TextStyle(
                color: muted, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(width: 13),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 5),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: muted, height: 1.5))
        ])),
      ]);

  Widget _lineup(bool narrow) {
    final query = _searchController.text.trim().toLowerCase();
    final costumes = _contest!.costumes
        .where((c) => '${c.username} ${c.title}'.toLowerCase().contains(query))
        .toList();
    final eligible =
        _contest!.costumes.where((c) => c.id != _participant?.costumeId).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('THE CONTENDERS',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: muted)),
          SizedBox(height: 10),
          Text('Quite the cast.',
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.1)),
        ])),
        IconButton(
            onPressed: _busy ? null : () => _load(),
            tooltip: 'Refresh the lineup',
            icon: const Icon(Icons.refresh, size: 22)),
      ]),
      const SizedBox(height: 12),
      Text(
          _registered && _voting && !_voted
              ? 'Tap a costume to add it to your ballot.'
              : 'Big ideas. Excellent disguises. Meet tonight’s lineup.',
          style: const TextStyle(color: muted, height: 1.5)),
      if (_contest!.costumes.any((c) => c.titleHidden) &&
          _contest!.revealAt != null)
        Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
                'Secret costumes reveal automatically on ${_revealLabel(_contest!.revealAt!)}.',
                style: const TextStyle(color: muted, height: 1.5))),
      if (_registered && _voting && !_voted && eligible < 3)
        Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _errorNotice(
                'There need to be at least three other costumes before you can vote. Please check with your host.')),
      const SizedBox(height: 22),
      TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: 'Find a name or costume',
              labelText: 'Search the lineup')),
      const SizedBox(height: 22),
      if (costumes.isEmpty)
        Container(
            width: double.infinity,
            padding: const EdgeInsets.all(36),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: line),
                borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              const Icon(Icons.theater_comedy_outlined, size: 36, color: muted),
              const SizedBox(height: 14),
              Text(query.isEmpty ? 'The stage is yours.' : 'No costumes found.',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                  query.isEmpty
                      ? 'Enter your costume to start the lineup.'
                      : 'Try another name or costume.',
                  style: const TextStyle(color: muted))
            ])),
      LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 850
            ? 3
            : constraints.maxWidth >= 540
                ? 2
                : 1;
        final width = (constraints.maxWidth - (columns - 1) * 18) / columns;
        return Wrap(
            spacing: 18,
            runSpacing: 18,
            children: costumes
                .map((c) => SizedBox(width: width, child: _costumeCard(c)))
                .toList());
      }),
    ]);
  }

  Widget _costumeCard(Costume costume) {
    final own = costume.id == _participant?.costumeId;
    final selected = _selected.contains(costume.id);
    final canVote = _registered &&
        _voting &&
        !_voted &&
        !own &&
        !costume.titleHidden &&
        !_busy;
    final atLimit = !selected && _selected.length >= 3;
    final palette = [
      const Color(0xFFF2C5AE),
      const Color(0xFFDDD8EF),
      const Color(0xFFDCE5B7),
      const Color(0xFFBFD9E0),
      const Color(0xFFF0D395),
      const Color(0xFFDECBDD)
    ];
    final icons = [
      Icons.auto_awesome,
      Icons.nightlight_round,
      Icons.local_florist_outlined,
      Icons.rocket_launch_outlined,
      Icons.bolt,
      Icons.theater_comedy_outlined
    ];
    final seed =
        costume.title.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length;
    final icon = costume.titleHidden ? Icons.lock_outline : icons[seed];
    void toggle() {
      if (!canVote || atLimit) return;
      setState(() {
        selected ? _selected.remove(costume.id) : _selected.add(costume.id);
      });
    }

    return Semantics(
        button: canVote,
        selected: selected,
        label:
            '${costume.title}, ${costume.username}${own ? ', your costume, cannot select' : ''}',
        child: Material(
            color: selected ? const Color(0xFFF0F5DF) : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                    color: selected ? ink : line, width: selected ? 2 : 1)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
                onTap: canVote && !atLimit ? toggle : null,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          height: 120,
                          color: palette[seed],
                          padding: const EdgeInsets.all(18),
                          child: Stack(children: [
                            Positioned(
                                right: -12,
                                bottom: -22,
                                child: Icon(icon,
                                    color: ink.withValues(alpha: .075),
                                    size: 140)),
                            Center(child: Icon(icon, size: 50, color: ink)),
                            if (own)
                              _tag('YOUR COSTUME', Colors.white)
                            else if (selected)
                              _tag('ON YOUR BALLOT', lime),
                          ])),
                      Padding(
                          padding: const EdgeInsets.all(19),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(costume.username.toUpperCase(),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 1.4,
                                        fontWeight: FontWeight.w700,
                                        color: muted)),
                                const SizedBox(height: 8),
                                Text(costume.title,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        height: 1.2,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -.4)),
                                if (costume.titleHidden &&
                                    _contest!.revealAt != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                      'Reveals ${_revealLabel(_contest!.revealAt!)}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                          height: 1.5)),
                                ],
                                const SizedBox(height: 19),
                                Row(children: [
                                  Icon(
                                      own
                                          ? Icons.lock_outline
                                          : selected
                                              ? Icons.check_circle
                                              : Icons.add_circle_outline,
                                      size: 20,
                                      color: own || !canVote ? muted : ink),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(
                                          own
                                              ? 'Cheer for someone else'
                                              : _voted
                                                  ? 'Ballot submitted'
                                                  : !_registered
                                                      ? 'Join to vote'
                                                      : !_voting
                                                          ? 'Voting is ${_contest!.stage == ContestStage.registration ? 'not open yet' : 'closed'}'
                                                          : selected
                                                              ? 'Selected · tap to remove'
                                                              : atLimit
                                                                  ? 'Three selected already'
                                                                  : 'Add to my ballot',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: own || !canVote
                                                  ? muted
                                                  : ink))),
                                ]),
                              ])),
                    ]))));
  }

  Widget _tag(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 8, letterSpacing: .8)));

  Widget _ballotDock(bool narrow) => SafeArea(
      top: false,
      child: Container(
          decoration: const BoxDecoration(color: ink),
          padding:
              EdgeInsets.symmetric(horizontal: narrow ? 20 : 40, vertical: 14),
          child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Text('${_selected.length} of 3 selected',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                              _selected.length == 3
                                  ? 'Ready for a final look.'
                                  : 'Pick ${3 - _selected.length} more ${_selected.length == 2 ? 'costume' : 'costumes'}.',
                              style: const TextStyle(
                                  color: Color(0xFFB8C8BE), fontSize: 11))
                        ])),
                    const SizedBox(width: 12),
                    FilledButton(
                        onPressed: _selected.length == 3 && !_busy
                            ? _reviewBallot
                            : null,
                        style: FilledButton.styleFrom(
                            backgroundColor: lime,
                            foregroundColor: ink,
                            disabledBackgroundColor: const Color(0xFF344B43),
                            disabledForegroundColor: const Color(0xFFB8C8BE),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 15)),
                        child: _busy
                            ? _spinner()
                            : Text(narrow
                                ? 'Review votes →'
                                : 'Review my three votes →')),
                  ])))));

  Widget _setupView() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: _lightCard(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.auto_awesome, size: 40),
        const SizedBox(height: 20),
        const Text('The party is taking shape.',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
        const SizedBox(height: 15),
        const Text(
            'This copy is not connected to a contest yet. You can explore a preview with sample entries while the host finishes setup.',
            style: TextStyle(fontSize: 16, height: 1.7, color: muted)),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: () {
              setState(() {
                _service = DemoContestService();
                _loading = true;
              });
              _load();
            },
            child: const Text('Explore the preview')),
      ])));
}

Widget _spinner() => const SizedBox(
    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

Widget _errorNotice(String message, {VoidCallback? onRetry}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        color: const Color(0xFFF9E6DC),
        borderRadius: BorderRadius.circular(14)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: const TextStyle(height: 1.5))),
      if (onRetry != null)
        TextButton(onPressed: onRetry, child: const Text('Retry')),
    ]));

class HostPage extends StatefulWidget {
  const HostPage({required this.service, super.key});
  final ContestService service;
  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> with WidgetsBindingObserver {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _title = TextEditingController();
  AdminSnapshot? _snapshot;
  bool _busy = false;
  String? _error;
  String? _notice;
  int _hostEpoch = 0;
  int _refreshEpoch = 0;
  Timer? _refreshTimer;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.service.isAdminAuthenticated) _refresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_busy && widget.service.isAdminAuthenticated) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _revealTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.service.isAdminAuthenticated) {
      _refresh();
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ServiceException
            ? e.message
            : 'Unable to complete that request. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final epoch = _hostEpoch;
    final refreshEpoch = ++_refreshEpoch;
    try {
      final snapshot = await widget.service.fetchAdmin();
      if (mounted && epoch == _hostEpoch && refreshEpoch == _refreshEpoch) {
        setState(() {
          if (_snapshot == null || _title.text == _snapshot!.title) {
            _title.text = snapshot.title;
          }
          _snapshot = snapshot;
        });
        _revealTimer?.cancel();
        final delay = _revealDelay(snapshot.revealAt, snapshot.serverTime);
        if (delay != null) _revealTimer = Timer(delay, _refresh);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e is ServiceException ? e.message : 'Unable to refresh results.');
      }
    }
  }

  Future<void> _login() => _action(() async {
        await widget.service.loginAdmin(_email.text.trim(), _password.text);
        _password.clear();
        await _refresh();
      });

  Future<void> _changeStage(ContestStage stage) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(switch (stage) {
                  ContestStage.registration => 'Reopen registration?',
                  ContestStage.voting => 'Open the ballot?',
                  ContestStage.closed => 'Close voting?',
                }),
                content: Text(switch (stage) {
                  ContestStage.registration =>
                    'Voting will pause so more guests can enter. This is possible only before the first ballot is submitted.',
                  ContestStage.voting =>
                    'Registration will close. Entrants will each be able to submit one ballot with three votes. Make sure everyone has entered.',
                  ContestStage.closed =>
                    'No more ballots will be accepted. Your results will remain private.',
                }),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirm'))
                ]));
    if (confirmed != true || !mounted) return;
    await _action(() async {
      await widget.service.setStage(stage);
      await _refresh();
    });
  }

  Future<void> _deleteEntry(CostumeResult costume) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('Delete ${costume.username}’s entry?'),
                scrollable: true,
                content: Text('Remove “${costume.title}” from the contest? '
                    'This cannot be undone. They can register again while registration is open.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep entry')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete entry')),
                ]));
    if (confirmed != true || !mounted) return;
    await _action(() async {
      await widget.service.deleteEntry(costume.id);
      await _refresh();
      if (mounted) {
        setState(() => _notice = '${costume.username}’s entry deleted.');
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            backgroundColor: paper,
            title: const Text('The host’s room',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
            actions: [
              if (_snapshot != null)
                TextButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            _hostEpoch++;
                            _revealTimer?.cancel();
                            setState(() {
                              _snapshot = null;
                            });
                            await widget.service.logoutAdmin();
                            if (mounted) {
                              setState(() {
                                _snapshot = null;
                              });
                            }
                          },
                    child: const Text('Sign out')),
              const SizedBox(width: 12)
            ]),
        body: SafeArea(
            child: SingleChildScrollView(
                child: Center(
                    child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.service.isDemo)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: _errorNotice(
                              'Preview only. All names and votes here are sample data.')),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: _errorNotice(_error!)),
                    if (_notice != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Text(_notice!)),
                    if (_snapshot == null) _loginPanel() else ..._dashboard(),
                  ])),
        )))),
      );

  Widget _loginPanel() =>
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.lock_outline, size: 34)),
        const SizedBox(height: 20),
        const Text('Just for you.',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text(
            'Manage the party and see the totals. Individual voting choices never appear in this view.',
            style: TextStyle(color: muted, height: 1.65)),
        const SizedBox(height: 24),
        if (widget.service.isDemo)
          FilledButton(
              onPressed: _busy ? null : _login,
              child: const Text('Open the demo host view'))
        else ...[
          TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Host email')),
          const SizedBox(height: 14),
          TextField(
              controller: _password,
              obscureText: true,
              enabled: !_busy,
              onSubmitted: (_) => _login(),
              decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 18),
          FilledButton(
              onPressed: _busy ? null : _login,
              child: _busy ? _spinner() : const Text('Sign in securely')),
        ],
      ]));

  List<Widget> _dashboard() {
    final data = _snapshot!;
    final canDelete =
        data.stage == ContestStage.registration && data.ballotCount == 0;
    final waitingForReveal = data.hasHiddenCostumes;
    final maxVotes =
        data.results.fold<int>(1, (max, c) => c.votes > max ? c.votes : max);
    final results = [...data.results]
      ..sort((a, b) => b.votes.compareTo(a.votes));
    return [
      Row(children: [
        const Expanded(
            child: Text('Behind the curtain.',
                style: TextStyle(
                    fontSize: 31,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1))),
        IconButton(
            onPressed: _busy ? null : () => _action(_refresh),
            tooltip: 'Refresh results',
            icon: const Icon(Icons.refresh))
      ]),
      const SizedBox(height: 10),
      const Text('Totals for your eyes only. No voter-by-voter breakdown.',
          style: TextStyle(color: muted, height: 1.6)),
      const SizedBox(height: 25),
      Wrap(spacing: 14, runSpacing: 14, children: [
        _stat('${data.registeredCount}', 'Costumes entered'),
        _stat('${data.ballotCount}', 'Ballots received'),
        _stat('${data.ballotCount * 3}', 'Votes cast'),
      ]),
      const SizedBox(height: 24),
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Contest · ${data.stage.label}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        TextField(
            controller: _title,
            enabled: !_busy,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Contest name')),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _action(() async {
                          await widget.service.setTitle(_title.text.trim());
                          await _refresh();
                          if (mounted) {
                            setState(() => _notice = 'Contest name updated.');
                          }
                        }),
                child: const Text('Save contest name'))),
        const Divider(height: 32, color: line),
        if (data.revealAt != null) ...[
          Text('Costume reveal · ${_revealLabel(data.revealAt!)}',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5)),
          const SizedBox(height: 8),
          Text(
              data.revealPending
                  ? 'Guests can keep their costume name secret until then. You can see every costume here.'
                  : 'The reveal time has passed. All costume names are now visible to guests.',
              style: const TextStyle(color: muted, height: 1.6)),
          const SizedBox(height: 16),
        ],
        Text(
            data.stage == ContestStage.registration
                ? 'Give everyone time to enter. At least four costumes are needed so each person has three others to choose from.'
                : data.stage == ContestStage.voting
                    ? 'Voting is live. Close the ballot when everyone has had a chance to vote.'
                    : 'The ballot is closed. You can announce the results whenever you’re ready.',
            style: const TextStyle(color: muted, height: 1.6)),
        const SizedBox(height: 16),
        if (waitingForReveal) ...[
          const Text('Voting can open after the secret costumes are revealed.',
              style: TextStyle(color: muted, height: 1.5)),
          const SizedBox(height: 12),
        ],
        if (data.stage == ContestStage.registration)
          FilledButton(
              onPressed: _busy || data.registeredCount < 4 || waitingForReveal
                  ? null
                  : () => _changeStage(ContestStage.voting),
              child: const Text('Close registration & open voting')),
        if (data.stage == ContestStage.voting)
          FilledButton(
              onPressed: _busy ? null : () => _changeStage(ContestStage.closed),
              child: const Text('Close voting')),
        if (data.stage != ContestStage.registration && data.ballotCount == 0)
          TextButton(
              onPressed:
                  _busy ? null : () => _changeStage(ContestStage.registration),
              child: const Text('Reopen registration')),
        if (data.stage == ContestStage.closed)
          OutlinedButton(
              onPressed: _busy || waitingForReveal
                  ? null
                  : () => _changeStage(ContestStage.voting),
              child: const Text('Resume voting')),
      ])),
      const SizedBox(height: 24),
      _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.emoji_events_outlined, size: 25),
          SizedBox(width: 10),
          Expanded(
              child: Text('The results',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)))
        ]),
        const SizedBox(height: 12),
        const Text(
            'Equal vote totals are a tie. Each submitted ballot contributes three votes.',
            style: TextStyle(color: muted, height: 1.6)),
        const SizedBox(height: 8),
        Text(
            canDelete
                ? 'You can delete an entry below while registration is open.'
                : data.ballotCount > 0
                    ? 'Entry deletion is locked because voting has started.'
                    : 'Reopen registration to delete an entry before anyone votes.',
            style: const TextStyle(color: muted, height: 1.6)),
        const SizedBox(height: 24),
        if (results.isEmpty)
          const Text('Results will appear here once costumes are entered.'),
        ...results.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text('${c.title} · ${c.username}',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(width: 12),
                Text('${c.votes}',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800))
              ]),
              if (c.titleHidden && data.revealAt != null) ...[
                const SizedBox(height: 8),
                Text('Secret until ${_revealLabel(data.revealAt!)}',
                    style: const TextStyle(
                        color: muted, fontSize: 12, height: 1.5)),
              ],
              const SizedBox(height: 10),
              ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                      value: c.votes / maxVotes,
                      minHeight: 9,
                      backgroundColor: paper,
                      color: ink)),
              if (canDelete)
                Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        key: ValueKey('delete-${c.id}'),
                        onPressed: _busy ? null : () => _deleteEntry(c),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text('Delete ${c.username}’s entry'))),
            ]))),
      ])),
      const SizedBox(height: 40),
    ];
  }

  Widget _panel(Widget child) => Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: line)),
      child: child);
  Widget _stat(String value, String label) => SizedBox(
      width: 210,
      child: _panel(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: muted)),
      ])));
}
