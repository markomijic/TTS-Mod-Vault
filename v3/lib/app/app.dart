import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/shell/app_shell.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// The root widget: a [MaterialApp] themed from [themeControllerProvider]
/// with [AppShell] as its home.
///
/// Must sit inside a `ProviderScope` that overrides [keyValueStoreProvider].
class App extends ConsumerWidget {
  /// Creates the app.
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.build(settings, Brightness.light),
      darkTheme: AppTheme.build(settings, Brightness.dark),
      themeMode: settings.mode,
      // material_ui ships its own MaterialLocalizations type, so its
      // delegates are used instead of the flutter_localizations ones that the
      // generated AppLocalizations.localizationsDelegates would supply.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      home: const AppShell(),
    );
  }
}
