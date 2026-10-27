# TaskFlow

A dark, glassmorphic to-do app built with Flutter. Everything lives on the
device: accounts in SQLite, tasks in SQLite, reminders as real Android
notifications scheduled at each task's due time. No backend, no API keys, no
network permission — it works in aeroplane mode.

---

## Features

**Accounts**
- Sign up and sign in with an email and password, stored locally
- Passwords are never stored: only a PBKDF2-HMAC-SHA256 digest with a
  per-account random salt (30,000 iterations, hashed on a background isolate
  so the form never janks)
- The session survives app restarts; "Remember me" pre-fills the email
- Change your password from Settings (current password required)
- Tasks are scoped to the signed-in account, so two people on one phone never
  see each other's list

**Tasks**
- Create, edit, complete, re-open and delete
- Swipe a card left to delete, with an UNDO in the snackbar
- Search by title or description
- Filter by All / Pending / Completed / Today / Overdue, and by category
- Sort by due date, priority, recently added or title — the choice is
  remembered
- Six categories, each with a fixed icon and colour
- Low / Medium / High priority

**AI Assist — on the phone, not in a datacentre**

The + button opens the assistant. Everything below runs locally against the
user's own SQLite rows: no account, no API key, no network call, and the app
holds no INTERNET permission, so none of it *can* leave the device.

- **Write it the way you'd say it.** "Submit the client report tomorrow 5pm
  urgent" becomes a task with the date, time, priority and category filled in,
  and the sheet shows what it understood before anything is saved.
- **It fills in what you leave out, from your habits.** Median scheduled time
  per category, the priority you usually give each category, and the hours you
  actually complete things in. Every suggestion is shown with its reason —
  "You usually schedule Health tasks around 6:00 AM" — never a silent guess.
- **It remembers what you repeat.** Titles you add again and again become
  one-tap chips, and a task that keeps landing on the same weekday is flagged
  as looking weekly.
- **Split into steps.** A big task is broken into a starting checklist matched
  from a library of common task shapes (studying, writing, a trip, a bug, a
  workout…). Steps are editable and selectable before any are added, and the
  sheet says plainly when it fell back to a generic three-step split.
- **Plan my day.** Lays today's open work — overdue first, then priority —
  across the rest of the day in 45-minute blocks, starting at the next quarter
  hour and favouring your productive hours. Nothing is written until you
  accept the plan.
- **What I noticed.** The Analytics tab reports the patterns it found: your
  peak hour, your strongest weekday, which category is slipping, and how far
  late tasks typically slip.
- **It talks to you.** The home screen opens with a line that reacts to your
  actual list — "Hi Anusha 👀 2 tasks slipped past their time", "Nice going,
  Anusha 🔥 2 of 5 done today", "Today's list is clear 🎉" — with a tap that
  takes you straight to whatever it just mentioned. This, not a badge on a
  button, is how the assistant makes itself known.
- **Speak instead of typing.** A mic in the assistant dictates into the same
  field. Indian English is the default language because it handles Tanglish —
  English and Tamil in one sentence — better than either pure locale.
- **It understands Tanglish.** `naalaiku kaalai`, `innaiku raathiri`,
  `velli`, `2 naal kazhichu`, `avasaram`, `amma`, `saman vaanganum` — dates,
  times, priorities and categories all parse from romanised Tamil as well as
  English, and trailing helpers like `pannanum` are stripped from the title.
- **It can speak Tanglish back.** Settings → *Talk to me in Tanglish* switches
  the greetings and nudges: "Hi Anusha 👋 Innaikku 4 task irukku, innum onnu
  kooda complete panla. Onnu start pannu, adhuve poadhum 💪"

> **One honest exception to "nothing leaves the phone":** voice dictation is
> handed to the phone's own speech recogniser — Google's, on most Android
> phones — which may send the audio to its servers. The app never sees or
> stores audio and still holds no INTERNET permission of its own, and the
> assistant says this on screen rather than letting the privacy claim blur.

It only speaks up once it has seen enough: below three tasks in a category it
says so instead of inventing a pattern.

**Where this sits in the market.** Todoist Assist does the same class of thing
— subtask breakdown, due-date suggestions from history, daily planning — but
in the cloud, on a paid tier. Motion and Reclaim auto-schedule, also cloud.
The privacy-first local-first apps (Super Productivity and friends) keep your
data but ship no AI at all. TaskFlow is the combination neither side offers:
the assistance, with the data never leaving the phone.

**Smart Add parsing** (the layer underneath)
Type a task the way you would say it and the form fills itself in:

| You type | It understands |
|---|---|
| `Submit client report tomorrow 5pm urgent` | tomorrow, 17:00, High, Work |
| `Gym monday 6am` | next Monday, 06:00, Health |
| `Buy groceries in 3 days` | +3 days, Shopping |
| `remind me to call mom at 8pm` | today 20:00, Personal, filler stripped |

It recognises `today`, `tomorrow`, `day after tomorrow`, weekday names,
`in N days/weeks`, `next week`, `12/5`, `5 dec`, clock times, `morning` /
`evening` / `noon`, and priority words like `urgent` or `whenever`. Everything
it guesses is shown as a chip so you can correct it before saving.

**Reminders**
- A local notification fires at the task's date and time
- Exact alarms where the OS allows them, inexact as a fallback
- Reminders are cancelled when a task is completed or deleted, and rescheduled
  when it is edited or re-opened
- The whole schedule is rebuilt on sign-in and after a device reboot
- One switch in Settings turns them all off and back on

**Backup & restore**
- Export every task to a `taskflow-backup-YYYY-MM-DD.json` file and send it
  wherever you keep things — Drive, Files, a chat with yourself
- Restore from that file on a new phone, or after a reinstall
- Restoring only ever adds: nothing is deleted, and a task you already have
  (same title, date and time) is skipped, so importing twice is harmless
- Reminders in the future are re-scheduled as part of the restore

**Calendar**
- Month view with a dot on every day that has tasks
- Tap a day to see its tasks; add a task straight onto that day

**Analytics**
- Completion percentage, current streak, overdue count
- Last-7-days completion chart
- Task split by category
- This month's created / completed / open counts

---

## Run it

```bash
flutter pub get
flutter run
```

That is the whole setup — there is nothing to configure.

Grant the notification permission when asked, or reminders stay silent.
Settings → *Send a test notification* confirms they are getting through.

Built and verified against Flutter 3.35.4. The Android side needs Java 17 and
Kotlin Gradle plugin 2.3.0 with core-library desugaring, because
`flutter_local_notifications` 20.x compiles against Java 17; both are pinned in
`android/settings.gradle.kts` and `android/app/build.gradle.kts`.

---

## Why local accounts instead of Firebase

This app was first wired up with Firebase Auth. Google now requires a billing
account before Firebase Authentication can be initialised on a **newly created**
project — the console returns *"Error updating Email/Password"* and the
`identityPlatform:initializeAuth` API returns `BILLING_NOT_ENABLED`. Projects
created earlier are unaffected, which is what makes the failure confusing.

Rather than attach a card to run a to-do app, authentication moved into the
app's own database. The trade-off is deliberate:

- **Gained:** zero setup, works offline, no keys in the repo, no vendor account
- **Given up:** no sync between devices, and **no password recovery** — there is
  no server to email a reset link from. The login screen says so plainly instead
  of offering a button that cannot work.

Because the data has nowhere else to live, Settings → *Export backup* is the
answer to "what happens if I lose the phone". Uninstalling the app deletes the
database, so export first.

If cloud sync is ever needed, `AuthService` is the only file that talks about
accounts; swapping its body for a remote provider leaves the rest of the app
untouched.

---

## Project layout

```
lib/
  main.dart                  prefs + session restore + notification bootstrap
  models/
    task_model.dart          the task, its derived values and (de)serialisation
    user_model.dart          a local account (never holds a plain password)
  database/
    database_helper.dart     SQLite schema, migrations, queries and stats
  services/
    auth_service.dart        local sign-up/sign-in, session, validation
    backup_service.dart      JSON export/import, duplicate-safe restore
    password_hasher.dart     PBKDF2-HMAC-SHA256 hashing and constant-time check
    task_intelligence.dart   on-device learning: habits, insights, day plan
    task_breakdown.dart      pattern library that splits a task into steps
    coach.dart               the home-screen greeting, English or Tanglish
    voice_input.dart         dictation via the phone's speech recogniser
    notification_service.dart scheduling, permissions, reschedule-all
    shared_pref_service.dart typed SharedPreferences wrapper
    smart_parser.dart        the offline natural-language parser
    task_events.dart         notifier that keeps the four tabs in sync
  screens/
    splash_screen.dart       branded splash → AuthGate
    auth_gate.dart           signed in? → MainShell, else → LoginScreen
    login_screen.dart        sign in
    signup_screen.dart       create account
    main_shell.dart          bottom nav + the four tabs in an IndexedStack
    ai_assist_sheet.dart     the + button: capture, habits, split into steps
    plan_day_sheet.dart      proposes a time for everything open today
    home_screen.dart         search, filters, stats, task list
    calendar_screen.dart     month view + the selected day's tasks
    analytics_screen.dart    progress, streak, weekly chart, category split
    settings_screen.dart     profile, password, reminders, backup, sign out
    add_task_screen.dart     thin wrapper around TaskForm
    edit_task_screen.dart    same form, plus delete
  widgets/                   glass panels, task card, form, pickers, chrome
  utils/
    app_colors.dart          brand palette
    app_spacing.dart         the one spacing, radius and icon-size scale
    app_theme.dart           the single dark ThemeData
    constants.dart           categories, priorities, filter/sort enums
    date_helper.dart         storage vs display formats, legacy parsing
test/widget_test.dart        unit tests for hashing, the parser, date handling
```

## Database

`todo.db`, schema version 3.

| Version | Change |
|---|---|
| 1 | original `tasks` table; `d/M/yyyy` dates and `9:00 AM` times |
| 2 | dates rewritten to `yyyy-MM-dd` and `HH:mm` so they sort; added `userId`, `createdAt`, `completedAt` |
| 3 | added the `users` table for local accounts |

The v2 migration rewrites existing rows rather than dropping them, and tasks
created before accounts existed are adopted by the first account that signs in,
so upgrading never loses data.

## Colour choices in Analytics

The six category colours are not decorative. They were checked against the dark
chart surface for lightness, chroma, contrast and colour-vision separation — the
original blue/violet pair for Work and Personal was indistinguishable to readers
with deuteranopia (ΔE 1.3) and hard even with full colour vision (ΔE 12). The
current set passes, and the analytics breakdown still labels every bar with an
icon and a name so identity never rests on colour alone.

## Tests

```bash
flutter test
```

49 tests cover password hashing (round-trip, wrong password, unique salts,
failing closed on a missing salt), the Smart Add parser (dates, times,
priorities, filler stripping, rollover behaviour), the on-device learning
(median-not-mean times, refusing to claim a habit from too few samples,
recurring-task detection, day-plan ordering and its 10pm cutoff), the
breakdown library, the Tanglish parsing, the coach's message selection, and
the legacy date/time parsing the migration depends on.

`TaskProfile.planDay` takes `now` as a parameter and judges "overdue" against
that same instant rather than the wall clock — the two disagreeing was a real
bug the tests caught.
