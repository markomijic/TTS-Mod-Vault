# Translating TTS Mod Vault

The app's text lives in one file per language in `lib/l10n/`. English
(`app_en.arb`) is the template; a translation is a copy of it with the
messages translated. You need a text editor and a pull request; running the
checks below needs the Flutter SDK, but a draft without them is still welcome
and a maintainer can run them for you.

## What gets translated

| What | Where | Translated? |
| --- | --- | --- |
| Every button, label, dialog, tooltip and message in the app | `lib/l10n/app_<locale>.arb` | Yes |
| The Help tab | `assets/text/help_<locale>.md` | Yes, optional (English is shown without it) |
| The Changelog tab | `assets/text/changelog.md` | No, English only (the app says so) |
| The log panel entries and `vault.log` | in the code | No: bug reports have to stay readable for the maintainer |
| Product name "TTS Mod Vault", file names, URLs | | No |

The names of the Material widgets (date pickers, "Cancel" in system dialogs
and so on) come from the framework. Before starting a language, check that
`GlobalMaterialLocalizations` supports it (the languages listed in the
Flutter `flutter_localizations` package); the app cannot show a language the
framework does not know.

## 1. Create the file

Copy `lib/l10n/app_en.arb` to `lib/l10n/app_<locale>.arb`, where `<locale>` is
a language code (`de`, `hr`) or a language and country (`pt_BR`). Then:

- Add `"@@locale": "<locale>"` as the first entry (use `pt_BR`, with the
  underscore, for a regional file). The test checks that it matches the file
  name.
- Delete every `"@key"` entry. Those are descriptions and placeholder
  declarations; they stay in the English file only. You can keep them while
  working, they are ignored, but the file is easier to read without them.
- Translate the values of the message entries. Do not rename any key.
- Messages you leave out show in English, so a partial translation never
  crashes. Delete a key rather than copying the English text into it.

Read the `description` of an entry in `app_en.arb` whenever a string is
unclear: it says where the text appears. If it still does not tell you, ask in
the pull request; the English description will be fixed so the next translator
does not hit the same question.

## 2. Placeholders

A word in curly braces is replaced by the app. Keep it exactly as written, and
move it where your grammar needs it:

```json
"settingAssetUrlFontSizeInfo": "Range: {min}-{max}. Default: {defaultSize}.",
```

```json
"settingAssetUrlFontSizeInfo": "Bereich: {min}-{max}. Standard: {defaultSize}.",
```

A message must use exactly the placeholders of the English one: a misspelled
or missing placeholder breaks at runtime, and it is the one mistake the test
below exists to catch.

## 3. Plurals

Counted messages use the ICU plural syntax. English has the forms `=1` (or
`one`) and `other`:

```json
"backupTooltipAssets": "{count, plural, =1{1 asset in backup} other{{count} assets in backup}}",
```

Write the forms your language needs. Many languages need more than English
(`zero`, `one`, `two`, `few`, `many`, `other`; Croatian and Russian use `one`,
`few`, `other`). `other` is always required:

```json
"backupTooltipAssets": "{count, plural, one{{count} datoteka u sigurnosnoj kopiji} few{{count} datoteke u sigurnosnoj kopiji} other{{count} datoteka u sigurnosnoj kopiji}}",
```

Keep the `{count, plural, ...}` frame; only the text inside the braces is
yours.

## 4. Register the language

- Add the language's own name to `nativeLanguageNames` in
  `lib/l10n/locale_tags.dart` (`'de': 'Deutsch'`): the language dropdown in
  Settings lists each language in itself, and shows the bare code without an
  entry.
- Add a line to `TRANSLATORS.md` to be credited in the About tab:
  `- de: Your Name`.

## 5. Check it

```
flutter gen-l10n
flutter test test/l10n
```

`flutter gen-l10n` regenerates the code and writes `build/untranslated.json`,
which lists the keys each language still lacks. The tests check that your file
has no keys the English file lacks, that every message uses the same
placeholders as English, and print the messages that are still identical to
English. To see the result, run the app and pick the language in
Settings > Interface > Language.

Mind that translations are usually longer than English (German and Russian by
about 30 %). If a label is cut off or overflows somewhere, report it in the
pull request: the layout is fixed in the code, not by shortening the text.

## 6. The help text (optional)

Copy `assets/text/help.md` to `assets/text/help_<locale>.md` (`help_de.md`,
`help_pt_BR.md`) and translate it. The app loads `help_<language>_<country>.md`,
then `help_<language>.md`, then falls back to `help.md`.

## When a language is added to the app

A language ships once less than 10 % of its keys are untranslated
(`build/untranslated.json`); below that the English fallbacks are too visible.
Until then it can live in a pull request or a branch. After it ships,
untranslated keys are added to the English file with every release; the
untranslated list says which ones are new.

Pull requests are enough for now. When three or more languages are being
maintained, a hosted platform that reads ARB directly (Weblate, Crowdin) is
the next step.
