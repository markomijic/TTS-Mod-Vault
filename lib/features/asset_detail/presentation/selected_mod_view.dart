import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/domain/models/models.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_list.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/asset_toolbar.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_actions.dart';
import 'package:tts_mod_vault/features/asset_detail/presentation/selected_mod_header.dart';

/// The right panel for one selected mod (2.x `_SelectedModViewComponent`):
///
/// ```
/// Column
/// ├─ SelectedModHeader   name ("file.json⏎name" for saves) + help icon
/// ├─ AssetToolbar        status menu, audio, search, invalid/type chips
/// ├─ Expanded(AssetList) grouped URL list with per-type headers
/// └─ SelectedModBottomBar action buttons / operation progress slot
/// ```
class SelectedModView extends StatelessWidget {
  /// Creates the view for [mod].
  const SelectedModView({super.key, required this.mod});

  /// The selected mod.
  final Mod mod;

  @override
  Widget build(BuildContext context) {
    final title = mod.ref.type == ModType.save
        ? '${mod.ref.fileName}\n${mod.displayName}'
        : mod.displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectedModHeader(title: title),
        AssetToolbar(mod: mod),
        Expanded(child: AssetList(mod: mod)),
        SelectedModBottomBar(mod: mod),
      ],
    );
  }
}
