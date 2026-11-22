# Vault Board: CSC 4360 Homework 02

A Flutter message board using Firebase Authentication (email/password) and Cloud Firestore. Signed-in users post, edit and delete their own messages, and every user sees changes live. Firestore security rules, not the UI, decide who can read and write.

## Quick test (no build needed)

1. Install the release APK submitted on the LMS (`hw02_message_board-v1.0.0.apk`) on an Android emulator or phone:
   ```bash
   adb install hw02_message_board-v1.0.0.apk
   ```
2. Open **Vault Board**. Sign in with a test account, or tap **No account? Create one** to register a new one.

   | Email | Password |
   | --- | --- |
   | `ada@test.dev` | `test1234` |
   | `grace@test.dev` | `test1234` |

3. Try it:
   - **Create:** type a message and tap Send.
   - **Read:** sign in as the other account on a second emulator. New posts appear there without a refresh.
   - **Update / Delete:** tap the ⋮ menu on your own message. Other people's messages have no menu.
   - **Security rules:** tap the shield icon in the top bar. Each button sends a write that skips the app's checks (edit someone else's message, delete it, post as another user). Firestore answers `DENIED by Firestore: [permission-denied]`.
   - **Signed-out read:** sign out, then tap **Rules check: read board signed out** on the login screen. It is also denied.

## Build from source

You need Flutter 3.50+, plus the Firebase config file `.env.json`, which is not committed. Copy `.env.example.json` and fill it in from Firebase Console → Project settings → Android app.

```bash
flutter pub get
python3 tool/gen_google_services.py                            # writes android/app/google-services.json
flutter run --dart-define-from-file=.env.json                  # run on a connected emulator
flutter build apk --release --dart-define-from-file=.env.json  # build/app/outputs/flutter-apk/app-release.apk
flutter test                                                   # widget tests
```

If `.env.json` is missing, the splash screen shows "Firebase config missing" instead of starting.

## Data model

| Document | Fields | Who can write | Who can read |
| --- | --- | --- | --- |
| `users/{uid}` | `uid`, `firstName`, `lastName`, `role`, `registrationDateTime` | Owner, once, at registration | Owner only |
| `messages/{msgId}` | `text`, `authorUid`, `authorName`, `createdAt`, `editedAt` | Create: any signed-in user, as themselves. Update/delete: author only | Any signed-in user |

All timestamps are server time. `role` is a label only, and no rule uses it.

## Security rules (`firestore.rules`)

- Signed-out users can't read anything.
- A user record is created once by its owner with exactly the five fields, and can't be changed or deleted later.
- A new message must use your own `authorUid`, have 1 to 500 characters of text, and a server timestamp.
- Only the author can edit a message, and the edit may change only `text` and `editedAt`.
- Only the author can delete a message.

Deploy them with `firebase deploy --only firestore:rules`.

## Code layout

- `lib/main.dart`: Firebase init behind the splash screen.
- `lib/screens/auth_gate.dart`: follows `authStateChanges()`, showing Login when signed out and the board when signed in.
- `lib/services/auth_service.dart`: every Firebase Auth call.
- `lib/services/board_service.dart`: every Firestore call. The board is a `snapshots()` stream.
- Screens never touch Firestore directly.

## Extra spices

- **#4 Idempotent create:** each message gets one document id that is reused on retry, and a transaction creates it only if it doesn't exist yet. Double-tapping Send makes one message.
- **#2 Rules unit tests:** 10 tests in `rules-tests/` run against the Firestore emulator:
  ```bash
  cd rules-tests && npm install && cd ..
  firebase emulators:exec --only firestore --project demo-hw02-rules "cd rules-tests && npm test"
  ```
- **#1 Emulator Suite:** run the app against local emulators with seeded data, so production is never touched:
  ```bash
  firebase emulators:start --only auth,firestore
  # second terminal: seed the test accounts and five messages
  cd scripts/seed-emulator && npm install && \
    FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 npm run seed
  # third terminal: forward the ports and run the app
  adb reverse tcp:9099 tcp:9099 && adb reverse tcp:8080 tcp:8080
  flutter run --dart-define-from-file=.env.json --dart-define=USE_EMULATOR=true --dart-define=EMULATOR_HOST=127.0.0.1
  ```
  The Emulator UI is at http://127.0.0.1:4000.

## Evidence

Screenshots are in `docs/screenshots/`. The full write-up is the evidence document submitted on the LMS.

## Security note

The Firebase config is injected at build time from the gitignored `.env.json`. The Android API key is restricted to this app's package name, signing certificate and required APIs. The key from early commits was deleted on 2026-11-21 and no longer works.
