import 'dart:async' show Timer;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useFocusNode, useRef, useState, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, StateProvider, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider, selectedModTypeProvider;

class Search extends HookConsumerWidget {
  final StateProvider<String> searchQueryProvider;

  const Search({super.key, required this.searchQueryProvider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModType = ref.watch(selectedModTypeProvider);
    final controller = useTextEditingController();
    final focusNode = useFocusNode();
    final debounceTimer = useRef<Timer?>(null);
    final isExpanded = useState(false);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.clear();
        isExpanded.value = false;
      });
      return null;
    }, [selectedModType]);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final query = ref.read(searchQueryProvider);
        controller.text = query;
        if (query.isNotEmpty) isExpanded.value = true;
      });
      return null;
    }, []);

    useEffect(() {
      return () {
        debounceTimer.value?.cancel();
      };
    }, []);

    useEffect(() {
      void onFocusChange() {
        if (!focusNode.hasFocus && controller.text.isEmpty) {
          isExpanded.value = false;
        }
      }

      focusNode.addListener(onFocusChange);
      return () => focusNode.removeListener(onFocusChange);
    }, []);

    void onSearchChanged(String value) {
      if (ref.read(actionInProgressProvider)) return;

      debounceTimer.value?.cancel();

      debounceTimer.value = Timer(const Duration(milliseconds: 500), () {
        ref.read(searchQueryProvider.notifier).state = value;
      });
    }

    return isExpanded.value
        ? SizedBox(
            width: 300,
            height: 32,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              onChanged: onSearchChanged,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                prefixIcon: const Icon(Icons.search, color: Colors.black),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.black, size: 17),
                  onPressed: () {
                    controller.clear();
                    debounceTimer.value?.cancel();
                    ref.read(searchQueryProvider.notifier).state = '';
                    isExpanded.value = false;
                  },
                ),
                hintText: 'Search',
                hintStyle: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          )
        : SizedBox(
            height: 32,
            width: 32,
            child: ElevatedButton(
              onPressed: () {
                isExpanded.value = true;
                focusNode.requestFocus();
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.white),
                foregroundColor: WidgetStateProperty.all(Colors.black),
                padding: WidgetStateProperty.all(EdgeInsets.zero),
                shape: WidgetStateProperty.all(const CircleBorder()),
              ),
              child: const Icon(Icons.search, size: 20),
            ),
          );
  }
}
