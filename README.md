# nunya-mobile

Nunya for phones: Android first, iOS after.

[Nunya](https://github.com/nunyavpn/nunya) is a desktop VPN client for
[nunya-core](https://github.com/nunyavpn/nunya-core). This repository is its phone app, a project of
its own and not a port of the desktop window. It is built directly on nunya-core's mobile library
(gomobile: an `.aar` on Android, an `.xcframework` on iOS), so the core runs inside the app and the
system's own VPN API carries the tunnel: `VpnService` on Android, a packet tunnel extension on iOS.

## Decisions so far

- **Separate from the desktop repository.** nunya stays desktop-only (macOS, Linux, Windows); the
  phone apps are here.
- **The core does the work.** What the desktop app does in its own code (generating the tunnel
  config, reading share links and subscriptions) belongs in nunya-core's mobile library, so it is
  written once and both clients use it.
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

## License

GPL-3.0, like nunya and nunya-core.
