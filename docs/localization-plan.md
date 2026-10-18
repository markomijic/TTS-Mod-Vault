# Plan: support for additional languages

Written 2026-10-18 against `v3-rewrite` at `1827462`. Audience: whoever
implements it. Everything below was checked in the code at that commit; verify
file paths before editing, they may have moved.

## 1. Where the code stands

The string layer is done. What is missing is everything above it.

Done:

- Every user-facing string goes through ARB. `lib/l10n/app_en.arb` holds 583
  messages, 127 with placeholders, 26 ICU plurals, each with a `description`.
  `flutter gen-l10n` writes `lib/l10n/generated/` (git-ignored) from
  `l10n.yaml` (`synthetic-package: false`, `nullable-getter: false`).
- No literal UI strings remain in widgets. The only literal is the window title
  in `lib/bootstrap/bootstrap.dart` (`'TTS Mod Vault ${info.version}'`), which
  is the product name and stays.
- Enum titles (`lib/features/library/presentation/library_labels.dart`), sort
  and filter labels, operation progress labels
  (`lib/features/operations/presentation/operation_labels.dart`, keyed strings
  mapped to `AppLocalizations`, English `humanizeLabelKey` fallback) and all
  dialogs resolve through `AppLocalizations`.
- `lib/app/app.dart` already uses `AppLocalizations.delegate` plus
  `GlobalMaterialLocalizations.delegates` from `package:material_ui` (not
  `flutter_localizations`; material_ui ships its own `MaterialLocalizations`
  type). Framework strings therefore translate for free once a locale is
  supported.

Missing:

- No language setting. `AppSettings` has no locale field; `MaterialApp` has no
  `locale:`; `supportedLocales` is the generated list, which contains only
  `en`.
- `modDateFormat` in `lib/features/library/presentation/mod_badges.dart` is a
  top-level `final DateFormat = DateFormat.yMMMd().add_Hm()`, built once with
  the default locale. It would not follow a user-chosen language. It is used by
  `mod_badges.dart`, `backup_badges.dart`, `backup_grid_card.dart`.
- `lib/domain/parsing/mod_metadata.dart` uses `DateFormat('M/d/yyyy h:mm:ss a')`
  and `'MM/dd/yyyy HH:mm:ss'` to parse the dates TTS writes into mod files.
  Those must stay fixed to `en_US` regardless of UI language.
- `assets/text/help.md` (678 words) and `assets/text/changelog.md` are single
  English assets, loaded by `lib/features/about/presentation/help_dialog.dart`
  (`helpAssetPath`, `changelogAssetPath`) and rendered by `simple_markdown.dart`.
- The ~110 log messages (`_log.info/warning/error(LogSource..., '...')`) are
  English and go both to the log panel and to `vault.log`.
- Layout was never checked with longer text. German and Russian run ~30 %
  longer than English; the window minimum is 854 x 480.
- 15 places use `EdgeInsets.only(left:/right:)`, `Alignment.*Left/Right` or
  `TextAlign.left/right` instead of directional variants; none use
  `EdgeInsetsDirectional`/`AlignmentDirectional`. Only matters for RTL.
- Tests: 676 `find.text('...')` assertions use English literals and 11 test
  files reference `AppLocalizations`. Tests run in `en` and should keep doing
  so.

## 2. Phase A: make the app language-aware (no translation yet)

About one to two days. Ships in 3.0, before the release; nothing changes for English users.

### A1. Language setting

- Add a nullable `locale` field (`String?`, BCP 47 tag such as `de`, `pt-BR`)
  to `AppSettings` in `lib/features/settings/application/app_settings.dart`.
  `null` means "follow the system". Persist it through the existing settings
  path (`SettingsController`, JSON in the kv store). The 2.x importer leaves it
  null; nothing to import.
- Settings dialog, Interface section
  (`lib/features/settings/presentation/interface_section.dart` or wherever the
  view toggles live): a dropdown "Language" with "System default" plus each
  supported locale shown by its native name ("Deutsch", "Hrvatski", ...), not
  its English name. The native names are a small hand-kept map; they are not in
  the ARB because each name is written in its own language.
- "Reset to defaults" resets it to null.

### A2. Wire it into MaterialApp

In `lib/app/app.dart`:

- `locale:` from the settings provider (`null` keeps the system locale).
- `supportedLocales: AppLocalizations.supportedLocales` stays; it grows
  automatically as `app_<locale>.arb` files are added.
- `localeResolutionCallback` that picks the closest supported locale: exact
  match, then language-only match (`pt_BR` -> `pt` if only `pt` exists, or the
  reverse), then `en`.
- Consider `onGenerateTitle` is already localised; nothing to do there.

### A3. Dates follow the locale

- Replace the global `modDateFormat` with a helper that takes the locale from
  the tree, e.g. `DateFormat.yMMMd(Localizations.localeOf(context).toString())
  .add_Hm()`, cached per locale (a tiny `Map<String, DateFormat>` is enough;
  building a `DateFormat` is not free and the grid builds many cards).
  `intl` date symbols for the supported locales are loaded by the
  `GlobalMaterialLocalizations` delegate, so no `initializeDateFormatting`
  call is needed; verify once with a non-English locale.
- Pin `mod_metadata.dart` to `DateFormat('...', 'en_US')` explicitly and add a
  comment that these parse TTS file content, not UI text.
- `lib/core/logging/log_entry.dart` formats timestamps without intl; leave it.

### A4. Guard rails

- `l10n.yaml`: add `untranslated-messages-file: build/untranslated.json` so
  every `flutter gen-l10n` run lists the keys each locale lacks. Flutter falls
  back to the template (English) for a missing key, so a partial translation
  never crashes; this file is how you measure completeness.
- New test `test/l10n/arb_consistency_test.dart`: for every `app_*.arb` in
  `lib/l10n/`, the set of message keys is a subset of the English keys (no
  stale keys), and for each shared key the placeholder names match the English
  `@key.placeholders`. Mismatched placeholders are the one translation error
  that breaks at runtime.
- Optional: a test that no `app_<locale>.arb` message is byte-identical to the
  English one, reported as a warning list, to catch strings left untranslated
  by copy-paste.

### A5. Long-text pass (throwaway)

Before any real translation, find layout bugs once:

1. Generate a temporary `lib/l10n/app_xx.arb` from `app_en.arb` with every
   message padded to ~1.3x its length (keep placeholders and ICU syntax intact;
   pad only the literal text parts). A 20-line Dart or Python script.
2. Run the app with that locale forced, at the 854 x 480 minimum and at a
   normal size. Check: sidebar labels, toolbar buttons and the tab selector,
   dialog action rows, the selected-mod panel header, the settings dialog, the
   log panel header, snack bars.
3. Fix overflows with `Flexible`/ellipsis/wrapping as appropriate, never by
   shortening the English.
4. Delete `app_xx.arb`; do not commit it. Note in this file which widgets were
   changed.

## 3. Phase B: first language and the help text

Pick one pilot language someone on the project reads fluently; the first
translation is what finds the structural problems (strings that assume English
word order, plurals that need more categories, labels too terse to translate).
Croatian if the maintainer reviews it himself; otherwise German, the largest
non-English share of the TTS community.

- **ARB.** `lib/l10n/app_<locale>.arb` with `@@locale`. 583 strings is roughly
  4,500 English words. A machine first draft reviewed by a fluent speaker is
  about a day of review; from scratch, two to three days. Whenever the reviewer
  has to ask what a string means, fix the English `description` so later
  languages do not hit the same question.
- **Help text.** Load `assets/text/help_<locale>.md` when it exists, else
  `help.md`. Implement as: try the locale-specific asset, catch the
  `FlutterError` from `rootBundle.loadString`, fall back. Register the new
  files under `flutter: assets:` in `pubspec.yaml` (the whole `assets/text/`
  folder is probably already listed; check). The changelog stays English only;
  add one translated line in the Changelog tab saying so.
- **Logs stay English.** `vault.log` is what users attach to bug reports and
  what the maintainer reads; translating it would make reports harder to read
  and double the translation surface. The log panel's controls, filters and
  "Open log file" are already in the ARB.
- **Credits.** A `TRANSLATORS.md` at the repo root and an entry in the About
  tab (one ARB string with a placeholder, or read the file as an asset).
- **Release notes.** A "Languages" line in `docs/v3-release-notes-*.md`, the
  in-app changelog and the Nexus description.

## 4. Phase C: community translations and the long tail

- **Contribution path.** `docs/translating.md`: ARB format, placeholders and
  plurals with one example each, how to run `flutter gen-l10n` and the
  consistency test, and the shipping rule below. Pull requests are enough to
  start. Move to Weblate or Crowdin only with three or more active languages;
  both read ARB directly, and because the generated code is git-ignored the
  switch costs nothing later.
- **Shipping rule.** A locale is added to the app when its untranslated list
  is under 10 % of keys. Below that the English fallbacks are too visible.
- **Right-to-left.** Nothing until an RTL language is requested. Then convert
  the 15 left/right usages to `EdgeInsetsDirectional`, `AlignmentDirectional`,
  `TextAlign.start/end`, and run with Arabic to check the custom widgets.
  Material widgets mirror by themselves.
- **Fonts.** The theme sets no body font family (`fontFamily` appears twice in
  `lib/`, check what they are), so CJK and Cyrillic render with OS fonts on all
  three desktops. If a custom font is ever added for the Classic preset, keep
  it off body text or add `fontFamilyFallback`.
- **Sorting.** Mod names use plain string comparison. Fine for Latin scripts,
  acceptable elsewhere; Dart has no built-in collator and mod names are mostly
  English regardless of UI language. Leave it.

## 5. Order and effort

| Step | Effort | Target |
| --- | --- | --- |
| A1 to A4 | 1 day | 3.0 |
| A5 long-text pass | half a day | 3.0 |
| Pilot ARB + help text (B) | 2 to 3 days incl. review | 3.0 |
| Contribution doc, credits | half a day | 3.0 |
| Hosted translation platform | half a day | when three languages exist |

All of A, B and the contribution doc from C ship in 3.0. Phase A depends on
nobody and starts now; B needs a decision on the pilot language and who
reviews it. Only the hosted platform and RTL wait for demand.

## 6. Definition of done for Phase A

- `flutter analyze` clean, `flutter test` green (the English tests unchanged).
- Settings shows a Language dropdown; choosing "System default" or a locale
  persists across restarts.
- With a temporary `app_xx.arb` present, the app switches to it at runtime and
  dates on cards change format with it; with the file deleted, nothing in git
  references it.
- `build/untranslated.json` is produced by `flutter gen-l10n`.
- `test/l10n/arb_consistency_test.dart` exists and passes.
- This file's section 2 updated with anything that turned out differently.
