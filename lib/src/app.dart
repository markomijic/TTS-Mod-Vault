import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/mods/images_viewer_page.dart'
    show ImagesViewerPage;
import 'package:tts_mod_vault/src/mods/mods_page.dart' show ModsPage;
import 'package:tts_mod_vault/src/splash/splash_page.dart' show SplashPage;
import 'package:tts_mod_vault/src/utils.dart' show darkTheme;

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TTS Mod Vault',
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashPage(),
        '/mods': (context) => const ModsPage(),
        '/images-viewer': (context) => const ImagesViewerPage(),
      },
    );
  }
}
