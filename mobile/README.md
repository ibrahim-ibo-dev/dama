# Dama for Android and iOS

A native Flutter client for the private Kurdish / Turkish dama game. Flutter draws the screens and board directly; this is not a WebView wrapper. The interface uses Sorani Kurdish, right-to-left layout, a bundled Arabic font, and light/dark appearances.

The mobile app and [the website](https://dama.ibrahim-eng.dev) use the same room API. Friends on Android, iPhone and desktop browsers can join the same room: two player seats and up to two spectators.

## بەکارهێنان بە کوردی

١. ئەپەکە بکەرەوە و ناوەکەت بنووسە. «ڕوومێکی نوێ» هەڵبژێرە.

٢. لینک یان کۆدی ڕوومەکە بۆ هاوڕێکەت بنێرە. ئەو دەتوانێت لە ئەپ یان وێبسایتەکە پەیوەست بێت؛ هەردووکتان هەمان سێرڤەر بەکاربهێنن.

٣. لە ئەپەکەدا، هاوڕێکەت کۆدە ١٠ پیتییەکە بنووسێت و «یاریزان» هەڵبژێرێت. دوو کەسی تریش دەتوانن وەک «تماشاکەر» بچنە ژوورەوە.

٤. بۆ یاری بە تەنیا، «لەگەڵ بۆت» هەڵبژێرە: ئاسان، مامناوەند یان بەهێز. «تاقیکردنەوەی دوو کەسی»یش هەیە و ئینتەرنێتی ناوێت.

٥. لە ڕێکخستنەکاندا ڕووکار، تەختە، دەنگ و ئاماژەکان بگۆڕە. ئەگەر سێرڤەرەکەت وشەی نهێنی هەبوو، بۆ چوونەژوورەوە بینووسە؛ ئەپەکە وشە نهێنییەکە هەڵناگرێت.

## Development

Flutter **3.38.0** and its bundled Dart **3.10** were used for this client. `pubspec.yaml` accepts Dart `>=3.8.0 <4.0.0`; CI pins Flutter 3.38.0. Android requires an Android SDK and JDK 17. iOS requires a Mac, Xcode and its iOS tooling; the generated project targets iOS 13.0.

Use the selected SDK explicitly if several installations exist. The Windows development machine used `C:\flutter\bin\flutter.bat`; no global SDK upgrade is required. From the repository root:

```sh
cd mobile
flutter --version
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d DEVICE_ID
```

Replace `DEVICE_ID` with an ID printed by `flutter devices`. Keep `pubspec.lock` committed. Fonts are bundled in `assets/fonts/`; the app does not download fonts at runtime. Shared logic and HTTP/controller tests do not require a live room.

## Server selection and crossplay

The default API origin is `https://dama.ibrahim-eng.dev`. The lobby also has a server URL setting. Enter the base URL, not `/api/rooms`, and use the same server as your friends. Each selected server has a separate stored player identity; room codes do not transfer between servers.

To build with another default:

```sh
flutter run --dart-define=DAMA_SERVER_URL=https://your-dama.example
flutter build apk --release --dart-define=DAMA_SERVER_URL=https://your-dama.example
```

`DAMA_SERVER_URL` is a public endpoint, not a secret. Use trusted HTTPS for normal device builds. A self-hosted server must expose the same API and shared Redis room store as the web client. Native HTTP requests do not need browser CORS configuration.

A shared HTTPS invitation opens the web room in a browser. In the native app, enter its ten-character room code or paste the full invitation link. Pasting a link extracts only the room code; it never changes the configured server or sends your player token to the link's host. Verified Android App Links and iOS Universal Links are not configured.

The Flutter screens follow the website's design: the same four-square brand, Noto Sans Arabic and Manrope fonts, cream/forest/copper palette, entry tabs, three bot cards, wood board and matching dark theme. Both font families are bundled. The website source remains in the repository root; the native client stays in `mobile/`.

### Room protocol

All member requests send `x-player-token`; request bodies are JSON. The server assigns identities and validates online moves.

| Request | Purpose |
| --- | --- |
| `GET /api/status` | Availability and whether a shared room-entry password is required |
| `POST /api/rooms` | Create with `name` and optional `password` |
| `POST /api/rooms/{code}` | Join with `name`, optional `password`, and `role: player` or `spectator` |
| `GET /api/rooms/{code}` | Read an authorized snapshot |
| `PATCH /api/rooms/{code}` | Move, heartbeat, chat, draw, resign, rematch or leave |

A move contains `from`, the **entire** landing `path`, expected `ply`, and `gameId`. The board previews intermediate jumps locally and submits a complete legal turn. Duplicate/stale moves are rejected by the backend.

Foreground polling runs approximately every two seconds and heartbeats approximately every twenty seconds. Backgrounding pauses polling. Reconnection fetches current state instead of blindly replaying a move. Generation guards discard responses from a departed room or previous server selection.

Chat keeps the latest forty messages, at most 240 characters each. Match history keeps the latest twenty completed games. Wins use stable player IDs, so swapping colors for a rematch preserves the score.

## Android APK

Build a release-mode APK from `mobile/`:

```sh
flutter pub get
flutter build apk --release
```

The file is `build/app/outputs/flutter-apk/app-release.apk`. Copy it to your Android phone and open it. Android may ask you to allow installation from the file manager/browser opening that APK. For a connected device with Android Platform Tools:

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

For development, `flutter run` works with a device or emulator. CI builds `app-debug.apk` specifically for development testing.

### Signing and private updates

Local builds use the generated debug signing identity unless `android/key.properties` configures a private release keystore. A release-mode build using that fallback is for local preview/private testing, not a finished Google Play release. Debug keys differ between machines and CI runners, so their APKs may not update one another.

For consistent private updates, configure and retain your own key. The Gradle configuration supports a local, ignored `android/key.properties` containing:

```properties
storePassword=YOUR_LOCAL_STORE_PASSWORD
keyPassword=YOUR_LOCAL_KEY_PASSWORD
keyAlias=YOUR_KEY_ALIAS
storeFile=PATH_TO_YOUR_KEYSTORE
```

Keep this file and the keystore out of Git and uploaded artifacts. On Windows, use a correctly escaped path or forward slashes. Keep the package ID/signing identity stable and increment `version`'s build number in `pubspec.yaml` for distributed updates. A signature mismatch requires the previous key; uninstalling would erase this installation's local session.

See [Flutter's Android deployment guide](https://docs.flutter.dev/deployment/android) for keystore creation and store distribution.

## iOS

The source includes a native iOS project targeting iOS 13.0. Windows can edit Dart and run shared tests, but cannot compile iOS. A successful Android build does not verify iPhone installation.

On a Mac with Xcode and Flutter's required iOS tools:

```sh
cd mobile
flutter pub get
flutter build ios --simulator --debug --no-codesign
open ios/Runner.xcworkspace
```

The simulator app is `build/ios/iphonesimulator/Runner.app`. Run it in a compatible simulator using Xcode or `flutter run -d SIMULATOR_ID`. Its `.app`/ZIP cannot be installed on a physical iPhone.

For a physical-device archive, select your own Apple development team and bundle identifier in Xcode, configure signing, then use Xcode's archive/distribution flow or:

```sh
flutter build ipa --release
```

No Apple account, certificate, provisioning profile, signed IPA or TestFlight publication is supplied or created here. See [Flutter's iOS deployment guide](https://docs.flutter.dev/deployment/ios) for signing and distribution.

## Rules, bot and verification

`lib/game/game.dart` ports `../lib/game.ts`: orthogonal movement, globally maximal compulsory captures, immediate removal of captured pieces, no 180-degree reversal, promotion after the complete turn, blocked-side wins, single-piece endings and repetition. `GameState` and `DamaMove` use the server's JSON field names and defensive snapshots.

`lib/game/bot.dart` ports the web opponent. Easy deliberately varies play. Medium/hard use bounded iterative deepening, alpha-beta search, transpositions and capture extensions. Search runs through `compute` in a background isolate; it has time/node limits and is heuristic. Earlier-turn repetition stays with the owning game state.

Tests cover rules, complete capture selection, tactical bot choices, seeded repeatability, isolate transfer, JSON, HTTP failures and session/race behavior. `test/parity_test.dart` checks native legal moves and full resulting state against committed canonical web-engine snapshots.

When changing shared web rules, regenerate that fixture from the repository root, then check both clients:

```sh
npm ci
npx tsx scripts/generate-mobile-fixtures.ts
npm test
cd mobile
flutter test
```

Native tests read the committed synthetic JSON and do not require Node.js or user credentials at test runtime.

### Local crossplay smoke test

Start the web backend with `npm run dev` from the repository root. In a second terminal, from `mobile/`, run:

```sh
dart run tool/crossplay_probe.dart --server http://localhost:3000
```

This retained tool uses the real Dart `DamaApi` and a browser-shaped HTTP client against the same server. It checks room creation in both directions, matching move state, spectators/capacity/chat, stale moves, draw agreement, scoring and rematches, then leaves its test rooms. Local development storage is sufficient; no Android emulator or CORS change is needed for this command-line check.

If that backend requires a shared password, supply `DAMA_SITE_PASSWORD` in the terminal environment; the tool does not print it. Live testing is opt-in: use `--server https://dama.ibrahim-eng.dev` only when intentionally creating temporary test rooms on production. This tool is not invoked by CI.

## Preferences and sessions

Names, server selection, room metadata and appearance are local preferences. Per-server player capability tokens use secure randomness and `flutter_secure_storage`; the backend receives them over HTTPS and stores their hashes. The room-entry password is passed when entering and is not persisted.

A token represents a seat rather than a recoverable account. Clearing app data or losing the installation can lose that seat. Credentials do not belong in build defines, screenshots, logs or Git.

The native board has an expanded focus view and coordinate/target preferences. A private local coach is toggled by holding the footer star for roughly 1.5 seconds. This convenience toggle is not an authentication boundary; analysis runs on-device and does not bypass online move validation.

## CI artifacts

[`../.github/workflows/mobile.yml`](../.github/workflows/mobile.yml) pins Flutter 3.38.0 and defines two independent jobs:

1. Ubuntu/JDK 17: dependency resolution, static analysis, tests and an Android debug APK.
2. macOS: an unsigned iOS simulator build, zipped with `Runner.app` metadata preserved.

It runs on relevant pushes/pull requests and can be started from **Actions → Native mobile → Run workflow**. Download successful-run artifacts from the run summary: `dama-android-debug` contains the development APK; `dama-ios-simulator` contains a simulator-only ZIP. Retention is fourteen days.

The workflow has read-only repository permissions and uploads explicit build outputs. It does not sign store releases, publish apps, use Redis/Apple secrets, or create live production rooms. Check an actual successful run before treating either platform build as verified.

Actions are pinned to verified release commits: [checkout](https://github.com/actions/checkout), [setup-java](https://github.com/actions/setup-java), [flutter-action](https://github.com/subosito/flutter-action), [upload-artifact](https://github.com/actions/upload-artifact).

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Friend's room cannot be found | Match the server URL and exact code. Rooms expire after 24 hours without a write/heartbeat. |
| Redis is required | Configure the web backend's Upstash REST credentials and redeploy it. Mobile carries no Redis credentials. |
| Password rejected | Use the room-entry password configured on that server. |
| Timeout/offline | Check the selected HTTPS endpoint and device connectivity, then retry. Accepted moves remain on the server. |
| Seat no longer recognized | The token or room may no longer be available; return to the lobby and create/join another room. |
| Android SDK/Java failure | Run `flutter doctor -v`; use JDK 17 and the Android SDK components required by the generated project. |
| APK update rejected | Package ID and signing key must match; CI debug keys are not a persistent distribution key. |
| iPhone rejects the CI ZIP | It is for an iOS simulator; an iPhone needs a correctly signed device build. |
