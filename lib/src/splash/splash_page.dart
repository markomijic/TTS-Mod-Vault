import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/state/provider.dart';

class SplashPage extends HookConsumerWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directoriesNotifier = ref.watch(directoriesProvider.notifier);
    final modsNotifier = ref.watch(modsProvider.notifier);

    final ttsDirNotFound = useState(false);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await directoriesNotifier.checkIfTtsDirectoryExists()) {
          modsNotifier.loadModsData().then(
                (value) => context.mounted
                    ? Navigator.of(context).pushReplacementNamed('/mods')
                    : null,
              );
        } else {
          ttsDirNotFound.value = true;
        }
      });

      return null;
    }, []);

    return SafeArea(
      child: Scaffold(
        body: Center(
          child: ttsDirNotFound.value
              ? Text('TTS directory not found!')
              : CircularProgressIndicator(
                  color: Colors.white,
                ),
        ),
      ),
    );
  }
}
