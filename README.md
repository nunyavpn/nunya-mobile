# nunya-mobile

Nunya for phones: Android first, iOS after.

[Nunya](https://github.com/nunyavpn/nunya) is a desktop VPN client for
[nunya-core](https://github.com/nunyavpn/nunya-core). This repository is its phone app, a project of
its own and not a port of the desktop window. Its Android and iOS screens share one Flutter/Dart
codebase. Each platform supplies its own VPN integration: `VpnService` on Android and a packet
tunnel extension on iOS. The planned engine is Xray, built as a native library for each platform;
the exact bindings still need to be proved on devices.

## Decisions so far

- **Separate from the desktop repository.** nunya stays desktop-only (macOS, Linux, Windows); the
  phone apps are here.
- **One mobile UI.** Flutter owns the shared screens and presentation state. Native services own
  tunnel setup and engine lifetime, including when the app UI is closed.
- **An Xray-based mobile engine.** AndroidLibXrayLite and libXray are candidates for Android and
  iOS respectively. Their source builds, tunnel integration, and protocol coverage need validation
  before either is pinned. The desktop `nunya-core` executable is not the mobile runtime.
- **Android is released first, through F-Droid.** It is built from source, so nothing here can
  depend on a prebuilt binary F-Droid cannot rebuild. The repository is mirrored to GitLab
  (`nunya-vpn-group`) for that.
- **iOS is built but not released yet.** A VPN app on the App Store needs an Apple Developer
  account enrolled as an organization (App Store guideline 5.4).
- **Honest about coverage.** As on the desktop, proxy mode never claims to cover the whole phone;
  only VPN mode may say "You're protected".

## Design

[design/](design/README.md) has every screen, light and dark: Home (the connection as a sheet over
the map), Servers, the sheets that rise from the bottom, and Settings.

## Development

The app is at the scaffold stage; a working VPN is not implemented yet. With Flutter installed,
run `flutter pub get`, `flutter analyze`, and `flutter test` from this directory. Use
`flutter run` with an Android or iOS device to open the app.

## License

GPL-3.0, like nunya and nunya-core.
