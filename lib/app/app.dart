import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tts_mod_vault/app/providers/infrastructure_providers.dart';
import 'package:tts_mod_vault/app/theme/app_theme.dart';
import 'package:tts_mod_vault/app/theme/theme_controller.dart';
import 'package:tts_mod_vault/features/settings/application/settings_controller.dart';
import 'package:tts_mod_vault/features/startup/presentation/startup_page.dart';
import 'package:tts_mod_vault/l10n/generated/app_localizations.dart';

/// Picks the supported locale closest to [requested]: exact match (language,
/// script and country), then the same language (`pt_BR` -> `pt`, or `pt` ->
/// the first `pt_*` there is), then English.
Locale resolveLocale(Locale? requested, Iterable<Locale> supported) {
  const fallback = Locale('en');
  if (requested == null) return fallback;
  for (final locale in supported) {
    if (locale == requested) return locale;
  }
  Locale? sameLanguage;
  for (final locale in supported) {
    if (locale.languageCode != requested.languageCode) continue;
    // Prefer the bare language, e.g. `pt` for `pt_BR`.
    if (locale.countryCode == null && locale.scriptCode == null) return locale;
    sameLanguage ??= locale;
  }
  return sameLanguage ?? fallback;
}

/// The root widget: a [MaterialApp] themed from [themeControllerProvider]
/// with [StartupPage] as its home (which becomes the shell once loaded).
///
/// Must sit inside a `ProviderScope` that overrides [keyValueStoreProvider].
class App extends ConsumerWidget {
  /// Creates the app.
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeControllerProvider);
    final locale = ref.watch(localeSettingProvider);
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
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: resolveLocale,
      debugShowCheckedModeBanner: false,
      home: const StartupPage(),
    );
  }
}
