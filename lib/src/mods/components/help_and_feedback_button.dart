import 'package:flutter/material.dart';
import 'package:tts_mod_vault/src/utils.dart' show openUrl, showSnackBar;

class HelpAndFeedbackButton extends StatelessWidget {
  final TextStyle? style;

  const HelpAndFeedbackButton({super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () async {
        final url =
            "https://steamcommunity.com/app/286160/discussions/0/591772542952298985/";
        final result = await openUrl(url);
        if (!result && context.mounted) {
          showSnackBar(context, "Failed to open: $url");
        }
      },
      child: Text('Help & Feedback', style: style),
    );
  }
}
