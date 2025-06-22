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
      children: [
        if (showCircularIndicator)
          CircularProgressIndicator(
            color: Colors.white,
            constraints: BoxConstraints(minHeight: 60, minWidth: 60),
            strokeWidth: 6,
          ),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
