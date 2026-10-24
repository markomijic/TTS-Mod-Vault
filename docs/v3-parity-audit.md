# v3 feature-parity audit (Phase 6)

Audit of `docs/v3-rewrite-plan.md` section 7 against the v3 code at `39905ce`
plus the fixes listed below, with the v2 code under `lib/src/` as the reference.
Every line was verified by reading the implementing v3 code and its tests, not
by running the app.

Result: **28 done, 0 partial, 0 missing.** Rows 29-31 were added on 2026-10-24 for the port of the 2.x download validation (`docs/v3-download-validation-port.md`). The one partial item found by the
audit (reduced context menu on images-viewer and PDF tiles) and the smaller
observations were listed under "Gaps needing work"; all four gaps have since
been closed (that section records what was done), followed by the keyboard
and light-theme passes of Phase 6 (sections at the end).

Paths below are relative to `v3/lib/`.

## Checklist

| # | Checklist line | Status | Implemented in | Notes |
| --- | --- | --- | --- | --- |
| 1 | Mods / Saves / Saved Objects (setting) tabs with counts tooltip | done | `features/library/presentation/toolbar/library_tab_selector.dart` (`LibraryTabSelector`), `features/library/application/library_tab.dart` (`availableLibraryTabsProvider`, `LibraryTabController`) | Saved Objects only with `showSavedObjects`; Backups tab only when a backups folder is set (`Directories.hasBackupsDir`). Switching clears selection and search as in 2.x. Tooltip lists "N mods, N saves, ..." and, since G4, leaves out empty kinds (no tooltip when everything is empty), as v2 did. Tests: `library_page_test`, `backups_view_test`. |
| 2 | Grid and list views (settings), title-on-cards setting | done | `mods_view.dart`, `mods_grid.dart`/`mods_grid_card.dart`, `mods_list.dart`/`mods_list_item.dart`, `toolbar/view_toggle_button.dart`; backups: `features/backups/presentation/backups_view.dart` | `useModsListViewSettingProvider`, `useBackupsListViewSettingProvider`, `showTitleOnCardsSettingProvider`; saves always show the title band (file name + name) as in 2.x. Grid card has no sync file check (image via `Mod.imagePath` + `errorBuilder`). |
| 3 | Sort: A-Z, newest, recently updated, missing assets; default sort setting (mods and backups) | done | `toolbar/sort_menu_button.dart`, `features/library/application/library_view_providers.dart` (`filteredModsProvider`), `features/settings/presentation/settings_defaults_applier.dart`, `interface_section.dart` | Non-name sorts tie-break by name; `newest` falls back to mtime when the JSON has no date. Default sorts applied once on mount and again on Save when changed (`SettingsDialog._applyEffects`). Tests: `library_view_providers_test`, `settings_defaults_applier_test`, `settings_dialog_test`. |
| 4 | Filters: folders, backup state, complete/missing, audio/image/model/PDF/asset bundle presence | done | `toolbar/filter_menu_button.dart`, `ModFilterController` | Folder sets remembered per type; missing/complete exclude each other; backup-state section hidden when `showBackupState` is off (as v2). **Fixed:** switching the setting off now also drops active backup-status filters (v2 did; v3 left them silently applied). |
| 5 | Search mods by name; search assets of selected mod | done | `toolbar/library_search_field.dart`, `features/asset_detail/presentation/asset_toolbar.dart` (`AssetSearchField`) | Debounced; Ctrl/Cmd+F focuses the mod/backup search, Esc clears selection or unfocuses (`LibraryPage`). Tests: `library_page_test`, `backups_view_test`, `selected_mod_panel_test`. |
| 6 | Single and Ctrl/Cmd multi-select | done | `features/library/presentation/item_interaction_region.dart`, `mod_interaction_region.dart`, `backup_interaction_region.dart`, `SelectionController` | `HardwareKeyboard.isControlPressed || isMetaPressed` toggles; right click selects + menu; ignored while an operation runs. Multi-select panel: `features/asset_detail/presentation/multi_select_view.dart`. |
| 7 | Selected mod: grouped assets, type chips, downloaded/missing filter, invalid filter, PDF thumbnails toggle + default setting, images viewer, open files (audio/image/PDF), open in file explorer | done | `selected_mod_view.dart`, `asset_toolbar.dart`, `asset_list.dart` (`AssetGroupHeader`, `PdfGridRow`), `pdf_thumbnail.dart`, `features/images_viewer/presentation/images_viewer_page.dart`, `asset_file_actions.dart` | Everything listed is reachable: chips from the unfiltered list, status menu, Invalid chip, PDF thumbnails/URLs header toggle seeded from `showPdfThumbnails`, images viewer from the Images header icon **and** the mod context menu, open file via `open_filex`, reveal in explorer. **Fixed (G1):** the right-click menu on image tiles and PDF thumbnails is now the full asset menu (`showAssetContextMenu`), as in v2; the reduced `showAssetFileMenu` is gone. |
| 8 | Asset actions: open URL, copy URL, replace URL (with optional file rename), delete file, shared-with info | done | `features/asset_detail/presentation/asset_context_menu.dart`, `replace_url_dialog.dart`, `features/library/application/mod_edit_service.dart` | Download only for missing files, Open/Reveal/Delete only for files on disk. **Fixed:** "Copy filename" (v2 item) added; copies the cached name without extension, or the TTS name of the URL when missing. Tests: `selected_mod_panel_test`, `asset_detail_helpers_test`, `mod_edit_service_test`. |
| 9 | Per-mod audio visibility override + global ignore-audio setting | done | `asset_toolbar.dart` (`AudioVisibilityButton`), `ModEditService.setAudioVisibility`, `features_section.dart` (`settingIgnoreAudio`) | Button only when the mod references audio; tinted while overriding; menu of the three choices with the global state in the label. |
| 10 | Download missing assets (single asset, per type, whole mod); concurrency setting; ignored domains | done | `features/downloads/presentation/download_actions.dart`, `features/downloads/application/download_assets_operation.dart`, `network_options.dart`, `network_section.dart` | `downloadAsset` / `downloadType` / `downloadMod`; `concurrentDownloads` and `ignoredDomains` passed to the downloader. Results dialog on failures/cancel. Tests: `download_wiring_test`, `download_assets_operation_test`. |
| 11 | Check URLs for a mod, persist invalid URLs; bulk check with results dialog | done | `check_urls_operation.dart` (`setInvalidUrls`), `url_check_results_dialog.dart`, `features/bulk/presentation/bulk_url_check_results_dialog.dart` | Invalid list replaces the stored one (empty clears). **Changed (G3):** the asset-menu single-URL check is now a one-asset `CheckUrlsOperation` on the runner (progress bar + Cancel) that merges its outcome into the stored invalid list. |
| 12 | Download Workshop mods by one or many ids; update from Workshop (single, bulk, force) | done | `features/workshop/presentation/download_workshop_mods_dialog.dart`, `workshop_id_parser.dart`, `update_from_workshop.dart`, `bulk_actions.dart` (`runBulkUpdateWorkshop`) | Ids or item URLs, target folder picker; "Force update" checkbox on the confirmation; context-menu item disabled for non-numeric ids (v2 showed it regardless). |
| 13 | Backup create (folder picker, default folder, set-as-default), replace prompt, progress | done | `features/backups/presentation/backup_actions.dart` (`backupMod`), `features/backups/application/backup_service.dart` | No default folder → picker + "use as default" checkbox; existing archive or backup elsewhere → Cancel / Select new folder / Replace; progress through the operations engine. Tests: `backup_mod_test`, `backup_service_test`. |
| 14 | Backup status: none / up to date / out of date / asset count mismatch, with tooltip times | done | `domain/rules/backup_rules.dart`, `features/library/presentation/mod_badges.dart` (`backupTooltip`, `BackupStatusBadge`) | **Fixed:** tooltip now shows the mod's save date (falls back to the file mtime) next to the backup date, as v2's "Update: / Backup:" lines did; asset count and the mismatch line as before. Test: `mod_badges_test`. |
| 15 | Backups tab: browse, sort, filter, search, import, open, copy filename, delete | done | `backups_view.dart`, `toolbar/backup_sort_menu_button.dart`, `backup_filter_menu_button.dart`, `backup_search_field.dart`, `backup_context_menu.dart`, `selected_backup_panel.dart`, `library_view_providers.dart`/`backup_view_providers.dart` | Sort name/size/date both ways; folder and has-matching-mod filters; copy filename without `.ttsmod`; plus rename and "Import selected" for multi-selection. |
| 16 | Import `.ttsmod` (ours and TTS Mod Backup), conflict dialog on older backup JSON; import JSON (+PNG) | done | `features/backups/application/backup_operations.dart` (import), `json_conflict_dialog.dart`, `import_results_dialog.dart`, `import_json_dialog.dart` | Shared `Mods/...` / `Saves/...` archive layout, streamed extraction (`zip_extractor.dart`), conflict → Cancel / Use backup JSON / Keep current. Tests: `import_backups_test`, `import_json_dialog_test`, `zip_extractor_test`. |
| 17 | Rename mod/save/saved object (+ rename backup); Save as Mod; delete mod (+ image + cache) | done | `dialogs/rename_mod_dialog.dart`, `save_as_mod_dialog.dart`, `delete_mod_dialog.dart`, `ModEditService` | Rename rewrites `SaveName` preserving creation time; "also rename backup" checkbox when one exists (keeps the forced-id form); saved objects get the explanatory failure. Save as Mod only for saves. Delete removes JSON + image, `modsDao.deleteByPaths` (cascades `mod_assets`, `PRAGMA foreign_keys = ON`) and `LibraryController.removeMod`. |
| 18 | Delete mod assets (non-shared / all) with shared report; bulk delete assets | done | `features/cleanup/presentation/delete_mod_assets_dialog.dart`, `features/cleanup/application/delete_assets_service.dart`, `features/bulk/presentation/bulk_delete_assets_dialog.dart` | Exclusive count, expandable shared list with sharing mods per URL, "also delete shared" checkbox; bulk scope dialog. |
| 19 | Update URLs (prefix or whole URL, `|` multi old prefixes, presets from settings, rename files) single and bulk | done | `features/url_updates/presentation/update_urls_dialog.dart`, `application/url_prefix_rules.dart`, `url_updates_service.dart`, `settings/presentation/url_presets_section.dart` | Preset dropdown (falls back to "Custom" on edit), `|` copy button, validation, rename option, help dialog. Tests: `update_urls_dialog_test`, `url_prefix_rules_test`. |
| 20 | Cleanup unused cached files | done | `features/cleanup/presentation/cleanup_actions.dart`, `cleanup_confirm_dialog.dart`, `application/cleanup_service.dart` | Scan (five asset folders + raw folders + legacy-host duplicates), confirm dialog, deletion on the runner with cancel. **Fixed (G2):** the "Scanning…" modal's Cancel now cancels the scan itself through a `CancellationToken`. |
| 21 | Bulk: download, backup, download+backup, with skip/replace rules and post-backup deletion; cancel for every bulk op | done | `features/bulk/presentation/bulk_actions_menu.dart`, `bulk_actions.dart`, `bulk_backup_dialog.dart` (`BulkBackupBehavior`, `PostBackupDeletion`), `application/bulk_operations.dart` | Bulk button shows the affected count; targets are the multi-selection or the filtered list (`bulk_targets.dart`); every op runs on the engine with the shared Cancel. Also Update from Workshop, Delete assets, Check URLs, Update URLs, Import backups. Tests: `bulk_operations_test`, `bulk_actions_menu_test`. |
| 22 | Refresh with optional clear cache | done | `features/library/presentation/refresh_dialog.dart` (`showRefreshDialog`, used by the sidebar in `app/shell/app_shell.dart` and by F5 on the library page), `LibraryController.refresh(clearCache:)` | Confirm dialog with the "clear cache" checkbox + info. |
| 23 | Settings: folders (mods, saves, backups, custom saves folder), ignored subfolders, ignored domains, force JSON filename in backup names, check updates on start, asset URL font size, concurrent downloads, show saved objects, show backup state | done | `features/settings/presentation/settings_dialog.dart`, `folders_section.dart`, `features_section.dart`, `interface_section.dart`, `network_section.dart`, `application/app_settings.dart` | All v2 fields, same JSON keys and defaults; folder validation as the start-up picker; "Allow custom Saves folder" and "Show PDF thumbnails" in Features. "Reset to defaults" also resets the theme: v2 had no theme, the confirm text says "including the theme", and Appearance is a section of this dialog, so this is kept as intended behaviour (noted, not a bug). |
| 24 | Update check against GitHub releases with Nexus/GitHub links; Help; Changelog; Ko-fi/Steam links | done | `features/about/application/update_check.dart`, `presentation/update_notice.dart` (`UpdateAvailableDialog`), `help_dialog.dart` (Help / Changelog / About tabs), `about_links.dart` | Dialog: Cancel / Nexus Mods / GitHub; About tab: GitHub releases, Nexus Mods, Steam discussion, Ko-fi, manual check, open log folder. Content from `assets/text/help.md`, `changelog.md`. |
| 25 | Collapsible log panel with level/source filters, search, jump to mod, copy, clear, error badge, one-click open of the rotating log file | done | `features/logs/presentation/log_panel.dart`, `log_panel_header.dart`, `log_entry_row.dart` (`selectLogEntryMod`), `application/log_providers.dart`, `core/logging/log_sink.dart` | Resizable, persisted height; unseen badge + header flash; open file / open folder / copy path. |
| 26 | Appearance settings: theme mode, seed colour, presets incl. Classic | done | `features/settings/presentation/appearance_section.dart`, `app/theme/theme_presets.dart`, `theme_controller.dart` | System/light/dark segmented button, preset chips (Vault, Classic, Ocean, Forest, Ember, Rose), swatches + hex field; live preview reverted on Cancel. |
| 27 | Window: min size 854x480, maximise on first show, title with version | done | `bootstrap/bootstrap.dart` | `WindowOptions(minimumSize: Size(854, 480), title: 'TTS Mod Vault <version>')`, maximise in a post-frame callback (100 ms delay kept from v2). |
| 28 | macOS pdfium module path fix; Linux header bar title; Windows product strings; AppImage and DMG scripts | done | `bootstrap/bootstrap.dart` (`_configurePdfiumModulePath`), `v3/linux/runner/my_application.cc`, `v3/windows/runner/Runner.rc`, repo `packaging/appimage/build_appimage.sh`, `packaging/macos/build_dmg.sh` | The packaging scripts live at the repo root and already take `PROJECT_DIR=v3`. Linux/macOS builds themselves are still on the Phase 6 list (need the VM/Mac). |
| 29 | 2.x `051741c` domain reachability: the single and bulk URL check test each host first, skip URLs on unreachable hosts, save the invalid list only when every host answered; results list unreachable domains | done | `data/net/domain_reachability_checker.dart`, `features/downloads/application/check_urls_operation.dart` (`checkUrlsWithDomains`), `url_check_results_dialog.dart`, `features/bulk/presentation/bulk_url_check_results_dialog.dart` | Any HTTP answer means reachable; one-minute cache shared through `domainReachabilityCheckerProvider` (the bulk check reuses it across mods, the single check forces a refresh). The bulk dialog counts each unreachable host once across mods (2.x summed per mod). Tests: `domain_reachability_checker_test`, `check_urls_operation_test`, `results_dialogs_test`, `bulk_results_test`. |
| 30 | 2.x `051741c` post-download validation after single-mod download, bulk/multi-select download and bulk download + backup, with the "Download check results" dialog | done | `features/downloads/application/validate_download_operation.dart`, `presentation/download_validation_dialog.dart`, `download_actions.dart`, `features/bulk/application/bulk_operations.dart`, `bulk_actions.dart` | Saved objects skipped; nothing missing clears the stored list. Runs only after a whole-mod download (not per type or per asset), as 2.x. The download + backup run checks before the backup so post-backup deletion cannot make every file look missing. Tests: `validate_download_operation_test`, `download_wiring_test`, `results_dialogs_test`. |
| 31 | 2.x `051741c` Settings → Network "Check all Mods and Saves domains" with the "Domain reachability results" dialog | done | `features/settings/application/check_domains_operation.dart`, `presentation/network_section.dart` (`CheckDomainsButton`), `domain_reachability_dialog.dart`, `data/db/daos/library_queries.dart` (`distinctAssetUrls`) | Runs on the `OperationRunner` (`OperationKind.checkDomains`). The button has its own Cancel while it runs because the modal Settings dialog covers the progress bar. Tests: `check_domains_operation_test`, `domain_reachability_dialog_test`, `library_queries_test`, `settings_dialog_test`. |

### Specific conditions checked

- Backups tab only when a backups folder is set: `availableLibraryTabsProvider`; the tab falls back to Mods when the folder is removed.
- "Download" context item only when assets are missing: `buildModContextMenu` (`mod.missingCount > 0`); asset menu "Download" only when `asset.path == null`.
- "Save as Mod" only for saves; "Open Steam Workshop page" / "Update from Workshop" only for mods (disabled without a numeric id).
- Mods/Saves selector tooltip shows counts: yes.
- Help tooltip in the selected-mod header: `SelectedModHeader(showHelp: true)` on the empty header and the selected view (`AssetHelpTooltip`, colour legend + actions).
- Images viewer reachable from the mod context menu and the Images group header: yes (`openImagesViewer`).
- "Open in file explorer" for assets (`asset_context_menu.dart`), mods and backups (`mod_context_menu.dart`, `backup_context_menu.dart`, `selected_backup_panel.dart`): yes.
- Esc clears the selection and Ctrl/Cmd+F focuses the search on both tabs: `LibraryPage` `CallbackShortcuts`; tests in `library_page_test` and `backups_view_test`. F5 and Delete were added in the keyboard pass (see below).
- Deleting a mod removes its cached rows: `modsDao.deleteByPaths` + `ModAssets.modPath` `onDelete: cascade` with foreign keys enabled, then `removeMod`.
- Renaming a mod renames the backup when asked: `ModEditService.renameMod(renameBackup:)` → `_renameBackupFor` (disk, `backups` table, library state).
- Bulk button shows the affected count and respects filters: `bulkTargetsProvider` (selection ≥ 2, else `filteredModsProvider`).
- `showBackupState` hides the badge and the filter section; now also clears active backup filters on Save.

## Fixes made in this audit

All within existing patterns, with tests; `dart format`, `flutter analyze` and `flutter test` are green.

1. **Asset context menu: "Copy filename"** (v2 item that was missing). `asset_context_menu.dart`: new `assetFileName(Asset)` helper and a `MenuAction` after "Copy URL". Tests: `asset_detail_helpers_test.dart`, label added to the menu test in `selected_mod_panel_test.dart`.
2. **Backup badge tooltip shows the mod's save time** next to the backup time (v2 "Update:" line). `mod_badges.dart` `backupTooltip` + ARB `backupTooltipModSaved`. Test: `test/features/library/presentation/mod_badges_test.dart`.
3. **"Copy missing URLs"** bottom-bar button (v2 overflow-menu item that was missing). `selected_mod_actions.dart`: button disabled when nothing is missing, `missingUrlsText(List<Asset>)` helper, ARB `actionCopyMissingUrls`. Tests: `selected_mod_panel_test.dart` ("Copy missing URLs" group), `asset_detail_helpers_test.dart`.
4. **Switching "Show backup state" off drops active backup-status filters** (v2 did; otherwise hidden filters kept hiding mods). `ModFilterController.clearBackupStatuses()` + call in `SettingsDialog._applyEffects`. Tests: `library_view_providers_test.dart`, `settings_dialog_test.dart`.

## Gaps needing work

All four gaps are **resolved**. The table keeps the original finding and
proposal and adds what was done.

| Id | Gap | Proposal | Status |
| --- | --- | --- | --- |
| G1 | Image tiles (images viewer) and PDF thumbnails offer a reduced right-click menu (Open file, Open in explorer, Copy URL). v2 offered the full asset menu on both (plus Check URL, Shared with, Delete file, Replace URL, Copy filename). | Give `ImagesViewerGridCard` and `PdfThumbnail` the owning `Mod` (the viewer page and `AssetList` have it), make the card a `HookConsumerWidget`, and call `showAssetContextMenu(context, ref, position, mod, asset)` instead of `showAssetFileMenu`; delete `showAssetFileMenu` once unused. Update `images_viewer_page_test` and `pdf_thumbnail_test` constructors and assert the extra items. | **Resolved** as proposed. `ImagesViewerGridCard(mod:, asset:)` is a `HookConsumerWidget`, `PdfThumbnail(mod:, asset:)` too; both call `showAssetContextMenu`. `asset_file_actions.dart` keeps only `urlTail` and `openAssetFile`. Tests: `pdf_thumbnail_test` (full menu on a downloaded file, Download-only variant for a missing one), `images_viewer_page_test`. |
| G2 | Cleanup scan is not cancellable: the "Scanning…" modal's Cancel abandons the result, but `CleanupService.scanOrphans` keeps running (worker-pool directory listings + the orphan query) until it finishes. | Add a `CancellationToken` parameter to `scanOrphans`/`_scan`, check it between the listing phase, the raw-file usage query and the size stats, and cancel the token when the modal pops with null (`runCleanup`). Optionally run the scan as a runner `Operation` so the docked bar and its Cancel cover it. | **Resolved.** `scanOrphans({CancellationToken? token})` checks the token before and between the phases and passes it to `pool.runAll` / `pool.run`; a cancelled scan throws `OperationCancelledException` (logged as info, not as a failed scan). `runCleanup` creates the token, cancels it when the modal pops without `true` and swallows the exception. Not made a runner `Operation` (the modal already offers Cancel). Tests: `cleanup_service_test` (pre-cancelled and mid-scan cancel), `cleanup_test` (modal Cancel cancels the token; a completed scan leaves it alone). |
| G3 | Single-URL "Check URL" (asset menu) is a fire-and-forget request with no cancel; bounded only by the 15 s connect/send/receive timeouts. Same as v2. | Either accept (one request, bounded), or route it through `OperationUi.launch` with a one-asset `CheckUrlsOperation` so the progress bar and Cancel appear and the result also persists the invalid flag. | **Implemented.** `CheckUrlsOperation(onlyAsset:)` checks that one URL and merges the outcome into the mod's stored invalid list (adds the URL when dead, removes it when live, keeps the rest); `DownloadsService.checkUrl(mod, asset)`; `checkSingleUrl(context, ref, mod, asset)` runs it through `OperationUi.launch` and shows "URL is valid" / "URL is not reachable" (nothing when cancelled). `singleUrlCheckProvider` removed. Tests: `check_urls_operation_test` (merge semantics, one request, progress total 1), `download_wiring_test`. |
| G4 | Tab selector tooltip lists zero counts ("0 saved objects"); v2 omitted empty kinds and showed no tooltip when everything was empty. | Filter `counts == 0` out of the tooltip list and skip the `Tooltip` when the list is empty. Cosmetic. | **Resolved** as proposed (`library_tab_selector.dart`). Tests: `library_page_test` ("5 mods, 1 save" with an empty backups folder; no tooltip for an empty library). |

Decision recorded: "Reset to defaults" also resetting the theme is kept (v2 had no theme; the confirmation text already says so; Appearance is a section of the same dialog).

## Smell audit (plan section 2)

Greps over `v3/lib` (generated files excluded):

| Smell | Result |
| --- | --- |
| Sync IO (`existsSync`, `statSync`, `readAsStringSync`, `listSync`, `lengthSync`) in a `build` method | **None.** All hits are in services/operations (`mod_edit_service.dart`, `backup_service.dart`, `backup_operations.dart`, `cleanup_service.dart`), the rotating log sink, `json_mod_reader.dart`, `tts_paths.dart`/`startup_controller.dart` (injected `DirectoryExists`), `library_tasks.dart` (isolate) and `bootstrap.dart` (pdfium path, before `runApp`). Grid cards and list rows use `Image.file` + `errorBuilder`. |
| `SizedBox.shrink()` placeholder rows in list builders | **None.** The asset list is a pre-flattened `List<AssetListRow>` with no filtered-out rows. The 9 remaining `SizedBox.shrink()` are "this widget renders nothing" cases in dedicated widgets (`BackupStatusBadge`, `MissingCountBadge`, `AudioBadge`, `_Overlay`, `DelayedProgress`, `OperationProgressBar(showWhenIdle: false)`, log preview, startup gate), not list items. |
| Literal `Colors.*` outside the theme files | 7 hits, all `Colors.transparent` as the "no border" colour of hover/selection borders (`vault_sidebar.dart`, `mods_grid_card.dart`, `mods_list_item.dart`, `backup_grid_card.dart`, `backup_list_item.dart`, `images_viewer_grid_card.dart`, `pdf_thumbnail.dart`). Not a palette colour; left as is. |
| `TextStyle(fontSize:)` outside the theme files | 1 hit: `asset_url_row.dart` applies the user's "asset URL font size" setting via `copyWith(fontSize:)`. Intentional. |
| `print` | 0 `print`; 1 `debugPrint` in `bootstrap.dart` for a maximise failure before the log store exists. Acceptable. |
| `BuildContext` passed into application-layer code | **None** under `features/*/application`, `core`, `data`, `domain`, `bootstrap`. |
| `showDialog` from application code | **None**; dialogs are shown from `presentation` through `OperationUi.showAppDialog` / `showDialog`, with callbacks (`onJsonConflict`) crossing the layer. |

Nothing trivial was left to fix in this section.

## Keyboard shortcuts (plan 4.6)

All on `LibraryPage`, so they work on every tab; none fires while a dialog
is open (the dialog route owns the focus).

| Key | Action | Where |
| --- | --- | --- |
| Ctrl/Cmd+F | Focus the search field of the current tab | `CallbackShortcuts` |
| Esc | Unfocus the search field if it has focus, else clear the current tab's selection | `CallbackShortcuts` |
| F5 | The Refresh confirmation (`showRefreshDialog`, shared with the sidebar's Refresh item); ignored while an operation runs | `CallbackShortcuts` |
| Delete | Mods / Saves / Saved Objects: `showDeleteModDialog` for the one selected mod; Backups: `deleteBackupWithConfirm` for the one selected backup. Nothing with zero or several selected, nothing while an operation runs | `Focus.onKeyEvent` |

Delete is handled on the page's focus node rather than as a shortcut because
a `CallbackShortcuts` binding reports the key as handled even when its
callback does nothing, which would have stopped Delete from editing text in
the search field. `focusIsInTextField()` (primary focus inside an
`EditableText`) makes the handler return `ignored` so the field keeps the
key. Ctrl/Cmd-click multi-select is unchanged.

Tests: `library_page_test` (tooltip, F5 with and without the search field
focused, Delete with none / one / several selected, Delete while typing
edits the text), `backup_edit_test` (Delete on the Backups tab),
`backups_view_test` (Esc, Ctrl+F on the Backups tab).

## Light theme

`test/app/theme/app_theme_test.dart` checks, for every preset (Vault,
Classic, Ocean, Forest, Ember, Rose) in both brightnesses, that each
`VaultColors` colour (asset present / missing / invalid, backup up to date /
out of date / mismatch / none, log info / success / warning / error) plus
`colorScheme.primary` (selected-card border), `error`, `onSurface` and
`onSurfaceVariant` has a WCAG contrast ratio of at least 3.0 against both
`colorScheme.surface` and `colorScheme.surfaceContainer`; a further test
runs `VaultColors.fromScheme` on an amber fidelity scheme in both
brightnesses. Every preset passed as is, so `VaultColors.fromScheme` was not
changed: its hues come from `ColorScheme.fromSeed(...).primary` at the
scheme's brightness, which lands on tone 40 (light) / 80 (dark) against
surfaces at tone 98 / 6, and `backupNone` reuses `onSurfaceVariant`. The
measured minimum over all presets is 5.52 in light mode (Forest, `primary`
on `surfaceContainer`) and 9.56 in dark mode (Forest, `logInfo`), both well
above the 3.0 threshold and even the 4.5 text threshold. The
asset URL rows (`asset_url_row.dart`) and the log rows use exactly these
colours, and the selected card border is `primary`, so the same assertions
cover them.
