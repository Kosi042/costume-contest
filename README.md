# Costume Club

A mobile-friendly costume contest built with Dart and Flutter. GitHub Pages hosts the website; Supabase stores entries and votes and protects the organizer's results.

**Live website:** [kosi042.github.io/costume-contest](https://kosi042.github.io/costume-contest/).

This repository deploys automatically to GitHub Pages from `main`. Its Supabase project is configured through repository variables. The live contest starts with registration open and no sample entries. Use **Host sign in** on the website with your contest organizer email and password to manage the event.

Contestants enter their name and costume, then choose their name and confirm **“Yes, that’s me”** before voting. The backend allows one final ballot per normalized name, with **exactly three different costumes**, excluding that entrant's own costume. At least four contestants are needed before voting can open.

Names are compared after normalizing capitalization and extra spaces, so changing those cannot create a duplicate entry. People with the same real name should include a surname or recognizable nickname.

Registration is open now. Guests may select **Keep my costume secret**: their name stays visible, while their costume title stays hidden from guests until **31 October 2026 at 20:00 CET (19:00 UTC)**. The host can see all costume titles. The server controls the reveal, and open pages refresh automatically at the deadline. Voting remains a host action and cannot open while any secret costume is still hidden.

Entries and votes are stored persistently in Supabase. They do not expire at 23:30 on 31 October, and this app has no automatic deletion schedule. The free plan can pause projects after a week of low activity; check the live site and Supabase dashboard before the event. See [Supabase's pausing guidance](https://supabase.com/docs/guides/platform/free-project-pausing).

## Try the local demo

Install [Flutter](https://docs.flutter.dev/get-started/install) and Chrome or Edge. This project uses Flutter **3.44.1** in deployment. In the project folder, run these commands in PowerShell, Terminal, or another shell:

```text
flutter pub get
flutter run -d chrome --dart-define=DEMO_MODE=true
```

On Windows, `flutter run -d edge --dart-define=DEMO_MODE=true` also works. If Flutter cannot find your browser, use `flutter run -d web-server --dart-define=DEMO_MODE=true` and open the address it prints.

Demo mode uses sample data in memory. It does not save real entries or votes. A published live build always uses `DEMO_MODE=false` and requires the backend configuration below.

## Set up the private backend

1. Create a [Supabase project](https://supabase.com/dashboard) and save its database password privately.
2. In the project's SQL editor, apply the files in `supabase/migrations/` once each, in filename order. The first creates the private tables and app functions; `202610240002_secret_reveal_and_entry_deletion.sql` adds the timed reveal and host entry deletion. For an existing project, apply only migrations that have not already been applied, before publishing the matching frontend.
3. In **Authentication → Users**, create your organizer user with an email address and strong password. Confirm the user's email when creating the user. Copy its user UUID.
4. Disable **Allow new users to sign up** in [Authentication settings](https://supabase.com/docs/guides/auth/general-configuration). Attendees use their names and do not need Auth accounts. Keep email/password sign-in enabled for your organizer account only.
5. In the SQL editor, replace the placeholder below with your organizer user's UUID and run:

   ```sql
   insert into contest_private.owners (user_id)
   values ('YOUR_ORGANIZER_AUTH_USER_UUID');
   ```

6. Copy the project's URL and its **publishable key** (or legacy **anon** key) from the project's connection/API settings. These are [public app configuration](https://supabase.com/docs/guides/getting-started/api-keys). Never put a secret key, `service_role` key, database password, or organizer password in the website or repository.

The private schema must remain private: do not add `contest_private` to exposed API schemas or grant browser roles access to its tables. The included app functions enforce registration, ballot limits, and organizer authorization on the server.

## Publish for free on GitHub Pages

[GitHub Pages supports public repositories on GitHub Free](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages). Supabase is a separate service. As checked on 24 October 2026, its [free plan](https://supabase.com/pricing) includes a 500 MB database, 50,000 monthly active Auth users, and 5 GB of egress. Free projects pause after one week of inactivity, so open your project and verify the live site before the event.

For your GitHub account, **kosi042**, either repository name works:

| Repository name | Resulting website address |
| --- | --- |
| `kosi042.github.io` | [https://kosi042.github.io](https://kosi042.github.io) |
| `costume-contest` | [https://kosi042.github.io/costume-contest/](https://kosi042.github.io/costume-contest/) |

The included workflow automatically handles either address.

1. Create a **public GitHub repository** and upload this project's source files. Keep real participant data, passwords, and database exports out of GitHub.
2. Open **Settings → Secrets and variables → Actions → Variables** and create these repository variables:

   | Variable | Value |
   | --- | --- |
   | `SUPABASE_URL` | Your project's HTTPS URL |
   | `SUPABASE_ANON_KEY` | Its public publishable key or legacy anon key |

3. Open **Settings → Pages** and choose **GitHub Actions** as the build and deployment source.
4. Push the files to the repository's default branch, or open **Actions → Publish costume contest → Run workflow** and select the default branch.
5. Wait for the workflow to finish, then open the website address shown in its deployment or in Pages settings.

The workflow installs Flutter 3.44.1, analyzes the code, runs tests, builds the live app, and publishes `build/web`. It runs only for default-branch pushes and manual runs on the default branch; pull requests do not deploy. It automatically uses `/REPOSITORY/` for project sites and `/` for a repository named `OWNER.github.io`. These instructions assume the standard `github.io` address.

Deployment intentionally stops if either configuration variable is missing or if the key appears to be a secret/service-role key. The setup steps above apply when deploying a separate copy of this project; the live repository is already configured. Private credentials are never included in the source.

## Run the contest

1. Open the organizer view and sign in with your Supabase Auth email and password.
2. Set the event title and keep the contest in **Registration** while people enter.
3. Share the website address. Each attendee registers their name and costume once. Duplicate names are rejected even if capitalization or extra spaces differ; attendees with the same real name should add a surname or nickname.
4. Attendees choose their own name and confirm **“Yes, that’s me”** in the popup before continuing.
5. Once at least four people have registered, change the stage to **Voting**. Everyone chooses three other costumes and confirms one final ballot. The backend rejects duplicate choices, votes for the selected entrant's own costume, repeat ballots for the same normalized name, and late registration.
6. Change the stage to **Closed** when voting ends. View the totals in the organizer view and announce the result yourself.

The name confirmation helps prevent accidental selection; it does not authenticate identity. This is an **honor-system contest**: someone could choose another person's name or invent another name. The limit is one ballot per normalized name, so use this version with a trusted group that agrees to enter and vote only as themselves.

Registration can reopen only before the first ballot is submitted; closed voting can be resumed. There is no reset button that erases an event.

To remove a mistaken entry, open **Host sign in → The results**, choose **Delete [name]'s entry**, and confirm. Deletion is available only while registration is open and no ballots have been submitted. It removes that contestant and costume, freeing the name to register again. If voting was opened but nobody has voted, reopen registration first. Once a ballot exists, deletion is locked to protect the results.

## What stays private

Entrant names are public. Costume names are public unless their entrant chooses the timed secret option; those titles are omitted from public responses until the reveal time. Returning with an entrant's name does not expose their secret costume. The organizer view can see secret titles and aggregate results, not individual ballots, and only an email/password account on the owner allowlist can access it. Other attendees cannot see vote totals or who voted for whom.

This provides privacy within the app, not cryptographic anonymity from the database owner. The underlying database links ballots to participant records to enforce the voting rules, so someone with full database access can inspect those links. Do not promise voters otherwise.

Supabase protects project API connections with [TLS](https://supabase.com/docs/guides/security/tls) and encrypts stored database data and backups with [AES-256](https://supabase.com/legal/privacy-resources/data-residency-and-transfers-faq). Security remains a [shared responsibility](https://supabase.com/docs/guides/security/soc-2-compliance): keep the private tables inaccessible to browser roles, retain the organizer allowlist checks, and protect the organizer and database credentials. Encryption does not verify an attendee's chosen name.

## Local live configuration and checks

To connect a local build to your real backend, create the ignored file `config.local.json`:

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_PUBLIC_PUBLISHABLE_OR_ANON_KEY",
  "DEMO_MODE": "false"
}
```

```text
flutter run -d chrome --dart-define-from-file=config.local.json
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn --dart-define-from-file=config.local.json
```

The resulting website is in `build/web`. Serve that folder with a local web server to inspect a release build; opening `index.html` directly is insufficient. For a manual project-site build, also pass `--base-href=/REPOSITORY/`.

The database contract tests are [`supabase/tests/contest_contract.sql`](supabase/tests/contest_contract.sql) and [`supabase/tests/secret_reveal_contract.sql`](supabase/tests/secret_reveal_contract.sql). Run them in a development project after applying the migrations. They test access controls, voting rules, the reveal boundary, and guarded deletion, and roll back their fixtures. Do not run them during a real event; they temporarily lock and hide contest data inside their transactions.

The deployment helper `scripts/prepare_deploy.py` can also create the ignored JSON file from local environment variables. It validates that the key is suitable for a public client, writes JSON safely, and never prints the key. In GitHub Actions it writes the configuration outside the published artifact and computes the correct Pages path.
