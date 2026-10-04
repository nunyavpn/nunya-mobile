# CLAUDE.md

Guidance for anyone changing this repository. The desktop app's `../nunya/CLAUDE.md` is the
source of the working rules below; desktop process, Tauri, and privilege details do not apply here.

## What this is

Nunya Mobile is a separate Flutter app for Android and iOS. One Dart UI serves both phones;
Android ships first. The VPN runs outside the UI lifecycle: Android owns it through `VpnService`,
and iOS through a `NEPacketTunnelProvider` extension. Xray is the planned engine; the Android and
Apple library bindings must be verified on devices before they are treated as settled dependencies.

`README.md` tells users and contributors what actually works. Do not describe a planned feature as
shipped. `design/` owns the source board, artwork, and light/dark screen references. Keep design
work there, and update the screenshots and their descriptions when a screen changes.

## Setup and checks

Run from the repository root:

| Task | Command |
| --- | --- |
| Get Dart packages | `flutter pub get` |
| Check Dart code | `flutter analyze` |
| Test Dart code | `flutter test` |
| Run Android | `flutter run -d <android-device>` |
| Run iOS | `flutter run -d <ios-device>` (macOS with Xcode and signing) |

A passing analyzer or widget test does not prove that the VPN works. Changes to tunnel setup,
permissions, routing, DNS, or native bindings need a real-device connect, traffic, network-change,
disconnect, and app-background check. Report checks that could not run and why.

## Boundaries

- `lib/` contains shared Dart UI, presentation state, and platform-neutral models. Build each screen
  once. Keep a small, typed tunnel interface between Dart and native code.
- `android/` will own the Kotlin `VpnService`, Android permissions and notifications, and its engine
  binding. `ios/` will own the Swift packet tunnel extension, entitlements, and its engine binding.
  Native code must own the tunnel even when the Flutter view is gone.
- The UI requests connect/disconnect and displays observed state. It never treats a successful
  button press as proof of a working tunnel. Only VPN mode may claim whole-device protection;
  proxy mode must say which traffic it covers.
- Import, config generation, DNS, and routing must have one documented owner. A share link or
  subscription that cannot run is rejected with a specific reason; never silently reinterpret it
  as a different protocol, transport, or security setting.
- Keep server credentials and subscription URLs out of logs, screenshots, and untrusted network
  requests. Persist them through the platform's protected storage; a corrupt store is an error,
  never a silent reset.
- Android's F-Droid build must be reproducible from source. Pin engine revisions and build the
  native library from that source rather than depending on an unexplained prebuilt AAR.

## Working rules from desktop Nunya

- Comments explain **why**, including important alternatives and platform constraints; avoid
  comments that merely repeat the code.
- Keep state changes in one direction. Widgets render state and send actions; they do not mutate
  saved profiles behind the state owner. Derive values from current state instead of caching copies.
- Split a module when it has more than one reason to change, not to meet a line-count target.
  Prefer small, local changes over speculative abstraction or a broad refactor alongside a feature.
- Test names describe behavior. Put focused tests under `test/`; use a real engine/device check for
  behavior a mock cannot establish.
- Keep all user-facing claims, UI copy, documentation, and screenshots consistent. In particular,
  connection state and traffic coverage must say what the OS and engine have actually established.
- Do not hand-edit generated build output. The checked-in Android and iOS project files are source
  and must be updated when platform integration requires it. Keep credentials out of git.
- For contributed changes, follow desktop Nunya's issue → `feature/`, `bugfix/`, or `hotfix/`
  branch → PR with `Closes #<n>` and verification → squash merge into `main` flow. `main` is the
  only long-lived branch.

## Current state

The repository has mobile screen designs and a Flutter app scaffold;
the native VPN bridges and Xray bindings are not implemented yet. A visual prototype must never
show a real connected state unless the platform reports one.
