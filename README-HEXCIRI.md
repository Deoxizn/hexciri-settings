# Hexciri Settings — fork notes

Fork of [ipkalid/omarchy-settings](https://github.com/ipkalid/omarchy-settings)
(master `ad54288`, v1.6.5), kept as a **plugin**, the way Omarchy does plugins
for system stuff. No bespoke app framework, no pane rewrites.

## What changed from upstream

- Renamed: `omasettings` → `hexciri-settings` everywhere (binary, paths
  `~/.config/hexciri`, `~/.local/share/hexciri-settings`, CLI calls
  `hexciri theme set`, `hexciri bar`, `hexciri plugin`, `hexciri-pkg-add`,
  `hexciri-launch-floating-terminal-with-presentation`).
- Manifest id `ipkalid.settings` → `deoxizn.settings`. (`hexciri.*` ids are
  reserved by `hexciri-plugin-validate` and would fail validation.)
- `kinds: ["service"]`, entry point `plugin/Service.qml`. No bar widget:
  enabling builds the app and adds it to the app launcher; launch it from
  there or with Super+Ctrl+S.
- Update channel removed (Hexciri has no release channel; updates follow the
  nyx branch). Herdr theme-sync toggle removed.
  `hexciri-launch-config-editor` → `hexciri-launch-editor`.
- Extra-panes hook (Nyxiri tab later, hook only for now): `Store::list("extraPanes")`
  reads `~/.config/hexciri/settings-panes/*.json`
  (`{id, title, glyph, group, keywords, qml}`), Main.qml appends them to the
  sidebar and loads the pane QML from the file path. Managed with
  `hexciri-settings-tabs add|list|remove`.
- Qt 6.12 fix: `src/store.cpp` passes `readFile(...).toUtf8()` to
  `QJsonDocument::fromJson` (it takes QByteArray, not QString). All other
  `fromJson` calls in `src/` already pass QByteArray.
- `plugin/install` is loud on qmake failure now: qmake output goes to the
  build log, the tail prints on failure, and a missing qmake6 or .pro dies
  with a clear message instead of silently exiting under `set -e`.
- Icon is still the upstream gear placeholder
  (`pkgbuild/hexciri-settings.svg`); Devi supplies the exact icon later,
  swap that one file.

## Install

The Hexciri installer does this on every update until the binary exists and
is current — no manual build command:

```bash
hexciri plugin add https://github.com/Deoxizn/hexciri-settings --enable --yes
bash ~/.config/hexciri/plugins/deoxizn.settings/plugin/install --quiet
```

`hexciri update` retries a failed build automatically on the next run; the
build log is `~/.cache/hexciri-settings-build/build.log`. Updates after that
come through `hexciri plugin update deoxizn.settings` (or the Plugins &
Themes row in the arch-updates bar panel); Service.qml rebuilds on update.

## Tests

`tests/` is the upstream testcase, renamed to `hexciri-settings_tests.*`.
