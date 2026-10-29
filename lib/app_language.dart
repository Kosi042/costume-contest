import 'package:flutter/material.dart';

enum AppLanguage { german, english }

/// German flavour copy is intentionally left for the event host to write.
/// Replace any null below with your German wording. Keep {name} and {contest}
/// placeholders where present. Until then, that item uses englishFlavourCopy.
const germanFlavourCopy = <String, String?>{
  'heroNew': null,
  'heroReady': null,
  'heroVoted': null,
  'heroIntroduction': null,
  'footer': null,
  'joinEyebrow': null,
  'joinHeading': null,
  'registrationHeading': null,
  'ruleThreeHeading': null,
  'ruleOthersHeading': null,
  'rulePrivateHeading': null,
  'lineupHeading': null,
  'lineupIntroduction': null,
  'emptyLineupHeading': null,
  'setupHeading': null,
  'hostHeading': null,
  'hostLoginHeading': null,
  'hostDashboardHeading': null,
};

const englishFlavourCopy = <String, String>{
  'heroNew': 'A little disguise.\nA lot of glory.',
  'heroReady': 'Who wore\nit best?',
  'heroVoted': 'Good taste.\nGreat choices.',
  'heroIntroduction':
      'Bring your alter ego. Meet the contenders.\nGive your three favourites a moment in the spotlight.',
  'footer':
      'A good costume deserves a little applause.\n{contest} · Made for a memorable night.',
  'joinEyebrow': 'YOUR MOMENT',
  'joinHeading': 'Let’s get you in.',
  'registrationHeading': 'Meet your alter ego.',
  'ruleThreeHeading': 'Make it a trio',
  'ruleOthersHeading': 'Share the spotlight',
  'rulePrivateHeading': 'Keep the suspense',
  'lineupHeading': 'Quite the cast.',
  'lineupIntroduction':
      'Big ideas. Excellent disguises. Meet tonight’s lineup.',
  'emptyLineupHeading': 'The stage is yours.',
  'setupHeading': 'The party is taking shape.',
  'hostHeading': 'The host’s room',
  'hostLoginHeading': 'Just for you.',
  'hostDashboardHeading': 'Behind the curtain.',
};

/// Neutral interface copy. The English phrase is its editable catalog key.
/// Participant names, costume titles, and the saved event name never enter this
/// catalog and are displayed exactly as the server supplies them.
const germanUiText = <String, String>{
  'Choose language': 'Sprache auswählen',
  'Is this you?': 'Bist du das?',
  'That’s not me': 'Das bin ich nicht',
  'Yes, that’s me': 'Ja, das bin ich',
  'Hidden from guests until {date}. Your name stays visible; the host can see your costume.':
      'Bis {date} für Gäste verborgen. Dein Name bleibt sichtbar; die Orga kann dein Kostüm sehen.',
  'A ballot has already been submitted for this name. You can see its confirmation, but cannot vote again.':
      'Für diesen Namen wurden bereits Stimmen abgegeben. Du kannst die Bestätigung ansehen, aber nicht erneut abstimmen.',
  'Confirm this is your name and costume. Use a surname or nickname if someone else shares your name.':
      'Bestätige deinen Namen und dein Kostüm. Ergänze deinen Nachnamen oder einen Spitznamen, wenn jemand genauso heißt.',
  'Please confirm this is your own name and costume. Each name gets one ballot with three votes.':
      'Bitte bestätige, dass dies dein eigener Name und dein Kostüm sind. Pro Name gibt es eine Abstimmung mit drei Stimmen.',
  'Your final three': 'Deine endgültige Auswahl',
  'Voting as {name}. One vote for each of these costumes:':
      'Du stimmst als {name} ab. Jedes dieser Kostüme erhält eine Stimme:',
  'Once submitted, your ballot cannot be changed.':
      'Nach dem Absenden kannst du deine Stimmen nicht mehr ändern.',
  'Keep choosing': 'Auswahl ändern',
  'Submit my 3 votes': 'Meine 3 Stimmen abgeben',
  'PREVIEW  ·  Sample entries. No real votes are saved.':
      'VORSCHAU  ·  Beispieldaten. Es werden keine echten Stimmen gespeichert.',
  'Sign out': 'Abmelden',
  'Host': 'Orga',
  'Host sign in': 'Orga-Anmeldung',
  'Your three votes are in. Now get back to the party — the host will reveal the winners.':
      'Deine drei Stimmen sind abgegeben. Viel Spaß auf der Party – die Orga verkündet die Gewinner.',
  'Welcome, {name}. Find your favourites and give three brilliant costumes their moment.':
      'Willkommen, {name}. Wähle deine drei Lieblingskostüme und gib jedem eine Stimme.',
  '{count} costumes': '{count} Kostüme',
  '3 votes per person': '3 Stimmen pro Person',
  'REGISTRATION IS OPEN': 'ANMELDUNG GEÖFFNET',
  'THE BALLOT IS OPEN': 'ABSTIMMUNG GEÖFFNET',
  'VOTING HAS CLOSED': 'ABSTIMMUNG BEENDET',
  'Enter your name to join or return.\nOne name. Three different favourites.':
      'Gib deinen Namen ein, um mitzumachen oder zurückzukehren.\nEin Name. Drei verschiedene Favoriten.',
  'Your name': 'Dein Name',
  'e.g. Alex Smith': 'z. B. Alex Schmidt',
  'Join the party': 'Mitmachen',
  'Already entered? Use the same name to return.':
      'Schon angemeldet? Verwende denselben Namen, um zurückzukehren.',
  'Try the demo as Alex →': 'Demo als Alex ausprobieren →',
  'Registration is closed. Ask your host if you need help joining.':
      'Die Anmeldung ist geschlossen. Wende dich an die Orga, wenn du Hilfe brauchst.',
  'Your name will appear in the lineup. If someone shares your name, add your surname or a nickname.':
      'Dein Name wird öffentlich angezeigt. Ergänze deinen Nachnamen oder einen Spitznamen, wenn jemand genauso heißt.',
  'Your name / nickname': 'Dein Name / Spitzname',
  'e.g. Alex': 'z. B. Alex',
  'Use at least 2 characters.': 'Verwende mindestens 2 Zeichen.',
  'Your costume': 'Dein Kostüm',
  'e.g. The midnight magician': 'z. B. Mitternachtsmagier',
  'Tell us your costume.': 'Gib dein Kostüm an.',
  'Keep my costume secret': 'Mein Kostüm geheim halten',
  'Reveal on {date}. Your name stays visible; the host can see your costume.':
      'Enthüllung am {date}. Dein Name bleibt sichtbar; die Orga kann dein Kostüm sehen.',
  'Enter my costume': 'Kostüm eintragen',
  'Use a different name': 'Anderen Namen verwenden',
  'You’re all voted.': 'Deine Stimmen sind abgegeben.',
  'You’re on the list.': 'Du bist dabei.',
  'A ballot has been received for this name. You cannot submit another. Only the host can view the totals.':
      'Für diesen Namen wurden bereits Stimmen abgegeben. Du kannst nicht erneut abstimmen. Nur die Orga sieht das Ergebnis.',
  'Your costume is entered. Voting will appear here when the host opens the ballot.':
      'Dein Kostüm ist eingetragen. Sobald die Orga die Abstimmung öffnet, kannst du hier wählen.',
  'The ballot is closed. Stay tuned for the winner announcement from your host.':
      'Die Abstimmung ist beendet. Die Orga gibt die Gewinner bekannt.',
  'Pick three different costumes below. Your own entry is marked and cannot be selected.':
      'Wähle unten drei verschiedene Kostüme. Dein eigenes ist markiert und kann nicht ausgewählt werden.',
  'Voting as {name}': 'Du stimmst als {name} ab',
  'Three votes. Three different costumes.':
      'Drei Stimmen. Drei verschiedene Kostüme.',
  'Save your votes for someone else.': 'Wähle die Kostüme der anderen.',
  'Only your host can see the totals.': 'Nur die Orga kann das Ergebnis sehen.',
  'THE CONTENDERS': 'DIE TEILNEHMENDEN',
  'Refresh the lineup': 'Teilnehmerliste aktualisieren',
  'Tap a costume to add it to your ballot.':
      'Tippe auf ein Kostüm, um es auszuwählen.',
  'Secret costumes reveal automatically on {date}.':
      'Geheime Kostüme werden am {date} automatisch sichtbar.',
  'There need to be at least three other costumes before you can vote. Please check with your host.':
      'Du brauchst mindestens drei andere Kostüme zur Auswahl. Bitte wende dich an die Orga.',
  'Find a name or costume': 'Name oder Kostüm suchen',
  'Search the lineup': 'Teilnehmerliste durchsuchen',
  'No costumes found.': 'Keine Kostüme gefunden.',
  'Enter your costume to start the lineup.':
      'Trage dein Kostüm als erstes ein.',
  'Try another name or costume.':
      'Versuche einen anderen Namen oder ein anderes Kostüm.',
  'Secret costume': 'Geheimes Kostüm',
  ', your costume, cannot select': ', dein Kostüm, nicht auswählbar',
  'YOUR COSTUME': 'DEIN KOSTÜM',
  'ON YOUR BALLOT': 'DEINE AUSWAHL',
  'Reveals {date}': 'Sichtbar ab {date}',
  'Cheer for someone else': 'Wähle ein anderes Kostüm',
  'Ballot submitted': 'Stimmen abgegeben',
  'Join to vote': 'Zum Abstimmen anmelden',
  'Voting is not open yet': 'Abstimmung noch nicht geöffnet',
  'Voting is closed': 'Abstimmung geschlossen',
  'Selected · tap to remove': 'Ausgewählt · zum Entfernen tippen',
  'Three selected already': 'Bereits drei ausgewählt',
  'Add to my ballot': 'Auswählen',
  '{count} of 3 selected': '{count} von 3 ausgewählt',
  'Ready for a final look.': 'Bereit zum Prüfen.',
  'Pick {count} more costume.': 'Wähle noch {count} Kostüm.',
  'Pick {count} more costumes.': 'Wähle noch {count} Kostüme.',
  'Review votes →': 'Prüfen →',
  'Review my three votes →': 'Meine drei Stimmen prüfen →',
  'This copy is not connected to a contest yet. You can explore a preview with sample entries while the host finishes setup.':
      'Der Wettbewerb ist noch nicht eingerichtet. Du kannst die Vorschau mit Beispieldaten ausprobieren, während die Orga alles vorbereitet.',
  'Explore the preview': 'Vorschau ansehen',
  'Retry': 'Erneut versuchen',
  'Reopen registration?': 'Anmeldung wieder öffnen?',
  'Open the ballot?': 'Abstimmung öffnen?',
  'Close voting?': 'Abstimmung beenden?',
  'Voting will pause so more guests can enter. This is possible only before the first ballot is submitted.':
      'Die Abstimmung wird pausiert, damit sich weitere Gäste anmelden können. Das ist nur möglich, solange noch niemand abgestimmt hat.',
  'Registration will close. Entrants will each be able to submit one ballot with three votes. Make sure everyone has entered.':
      'Die Anmeldung wird geschlossen. Jede Person kann dann einmal drei Stimmen abgeben. Prüfe vorher, ob alle angemeldet sind.',
  'No more ballots will be accepted. Your results will remain private.':
      'Es werden keine weiteren Stimmen angenommen. Die Ergebnisse bleiben privat.',
  'Cancel': 'Abbrechen',
  'Confirm': 'Bestätigen',
  'Delete {name}’s entry?': 'Eintrag von {name} löschen?',
  'Remove “{costume}” from the contest? This cannot be undone. They can register again while registration is open.':
      '„{costume}“ aus dem Wettbewerb entfernen? Das kann nicht rückgängig gemacht werden. Solange die Anmeldung offen ist, kann sich die Person erneut anmelden.',
  'Keep entry': 'Eintrag behalten',
  'Delete entry': 'Eintrag löschen',
  '{name}’s entry deleted.': 'Eintrag von {name} gelöscht.',
  'Preview only. All names and votes here are sample data.':
      'Nur eine Vorschau. Alle Namen und Stimmen sind Beispieldaten.',
  'Manage the party and see the totals. Individual voting choices never appear in this view.':
      'Verwalte den Wettbewerb und sieh dir das Ergebnis an. Einzelne Stimmabgaben werden hier nicht angezeigt.',
  'Open the demo host view': 'Demo-Orga öffnen',
  'Host email': 'E-Mail der Orga',
  'Password': 'Passwort',
  'Sign in securely': 'Anmelden',
  'Refresh results': 'Ergebnisse aktualisieren',
  'Totals for your eyes only. No voter-by-voter breakdown.':
      'Nur du siehst die Ergebnisse. Es gibt keine Aufschlüsselung einzelner Stimmabgaben.',
  'Costumes entered': 'Angemeldete Kostüme',
  'Ballots received': 'Abgegebene Stimmzettel',
  'Votes cast': 'Abgegebene Stimmen',
  'Contest · {stage}': 'Wettbewerb · {stage}',
  'Registration open': 'Anmeldung geöffnet',
  'Voting open': 'Abstimmung geöffnet',
  'Contest closed': 'Wettbewerb beendet',
  'Contest name': 'Name des Wettbewerbs',
  'Contest name updated.': 'Name des Wettbewerbs aktualisiert.',
  'Save contest name': 'Namen speichern',
  'Costume reveal · {date}': 'Kostümenthüllung · {date}',
  'Guests can keep their costume name secret until then. You can see every costume here.':
      'Gäste können ihr Kostüm bis dahin geheim halten. Du kannst hier alle Kostüme sehen.',
  'The reveal time has passed. All costume names are now visible to guests.':
      'Die Enthüllung ist erfolgt. Alle Kostümnamen sind jetzt für Gäste sichtbar.',
  'Give everyone time to enter. At least four costumes are needed so each person has three others to choose from.':
      'Gib allen Zeit, sich anzumelden. Es werden mindestens vier Kostüme benötigt, damit jede Person drei andere auswählen kann.',
  'Voting is live. Close the ballot when everyone has had a chance to vote.':
      'Die Abstimmung läuft. Beende sie, sobald alle die Gelegenheit zum Abstimmen hatten.',
  'The ballot is closed. You can announce the results whenever you’re ready.':
      'Die Abstimmung ist beendet. Du kannst die Ergebnisse jetzt bekannt geben.',
  'Voting can open after the secret costumes are revealed.':
      'Die Abstimmung kann nach der Enthüllung der geheimen Kostüme geöffnet werden.',
  'Close registration & open voting':
      'Anmeldung schließen und Abstimmung öffnen',
  'Close voting': 'Abstimmung beenden',
  'Reopen registration': 'Anmeldung wieder öffnen',
  'Resume voting': 'Abstimmung fortsetzen',
  'The results': 'Die Ergebnisse',
  'Equal vote totals are a tie. Each submitted ballot contributes three votes.':
      'Gleiche Stimmenzahlen bedeuten Gleichstand. Jede abgeschlossene Abstimmung zählt drei Stimmen.',
  'You can delete an entry below while registration is open.':
      'Solange die Anmeldung geöffnet ist, kannst du unten Einträge löschen.',
  'Entry deletion is locked because voting has started.':
      'Einträge können nicht mehr gelöscht werden, da bereits Stimmen abgegeben wurden.',
  'Reopen registration to delete an entry before anyone votes.':
      'Öffne die Anmeldung wieder, um einen Eintrag zu löschen. Das geht nur, solange noch niemand abgestimmt hat.',
  'Results will appear here once costumes are entered.':
      'Die Ergebnisse erscheinen hier, sobald Kostüme eingetragen sind.',
  'Secret until {date}': 'Geheim bis {date}',
  'Delete {name}’s entry': 'Eintrag von {name} löschen',
};

/// Service/database messages stay in English at the transport boundary. Translate
/// on display so an already-visible error follows a language switch immediately.
const germanErrorText = <String, String>{
  'Something went wrong. Please try again.':
      'Etwas ist schiefgelaufen. Bitte versuche es erneut.',
  'Enter your name to continue.': 'Gib deinen Namen ein, um fortzufahren.',
  'Refresh the lineup and try your name again.':
      'Aktualisiere die Teilnehmerliste und gib deinen Namen erneut ein.',
  'Unable to complete that request. Please try again.':
      'Die Aktion konnte nicht abgeschlossen werden. Bitte versuche es erneut.',
  'Unable to refresh results.':
      'Die Ergebnisse konnten nicht aktualisiert werden.',
  'Use a name of 2 to 32 characters.':
      'Verwende einen Namen mit 2 bis 32 Zeichen.',
  'The server did not confirm your ballot. Sign in again to check its status.':
      'Der Eingang deiner Stimmen wurde nicht bestätigt. Melde dich erneut mit deinem Namen an, um den Status zu prüfen.',
  'Host sign-in was canceled. Please sign in again.':
      'Die Orga-Anmeldung wurde abgebrochen. Bitte melde dich erneut an.',
  'The server did not confirm the deletion. Refresh the host view before trying again.':
      'Die Löschung wurde nicht bestätigt. Aktualisiere den Orga-Bereich, bevor du es erneut versuchst.',
  'The live contest is not configured yet. Add the Supabase settings before deployment.':
      'Der Wettbewerb ist noch nicht eingerichtet. Bitte wende dich an die Orga.',
  'The contest server returned an unexpected response. Please try again.':
      'Der Server hat unerwartet geantwortet. Bitte versuche es erneut.',
  'The request timed out. Check your connection. If you submitted a ballot, sign in again to check whether it was saved.':
      'Die Anfrage hat zu lange gedauert. Prüfe deine Verbindung. Falls du abgestimmt hast, melde dich erneut mit deinem Namen an und prüfe, ob deine Stimmen gespeichert wurden.',
  'Unable to reach the contest. Check your connection and try again.':
      'Der Wettbewerb ist nicht erreichbar. Prüfe deine Verbindung und versuche es erneut.',
  'The contest connection is not configured correctly.':
      'Die Verbindung zum Wettbewerb ist nicht richtig eingerichtet. Bitte wende dich an die Orga.',
  'Host sign-in failed. Check your email and password, then try again.':
      'Die Anmeldung ist fehlgeschlagen. Prüfe deine E-Mail-Adresse und dein Passwort und versuche es erneut.',
  'Your host session has expired or this account is not the host. Sign in again.':
      'Deine Orga-Sitzung ist abgelaufen oder dieses Konto hat keine Orga-Berechtigung. Bitte melde dich erneut an.',
  'Too many requests. Wait a moment and try again.':
      'Zu viele Anfragen. Warte einen Moment und versuche es erneut.',
  'The contest database is not ready. Complete the database setup and try again.':
      'Der Wettbewerb ist noch nicht vollständig eingerichtet. Bitte wende dich an die Orga.',
  'The contest server is temporarily unavailable. Please try again shortly.':
      'Der Server ist vorübergehend nicht erreichbar. Bitte versuche es gleich noch einmal.',
  'The request could not be completed. Refresh the contest and try again.':
      'Die Anfrage konnte nicht abgeschlossen werden. Aktualisiere die Seite und versuche es erneut.',
  'The contest server returned unexpected data. Check that the latest database setup is installed.':
      'Die Daten des Wettbewerbs konnten nicht geladen werden. Bitte wende dich an die Orga.',
  'Host sign-in could not be completed. Please try again.':
      'Die Orga-Anmeldung konnte nicht abgeschlossen werden. Bitte versuche es erneut.',
  'Sign in as the host to use these controls.':
      'Melde dich als Orga an, um diese Funktionen zu nutzen.',
  'Your host session has expired. Sign in again.':
      'Deine Orga-Sitzung ist abgelaufen. Bitte melde dich erneut an.',
  'Your host session has ended. Sign in again.':
      'Deine Orga-Sitzung wurde beendet. Bitte melde dich erneut an.',
  'Voting is paused until secret costumes are revealed.':
      'Die Abstimmung ist bis zur Enthüllung der geheimen Kostüme pausiert.',
  'Voting cannot open while secret costumes are hidden.':
      'Die Abstimmung kann erst geöffnet werden, wenn die geheimen Kostüme enthüllt sind.',
  'That name is already registered. Confirm it is yours to continue.':
      'Dieser Name ist bereits registriert. Bestätige, dass es dein Name ist, um fortzufahren.',
  'Registration is not open.': 'Die Anmeldung ist nicht geöffnet.',
  'Registration is closed.': 'Die Anmeldung ist geschlossen.',
  'Use a costume name of 2 to 80 characters.':
      'Verwende einen Kostümnamen mit 2 bis 80 Zeichen.',
  'Voting is not open.': 'Die Abstimmung ist nicht geöffnet.',
  'Register your name and costume before voting.':
      'Trage zuerst deinen Namen und dein Kostüm ein.',
  'Register your name and costume first.':
      'Trage zuerst deinen Namen und dein Kostüm ein.',
  'You have already submitted your ballot.':
      'Du hast deine Stimmen bereits abgegeben.',
  'Your ballot has already been submitted.':
      'Deine Stimmen wurden bereits abgegeben.',
  'Choose exactly three different costumes.':
      'Wähle genau drei verschiedene Kostüme.',
  'You cannot vote for your own costume.':
      'Du kannst nicht für dein eigenes Kostüm stimmen.',
  'One of those costumes is unavailable. Refresh and try again.':
      'Eines dieser Kostüme ist nicht mehr verfügbar. Aktualisiere die Seite und versuche es erneut.',
  'One or more costumes are unavailable.':
      'Mindestens eines der Kostüme ist nicht mehr verfügbar.',
  'Open the demo host view to use these controls.':
      'Öffne den Demo-Orga-Bereich, um diese Funktionen zu nutzen.',
  'Entries can only be deleted while registration is open.':
      'Einträge können nur gelöscht werden, solange die Anmeldung geöffnet ist.',
  'Entries cannot be deleted after a ballot has been submitted.':
      'Einträge können nicht mehr gelöscht werden, sobald Stimmen abgegeben wurden.',
  'That entry no longer exists.': 'Dieser Eintrag existiert nicht mehr.',
  'Registration cannot reopen after a ballot is submitted.':
      'Die Anmeldung kann nicht wieder geöffnet werden, sobald Stimmen abgegeben wurden.',
  'At least four costumes are needed to open voting.':
      'Zum Öffnen der Abstimmung werden mindestens vier Kostüme benötigt.',
  'At least four costumes are needed for three votes each.':
      'Für jeweils drei Stimmen werden mindestens vier Kostüme benötigt.',
  'Use an event title of 1 to 80 characters.':
      'Verwende einen Wettbewerbsnamen mit 1 bis 80 Zeichen.',
  'Organizer access required.':
      'Für diese Aktion brauchst du Orga-Berechtigung.',
  'Choose registration, voting, or closed.':
      'Wähle eine gültige Phase des Wettbewerbs.',
};

class AppCopy {
  const AppCopy(this.language);
  final AppLanguage language;

  String text(String english, [Map<String, Object> values = const {}]) => _fill(
      language == AppLanguage.german
          ? germanUiText[english] ?? english
          : english,
      values);

  String flavour(String key, [Map<String, Object> values = const {}]) => _fill(
      language == AppLanguage.german
          ? germanFlavourCopy[key] ?? englishFlavourCopy[key]!
          : englishFlavourCopy[key]!,
      values);

  String translateError(String message) {
    if (language == AppLanguage.english) return message;
    final translated = germanErrorText[message] ?? germanUiText[message];
    if (translated != null) return translated;
    if (germanUiText.containsValue(message) ||
        germanErrorText.containsValue(message)) {
      return message;
    }
    final deleted = RegExp(r'^(.*)’s entry deleted\.$').firstMatch(message);
    if (deleted != null) {
      return text('{name}’s entry deleted.', {'name': deleted.group(1)!});
    }
    return germanErrorText['Something went wrong. Please try again.']!;
  }

  String revealLabel(DateTime date) {
    // This event's configured dates are in Central European winter time.
    final cet = date.toUtc().add(const Duration(hours: 1));
    const en = [
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
    const de = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember'
    ];
    final hour = cet.hour.toString().padLeft(2, '0');
    final minute = cet.minute.toString().padLeft(2, '0');
    return language == AppLanguage.german
        ? '${cet.day}. ${de[cet.month - 1]} ${cet.year} um $hour:$minute Uhr MEZ'
        : '${cet.day} ${en[cet.month - 1]} ${cet.year} at $hour:$minute CET';
  }

  String _fill(String template, Map<String, Object> values) =>
      template.replaceAllMapped(RegExp(r'\{([a-z]+)\}'),
          (match) => values[match.group(1)]?.toString() ?? match.group(0)!);
}

class AppLanguageScope extends InheritedWidget {
  const AppLanguageScope(
      {required this.language,
      required this.onChanged,
      required super.child,
      super.key});
  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;
  AppCopy get copy => AppCopy(language);

  static AppLanguageScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguageScope>()!;

  @override
  bool updateShouldNotify(AppLanguageScope oldWidget) =>
      language != oldWidget.language;
}

class LanguageSwitcher extends StatelessWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppLanguageScope.of(context);
    return PopupMenuButton<AppLanguage>(
      key: const Key('language-switch'),
      tooltip: scope.copy.text('Choose language'),
      initialValue: scope.language,
      onSelected: scope.onChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(value: AppLanguage.german, child: Text('Deutsch')),
        PopupMenuItem(value: AppLanguage.english, child: Text('English')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(scope.language == AppLanguage.german ? 'DE' : 'EN',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          const Icon(Icons.expand_more, size: 16),
        ]),
      ),
    );
  }
}
