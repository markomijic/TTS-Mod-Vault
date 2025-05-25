import 'package:flutter/material.dart';

// Enum for menu options
enum HelpMenuOption { checkForUpdates, about }

class HelpButton extends StatelessWidget {
  const HelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<HelpMenuOption>(
      color: Colors.black,
      shadowColor: Colors.red,
      surfaceTintColor: Colors.yellow,
      iconColor: Colors.blue,
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: IgnorePointer(
            ignoring: true,
            child: ElevatedButton(
              onPressed: () {},
              child: Text('Help', style: TextStyle(fontSize: 14)),
            ),
          )),
      onSelected: (HelpMenuOption option) {
        switch (option) {
          case HelpMenuOption.checkForUpdates:
            // _checkForUpdates(context);
            break;
          case HelpMenuOption.about:
            //  _showAboutDialog(context);
            break;
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<HelpMenuOption>>[
        const PopupMenuItem<HelpMenuOption>(
          value: HelpMenuOption.checkForUpdates,
          child: Text('Check for Updates'),
        ),
        const PopupMenuItem<HelpMenuOption>(
          value: HelpMenuOption.about,
          child: Text('About'),
        ),
      ],
    );
  }
}
