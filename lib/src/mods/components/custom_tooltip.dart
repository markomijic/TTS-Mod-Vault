import 'package:flutter/material.dart'
    show
        Border,
        BorderRadius,
        BoxDecoration,
        BuildContext,
        Colors,
        InlineSpan,
        StatelessWidget,
        TextStyle,
        Theme,
        Tooltip,
        Widget;

class CustomTooltip extends StatelessWidget {
  final String? message;
  final InlineSpan? richMessage;
  final Widget? child;
  final Duration? waitDuration;

  const CustomTooltip({
    super.key,
    this.message,
    this.richMessage,
    this.child,
    this.waitDuration,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      waitDuration: waitDuration,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.white, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: richMessage == null
          ? TextStyle(
              fontSize: 16,
              color: Colors.white,
            )
          : null,
      message: message,
      richMessage: richMessage,
      child: child,
    );
  }
}
