import 'package:costume_ballot/contest_service.dart';
import 'package:costume_ballot/main.dart';
import 'package:costume_ballot/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester,
      {double width = 390, DemoContestService? service}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(CostumeClubApp(service: service ?? DemoContestService()));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // An identity dialog waits for the guest while the underlying button is busy.
    if (find.byType(AlertDialog).evaluate().isEmpty) {
      await tester.pumpAndSettle();
    }
  }

  Future<void> enterName(WidgetTester tester, String name) async {
    final field = find.widgetWithText(TextField, 'Your name');
    await tester.ensureVisible(field);
    await tester.enterText(field, name);
    await tapText(tester, 'Join the party');
  }

  testWidgets('confirming identity is required before voting', (tester) async {
    await open(tester);
    await enterName(tester, '  aLeX  ');
    expect(find.text('Is this you?'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Alex')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Disco Wizard')),
        findsOneWidget);
    expect(find.text('0 of 3 selected'), findsNothing);
    await tapText(tester, 'That’s not me');
    expect(find.text('0 of 3 selected'), findsNothing);
    expect(find.text('Join the party'), findsOneWidget);
    await tapText(tester, 'Join the party');
    await tapText(tester, 'Yes, that’s me');
    expect(find.text('Voting as Alex'), findsOneWidget);
    expect(find.text('0 of 3 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('phone ballot excludes own entry and confirms exactly three once',
      (tester) async {
    await open(tester);
    expect(find.textContaining('PREVIEW'), findsOneWidget);
    await tapText(tester, 'Try the demo as Alex →');
    await tapText(tester, 'Yes, that’s me');
    expect(find.text('0 of 3 selected'), findsOneWidget);
    await tapText(tester, 'Disco Wizard');
    expect(find.text('0 of 3 selected'), findsOneWidget);
    await tapText(tester, 'Cosmic Cowgirl');
    await tapText(tester, 'Garden Goblin');
    await tapText(tester, 'Midnight Moth');
    expect(find.text('3 of 3 selected'), findsOneWidget);
    await tapText(tester, 'Retro Robot');
    expect(find.text('3 of 3 selected'), findsOneWidget);
    await tester.tap(find.text('Review votes →'));
    await tester.pumpAndSettle();
    expect(find.text('Your final three'), findsOneWidget);
    expect(find.text('Once submitted, your ballot cannot be changed.'),
        findsOneWidget);
    await tester.tap(find.text('Submit my 3 votes'));
    await tester.pumpAndSettle();
    expect(find.text('You’re all voted.'), findsOneWidget);
    expect(find.text('3 of 3 selected'), findsNothing);
    expect(find.text('The results'), findsNothing);
    await tapText(tester, 'Sign out');
    await enterName(tester, '  ALEX  ');
    expect(find.textContaining('A ballot has already been submitted'),
        findsOneWidget);
    await tapText(tester, 'Yes, that’s me');
    expect(find.text('You’re all voted.'), findsOneWidget);
    expect(find.text('0 of 3 selected'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('registration requires confirming the name and costume',
      (tester) async {
    final service = DemoContestService(now: () => DateTime.utc(2026, 10, 24));
    await service.loginAdmin('', '');
    await service.setStage(ContestStage.registration);
    await service.logoutAdmin();
    await open(tester, service: service);
    await enterName(tester, 'Taylor');
    expect(find.text('Meet your alter ego.'), findsOneWidget);
    await tapText(tester, 'Keep my costume secret');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Your costume'), 'Paper Dragon');
    await tapText(tester, 'Enter my costume');
    expect(find.text('Is this you?'), findsOneWidget);
    expect((await service.fetchContest()).costumes.length, 6);
    await tapText(tester, 'That’s not me');
    expect((await service.fetchContest()).costumes.length, 6);
    await tapText(tester, 'Enter my costume');
    await tapText(tester, 'Yes, that’s me');
    expect(find.text('You’re on the list.'), findsOneWidget);
    expect(find.text('Paper Dragon'), findsOneWidget);
    expect(find.text('0 of 3 selected'), findsNothing);
    expect((await service.fetchContest()).costumes.length, 7);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a name claimed during registration is never overwritten',
      (tester) async {
    final service = DemoContestService();
    await service.loginAdmin('', '');
    await service.setStage(ContestStage.registration);
    await service.logoutAdmin();
    await open(tester, service: service);
    await enterName(tester, 'Taylor');
    await service.registerParticipant('TAYLOR', 'Original Dragon');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Your costume'), 'New Dragon');
    await tapText(tester, 'Enter my costume');
    await tapText(tester, 'Yes, that’s me');
    expect(find.text('Meet your alter ego.'), findsOneWidget);
    final entries = (await service.fetchContest()).costumes;
    expect(
        entries.where((c) => c.username.toLowerCase() == 'taylor').length, 1);
    expect(entries.any((c) => c.title == 'Original Dragon'), isTrue);
    expect(entries.any((c) => c.title == 'New Dragon'), isFalse);
    expect(find.text('Voting as TAYLOR'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new costume is secret by default without hiding the guest name',
      (tester) async {
    final service = DemoContestService(now: () => DateTime.utc(2026, 10, 24));
    await service.loginAdmin('', '');
    await service.setStage(ContestStage.registration);
    await service.logoutAdmin();
    await open(tester, width: 320, service: service);
    await enterName(tester, 'Taylor');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Your costume'), 'Paper Dragon');
    await tapText(tester, 'Enter my costume');
    expect(find.textContaining('31 October 2026 at 20:00 CET'), findsWidgets);
    await tapText(tester, 'Yes, that’s me');
    final entry = (await service.fetchContest()).costumes.last;
    expect(entry.username, 'Taylor');
    expect(entry.titleHidden, isTrue);
    expect(find.text('Paper Dragon'), findsNothing);
    expect(find.text('Secret costume'), findsOneWidget);
    await tapText(tester, 'Sign out');
    await enterName(tester, 'Taylor');
    expect(find.text('Paper Dragon'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Secret costume')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('costume reveals from server time without a manual refresh',
      (tester) async {
    var now = DateTime.utc(2026, 10, 31, 18, 59, 55);
    final service = DemoContestService(now: () => now);
    await service.loginAdmin('', '');
    await service.setStage(ContestStage.registration);
    await service.registerParticipant('Taylor', 'Paper Dragon',
        hideUntilReveal: true);
    await service.logoutAdmin();
    await open(tester, service: service);
    expect(find.text('Paper Dragon'), findsNothing);
    expect(find.text('Secret costume'), findsOneWidget);
    now = DateTime.utc(2026, 10, 31, 19);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Paper Dragon'), findsOneWidget);
    expect(find.text('Secret costume'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('host sees secrets and confirms deletion during registration',
      (tester) async {
    final service = DemoContestService(now: () => DateTime.utc(2026, 10, 24));
    await service.loginAdmin('', '');
    await service.setStage(ContestStage.registration);
    await service.registerParticipant('Taylor', 'Paper Dragon',
        hideUntilReveal: true);
    await open(tester, width: 320, service: service);
    await tapText(tester, 'Host');
    expect(find.text('Paper Dragon · Taylor'), findsOneWidget);
    final openVoting = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Close registration & open voting'));
    expect(openVoting.onPressed, isNull);
    await tapText(tester, 'Delete Taylor’s entry');
    await tapText(tester, 'Keep entry');
    expect((await service.fetchContest()).costumes.length, 7);
    await tapText(tester, 'Delete Taylor’s entry');
    await tapText(tester, 'Delete entry');
    expect((await service.fetchContest()).costumes.length, 6);
    expect(find.text('Taylor’s entry deleted.'), findsOneWidget);
    expect(find.text('Paper Dragon · Taylor'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('host cannot delete entries after a ballot has been received',
      (tester) async {
    final service = DemoContestService();
    final entries = (await service.fetchContest()).costumes;
    await service.submitBallot(
        'Alex', entries.skip(1).take(3).map((c) => c.id).toList());
    await service.loginAdmin('', '');
    await open(tester, service: service);
    await tapText(tester, 'Host');
    expect(find.textContaining('Delete Alex'), findsNothing);
    expect(find.text('Entry deletion is locked because voting has started.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets(
        'name form and confirmation fit a ${width.toInt()} pixel viewport',
        (tester) async {
      await open(tester, width: width);
      expect(find.text('A little disguise.\nA lot of glory.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Try the demo as Alex →');
      expect(find.text('Is this you?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Yes, that’s me');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
