import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/mods/images_viewer_page.dart'
    show ImagesViewerPage;
import 'package:tts_mod_vault/src/splash/splash_page.dart' show SplashPage;
import 'package:tts_mod_vault/src/utils.dart' show darkTheme;
import 'package:tts_mod_vault/src/mods/vault.dart' show Vault;

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TTS Mod Vault',
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      initialRoute: '/',
      /* 
      builder: (context, child) {
        return Stack(
          children: [
            child!,
            Align(
              alignment: Alignment.centerRight,
              child: DebugConsole(height: 300),
            ),
          ],
        );
      }, 
       */
      routes: {
        '/': (context) => const SplashPage(),
        '/vault': (context) => const Vault(),
        '/images-viewer': (context) => const ImagesViewerPage(),
      },
    );
  }
}
