import 'dart:convert' show JsonEncoder;
import 'dart:io' show File, Platform, Process;
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useMemoized;
import 'package:hooks_riverpod/hooks_riverpod.dart' show HookConsumerWidget, ConsumerWidget, WidgetRef;
import 'package:path/path.dart' as path;
import 'package:tts_mod_vault/src/state/enums/asset_type_enum.dart';
import 'package:tts_mod_vault/src/state/mods/mod_model.dart' show ModTypeEnum;
import 'package:tts_mod_vault/src/state/provider.dart' show sharedAssetsProvider;
import 'package:tts_mod_vault/src/state/shared_assets/shared_assets_state.dart';
import 'package:tts_mod_vault/src/state/shared_assets/models/shared_asset_entry.dart';
import 'package:tts_mod_vault/src/state/shared_assets/models/mod_shared_assets_entry.dart';
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class SharedAssetsViewerDialog extends HookConsumerWidget {
  const SharedAssetsViewerDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sharedAssetsProvider);

    // Compute on mount
    useEffect(() {
      Future.microtask(
          () => ref.read(sharedAssetsProvider.notifier).computeSharedAssets());
      return null;
    }, []);

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: Dialog(
        child: SizedBox(
          width: 1000,
          height: 700,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Shared Assets Viewer',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    children: [
                      NavigationRail(
                        selectedIndex: state.viewMode.index,
                        onDestinationSelected: (index) {
                          ref.read(sharedAssetsProvider.notifier).setViewMode(
                              SharedAssetsViewMode.values[index]);
                        },
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.image),
                            label: Text('By Asset'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.folder),
                            label: Text('By Mod'),
                          ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: _buildContent(context, ref, state),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildBottomActions(context, ref, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, SharedAssetsState state) {
    if (state.status == SharedAssetsStatusEnum.computing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Computing shared assets...'),
          ],
        ),
      );
    }

    if (state.status == SharedAssetsStatusEnum.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: ${state.errorMessage}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref
                  .read(sharedAssetsProvider.notifier)
                  .computeSharedAssets(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.status == SharedAssetsStatusEnum.ready) {
      return IndexedStack(
        index: state.viewMode.index,
        children: [
          _AssetCentricView(),
          _ModCentricView(),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildBottomActions(
      BuildContext context, WidgetRef ref, SharedAssetsState state) {
    return Row(
      spacing: 8,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
          onPressed: state.status == SharedAssetsStatusEnum.computing
              ? null
              : () => ref
                  .read(sharedAssetsProvider.notifier)
                  .computeSharedAssets(),
        ),
        const Spacer(),
        if (state.status == SharedAssetsStatusEnum.ready)
          ElevatedButton.icon(
            icon: const Icon(Icons.file_download),
            label: const Text('Export'),
            onPressed: () => _showExportDialog(context, ref, state),
          ),
        ElevatedButton(
          onPressed: () {
            ref.read(sharedAssetsProvider.notifier).resetState();
            Navigator.pop(context);
          },
          child: const Text('Close'),
        ),
      ],
    );
  }

  Future<void> _showExportDialog(
      BuildContext context, WidgetRef ref, SharedAssetsState state) async {
    final format = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Format'),
        content: const Text('Choose export format:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'csv'),
            child: const Text('CSV'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'json'),
            child: const Text('JSON'),
          ),
        ],
      ),
    );

    if (format == null || !context.mounted) return;

    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Shared Assets',
        fileName:
            'shared_assets_${DateTime.now().millisecondsSinceEpoch}.$format',
      );

      if (path != null) {
        if (format == 'csv') {
          await _exportToCsv(path, state.filteredSharedAssets);
        } else {
          await _exportToJson(path, state.filteredSharedAssets);
        }

        if (context.mounted) {
          showSnackBar(context, 'Export successful: $path');
        }
      }
    } catch (e) {
      if (context.mounted) {
        showSnackBar(context, 'Export failed: $e');
      }
    }
  }

  Future<void> _exportToCsv(String filePath, List<SharedAssetEntry> assets) async {
    final buffer = StringBuffer();
    buffer.writeln('Filename,Asset Type,Share Count,File Path,Mods');

    for (final asset in assets) {
      buffer.writeln(
        '${asset.filename},${asset.assetType.label},${asset.shareCount},'
        '"${asset.filePath ?? 'N/A'}","${asset.modJsonFileNames.join('; ')}"',
      );
    }

    await File(filePath).writeAsString(buffer.toString());
  }

  Future<void> _exportToJson(String filePath, List<SharedAssetEntry> assets) async {
    final data = {
      'exportDate': DateTime.now().toIso8601String(),
      'totalSharedAssets': assets.length,
      'assets': assets
          .map((a) => {
                'filename': a.filename,
                'assetType': a.assetType.label,
                'shareCount': a.shareCount,
                'filePath': a.filePath,
                'mods': a.modJsonFileNames.toList(),
                'modTypeCounts': {
                  'mods': a.modTypeCounts[ModTypeEnum.mod] ?? 0,
                  'saves': a.modTypeCounts[ModTypeEnum.save] ?? 0,
                  'savedObjects':
                      a.modTypeCounts[ModTypeEnum.savedObject] ?? 0,
                },
              })
          .toList(),
    };

    await File(filePath).writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }
}

// Asset-Centric View
class _AssetCentricView extends HookConsumerWidget {
  _AssetCentricView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sharedAssetsProvider);
    final filteredAssets = useMemoized(
        () => state.filteredSharedAssets, [state.filteredSharedAssets]);

    return Column(
      children: [
        _FilterHeader(),
        const SizedBox(height: 8),
        if (filteredAssets.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No shared assets found'),
                  if (state.filteredAssetTypes.isNotEmpty ||
                      state.filteredModTypes.isNotEmpty ||
                      state.searchQuery.isNotEmpty)
                    TextButton(
                      onPressed: () => ref
                          .read(sharedAssetsProvider.notifier)
                          .clearAllFilters(),
                      child: const Text('Clear Filters'),
                    ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: filteredAssets.length,
              itemBuilder: (context, index) {
                return _AssetCard(asset: filteredAssets[index]);
              },
            ),
          ),
      ],
    );
  }
}

// Mod-Centric View
class _ModCentricView extends HookConsumerWidget {
  _ModCentricView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sharedAssetsProvider);
    final filteredMods = useMemoized(
        () => state.filteredModSharedAssets, [state.filteredModSharedAssets]);

    return Column(
      children: [
        _FilterHeader(),
        const SizedBox(height: 8),
        if (filteredMods.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No mods with shared assets found'),
                  if (state.filteredAssetTypes.isNotEmpty ||
                      state.filteredModTypes.isNotEmpty ||
                      state.searchQuery.isNotEmpty)
                    TextButton(
                      onPressed: () => ref
                          .read(sharedAssetsProvider.notifier)
                          .clearAllFilters(),
                      child: const Text('Clear Filters'),
                    ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              itemCount: filteredMods.length,
              itemBuilder: (context, index) {
                return _ModCard(mod: filteredMods[index]);
              },
            ),
          ),
      ],
    );
  }
}

// Filter Header
class _FilterHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sharedAssetsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Asset type filters
        const Text('Asset Type:', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: AssetTypeEnum.values.map((type) {
            return FilterChip(
              label: Text(type.label),
              selected: state.filteredAssetTypes.contains(type),
              onSelected: (selected) {
                ref.read(sharedAssetsProvider.notifier).toggleAssetTypeFilter(type);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // Mod type filters
        const Text('Mod Type:', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: ModTypeEnum.values.map((type) {
            return FilterChip(
              label: Text(type.label),
              selected: state.filteredModTypes.contains(type),
              onSelected: (selected) {
                ref.read(sharedAssetsProvider.notifier).toggleModTypeFilter(type);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // Search and sort
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onChanged: (value) {
                  ref.read(sharedAssetsProvider.notifier).setSearchQuery(value);
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(state.sortAscending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward),
              tooltip:
                  'Sort by share count ${state.sortAscending ? 'descending' : 'ascending'}',
              onPressed: () {
                ref.read(sharedAssetsProvider.notifier).toggleSortOrder();
              },
            ),
          ],
        ),
      ],
    );
  }
}

// Asset Card
class _AssetCard extends ConsumerWidget {
  final SharedAssetEntry asset;

  const _AssetCard({required this.asset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(_getAssetIcon(asset.assetType)),
        title: Text(asset.filename),
        subtitle: Text('${asset.shareCount} mods • ${asset.assetType.label}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.folder_open, size: 20),
              tooltip: 'Open in file explorer',
              onPressed: asset.filePath != null
                  ? () => _openInExplorer(asset.filePath!)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 20),
              tooltip: 'Copy asset info',
              onPressed: () => _copyAssetInfo(context, asset),
            ),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Used by ${asset.shareCount} mods:',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                ...asset.modJsonFileNames.map((modName) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(modName)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Mod Card
class _ModCard extends ConsumerWidget {
  final ModSharedAssetsEntry mod;

  const _ModCard({required this.mod});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(_getModTypeIcon(mod.modType)),
        title: Text(mod.modSaveName),
        subtitle: Text('${mod.sharedAssetCount} shared assets'),
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shared assets (${mod.sharedAssetCount}):',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                ...mod.sharedAssets.map((asset) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(_getAssetIcon(asset.assetType), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              '${asset.filename} (shared with ${asset.shareCount - 1} others)'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.folder_open, size: 18),
                          tooltip: 'Open in file explorer',
                          onPressed: asset.filePath != null
                              ? () => _openInExplorer(asset.filePath!)
                              : null,
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Helper functions
IconData _getAssetIcon(AssetTypeEnum type) {
  switch (type) {
    case AssetTypeEnum.image:
      return Icons.image;
    case AssetTypeEnum.audio:
      return Icons.audiotrack;
    case AssetTypeEnum.model:
      return Icons.view_in_ar;
    case AssetTypeEnum.assetBundle:
      return Icons.folder_zip;
    case AssetTypeEnum.pdf:
      return Icons.picture_as_pdf;
  }
}

IconData _getModTypeIcon(ModTypeEnum type) {
  switch (type) {
    case ModTypeEnum.mod:
      return Icons.extension;
    case ModTypeEnum.save:
      return Icons.save;
    case ModTypeEnum.savedObject:
      return Icons.category;
  }
}

Future<void> _openInExplorer(String filePath) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      // Try to open the containing directory
      final directory = path.dirname(filePath);
      await Process.run('xdg-open', [directory]);
    }
  } catch (e) {
    debugPrint('Error opening file explorer: $e');
  }
}

Future<void> _copyAssetInfo(BuildContext context, SharedAssetEntry asset) async {
  final info = '''
Filename: ${asset.filename}
Type: ${asset.assetType.label}
Shared by: ${asset.shareCount} mods
Path: ${asset.filePath ?? 'Not downloaded'}
Mods: ${asset.modJsonFileNames.join(', ')}
''';

  await Clipboard.setData(ClipboardData(text: info));

  if (context.mounted) {
    showSnackBar(context, 'Asset info copied to clipboard');
  }
}
