import 'package:flutter/material.dart';

class MessageProgressIndicator extends StatelessWidget {
  final bool showCircularIndicator;
  final String message;

  const MessageProgressIndicator({
    super.key,
    this.showCircularIndicator = true,
    this.message = "Loading",
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 8,
      children: [
        if (showCircularIndicator)
          CircularProgressIndicator(
            color: Colors.white,
            constraints: BoxConstraints(minHeight: 50, minWidth: 50),
            strokeWidth: 6,
          ),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
