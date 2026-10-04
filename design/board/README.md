# The design board

The source the screens in [`../screens/`](../screens/) were rendered from. It is a page for the
desktop app's development server: it reads the desktop app's colour tokens, icons, flags and map
straight out of [nunya](https://github.com/nunyavpn/nunya)'s `src/`, so the design used the real
parts. That means it does not run on its own here.

To open it again, it was rendered from nunya's commit
[`ea1944d`](https://github.com/nunyavpn/nunya/commit/ea1944dbfad1a365b522e1887ac627ad6f727fab),
which carries it as `design/mobile/`:

```bash
git -C nunya checkout ea1944d   # a nunya clone
cd nunya && npm install && npm run design
# then open http://localhost:1421/design/mobile/
```

Once this app has its own UI code, the board moves onto it, and the screens are retaken from that.
