import 'package:flutter/foundation.dart' show DebugPrintCallback;
import 'package:flutter/material.dart';

class DebugConsole extends StatefulWidget {
  final double height;
  const DebugConsole({super.key, this.height = 200});

  @override
  State<DebugConsole> createState() => _DebugConsoleState();
}

class _DebugConsoleState extends State<DebugConsole> {
  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();
  late final DebugPrintCallback _originalDebugPrint;

  @override
  void initState() {
    super.initState();

    // Save the original debugPrint
    _originalDebugPrint = debugPrint;

    // Override debugPrint to capture logs
    debugPrint = (String? message, {int? wrapWidth}) {
      final ts = DateTime.now().toIso8601String();
      final log = "[$ts] ${message ?? ''}";

      if (mounted) {
        setState(() => _logs.add(log));

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }

      // Still call the original debugPrint
      _originalDebugPrint(message, wrapWidth: wrapWidth);
    };
  }

  @override
  void dispose() {
    // Restore original debugPrint
    debugPrint = _originalDebugPrint;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: widget.height,
      width: MediaQuery.of(context).size.width * 0.31,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(4),
        child: SelectableText(
          _logs.join('\n'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
