# Port spec: 2.x "download validation and domain checks" into 3.0

Written 2026-10-23 on `v3-rewrite` at `ac0f9a8`. Audience: the session that
implements the port. Status: analysis done, nothing ported yet, one product
decision open (section 4).

## 1. Where it comes from

Commit `051741c` on `main` ("Add download validation and domain checks",
author flash201524, 2.x only, no version bump; the only commit on `main`
since the rewrite branched). It was merged into `v3-rewrite` as `6629c9e`
with every `lib/src/` file kept deleted (`1113c5a` removed the two new 2.x
files the merge had added), so `git log` carries it but no 2.x code exists on
the branch. Read the original with:

```sh
git show 051741c --stat
git show 051741c:lib/src/state/download/download.dart          # the logic
git show 051741c:lib/src/mods/components/download_validation_dialog.dart
git show 051741c:lib/src/state/download/download_validation_result.dart
```

A 2.x debug build with the feature was made on 2026-10-18 for the user to
try: `D:\Dev\TTS-Mod-Vault\build\windows\x64\runner\Debug\tts_mod_vault.exe`
(from the `main` checkout; needed `pdfrx_engine` bumped to 0.4.7 in the
lockfile to compile on Flutter 3.47.7).

## 2. What 2.x does (behaviour to reproduce)

1. **Domain reachability check.** For a set of URLs, take one representative
   per unique host (lower-cased). For each host try, in order: `https://host/`,
   `http://host/`, the representative URL; each candidate with `HEAD` then a
   one-byte ranged `GET`, 10 s timeouts, redirects not followed. *Any* HTTP
   response (403, 404, 5xx included) means reachable; only connection-level
   failures mean unreachable. Results are cached in memory for one minute
   (bypassed with `forceRefresh`). Concurrency = the "concurrent downloads"
   setting. Progress text "Checked N/M domains". Cancellable.
2. **URL check (existing feature) gains the reachability step.** Before URLs
   are classified, the domains of all the mod's assets are checked; URLs on
   unreachable hosts are skipped and *not* marked invalid, the rest go through
   the existing liveness check. The persisted invalid list is only updated when
   no domain was unreachable. Results carry `unreachableDomains` next to
   `invalidUrls`; the single-mod dialog titles itself "URL Check Complete with
   Unreachable Domains" and lists them; the bulk dialog shows
   "Domains unreachable: N" and per-mod "(N invalid, N unreachable)".
   The bulk URL check passes `forceDomainRefresh: false` (uses the 1-minute
   cache across mods); the single check forces a refresh.
3. **Post-download validation.** After a single mod download, a multi-select
   download, "Download all", "Download & backup all" and multi-select download
   and backup: assets still missing after the download are run through the
   reachability check, then the liveness check for URLs on reachable hosts.
   Saved objects are skipped. If nothing is missing, the persisted invalid list
   is cleared. A "Download check results" dialog appears only when something
   is unreachable or invalid: section "Domains unreachable" (orange, "could
   not be reached from the current network; their resources were not marked
   invalid") and section "Invalid resources" (red, "domains are reachable but
   these resource URLs are invalid"), grouped per mod with the URL lists
   selectable. Bulk runs collect one result per mod and show one dialog at the
   end. A cancelled check returns an empty result and shows nothing.
4. **Completion rule.** `isDownloadComplete` = no missing assets, or every
   missing asset's URL is in the persisted invalid list.
   `missingInvalidAssetCount` = number of distinct missing URLs that are
   invalid. Cards and list rows show the "complete" indicator with the tooltip
   "All available assets downloaded\nN invalid resource URL(s)" instead of the
   missing badge. (In 2.x this also means such mods no longer look like they
   need a download.)
5. **Settings, Network section.** Button "Check all Mods and Saves domains"
   (spinner + "Checking domains..." while running) over every unique domain in
   the cached URL lists of Mods and Saves, including domains on the ignore
   list; opens a "Domain reachability results" dialog: "N reachable, N
   unreachable (N total)" or "No domains were found in Mods or Saves", then a
   list sorted unreachable-first with a check/cross icon and the word
   Reachable/Unreachable, domain names selectable.
6. **Persistence.** Per mod: invalid URL list + the mod file's modification
   timestamp; dropped when the mod JSON changes.
7. Download retry/backoff, 60 s receive timeout, scheme resolution for
   scheme-less URLs: v3 already has all three (`lib/data/net/asset_downloader.dart`,
   `url_checker.dart`); nothing to port.

## 3. What v3 already has, and where each piece lands

| 2.x piece | v3 today | Where to put the port |
| --- | --- | --- |
| Liveness check `isUrlLive` | `UrlChecker.isLive` in `lib/data/net/url_checker.dart` (HEAD, ranged GET, HTML-page detection) | unchanged |
| Reachability check | nothing (grep `reachab` finds only ignored-domain settings) | new `DomainReachabilityChecker` in `lib/data/net/`, injected like `UrlChecker`; pure Dart, unit-tested against a local `HttpServer` like `url_checker_test.dart` |
| Persisted invalid URLs | `mods.invalid_urls_json` column, `ModsDao.setInvalidUrls`, `Mod.invalidUrls`, `Asset.invalid` | unchanged; already dropped on re-parse |
| URL check operation | `lib/features/downloads/` (`checkUrlsProgressLabel`) and the bulk variant in `lib/features/bulk/` | add the reachability step first, add `unreachableDomains` to the result types, skip those URLs, only persist when none unreachable |
| Post-download validation | nothing | a `ValidateDownloadOperation` in `lib/features/downloads/application/`, composed after the download operation (single, multi-select, bulk download, bulk download+backup); results collected by the launcher and shown once |
| Results dialog | nothing | `lib/features/downloads/presentation/download_validation_dialog.dart`, strings in `app_en.arb` (+ `app_hr.arb`), built on `AppDialog` |
| Completion rule | `AssetSummary.isComplete`, `Mod.missingCount` (`lib/domain/models/`) | decision in section 4; implement in `AssetSummary`/`Mod` so cards, list rows and the `missingAssets` filter all follow it |
| Settings button | Network section exists (`lib/features/settings/presentation/`) | button + "Domain reachability results" dialog; the operation runs through `OperationRunner` so the progress bar and cancel work, with its own label key in `operation_labels.dart` |
| Domain set for the Settings button | `LibraryQueries` can list all asset URLs of mods + saves | one DAO query returning distinct hosts |
| Concurrency | `NetworkOptions.concurrentDownloads` | reuse |

Rules that apply: everything through `OperationRunner` (one operation at a
time, `CancellationToken`), label keys mapped in `operation_labels.dart`,
strings in ARB with descriptions, log lines through `AppLog` (`LogSource.net`
or whichever exists) so the log panel explains "domain X unreachable" and
"URL Y invalid", tests for the checker, the operation and the summary rule.

## 4. Open decision (ask the user before implementing the completion rule)

2.x now treats a mod whose only missing assets are known-invalid URLs as
complete: the missing badge disappears and the tooltip says "All available
assets downloaded, N invalid resource URL(s)".

Options for 3.0:

- (a) Same as 2.x: `isComplete` becomes "missing == 0 or all missing are
  invalid"; the missing-assets filter stops matching such mods; the badge
  shows the invalid count.
- (b) Keep "missing" strict: the badge keeps showing N missing, with the
  invalid count next to it ("3 missing, 3 invalid"); the filter keeps matching;
  nothing is hidden, the user still sees that the mod cannot be completed.

Also to confirm: should post-download validation be always-on as in 2.x, or a
setting (default on)? It adds one request per unique domain plus one per
still-missing URL after every download.

## 5. Suggested order

1. `DomainReachabilityChecker` + tests (pure data layer, no UI).
2. Reachability step in the existing URL check (single + bulk) + result types
   + dialog changes + ARB strings + tests.
3. `ValidateDownloadOperation` + the results dialog + wiring into the four
   download entry points + ARB + tests.
4. Completion rule per the user's answer + card/list/filter updates + tests.
5. Settings button + domain results dialog + DAO query + tests.
6. `assets/text/help.md` (and `help_hr.md`) and `changelog.md`: describe the
   reachability behaviour and the Settings button. Update
   `docs/v3-parity-audit.md` with the new rows.

Estimate: half a day to a day with subagents on 1, 3 and 5 in parallel (the
user asked for Opus subagents).
