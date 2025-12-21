import 'dart:async' show Timer;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useRef, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show actionInProgressProvider, searchQueryProvider, selectedModTypeProvider;

class Search extends HookConsumerWidget {
  const Search({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModType = ref.watch(selectedModTypeProvider);
    final controller = useTextEditingController();
    final debounceTimer = useRef<Timer?>(null);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.clear();
      });
      return null;
    }, [selectedModType]);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.text = ref.read(searchQueryProvider);
      });
      return null;
    }, []);

    useEffect(() {
      return () {
        debounceTimer.value?.cancel();
      };
    }, []);

    void onSearchChanged(String value) {
      if (ref.read(actionInProgressProvider)) return;

      debounceTimer.value?.cancel();

      debounceTimer.value = Timer(const Duration(milliseconds: 500), () {
        ref.read(searchQueryProvider.notifier).state = value;
      });
    }

    return SizedBox(
      width: 300,
      height: 32,
      child: TextField(
        controller: controller,
        onChanged: onSearchChanged,
        style: TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 20),
          prefixIcon: Icon(
            Icons.search,
            color: Colors.black,
          ),
          suffixIcon: IconButton(
              icon: const Icon(
                Icons.clear,
                color: Colors.black,
                size: 17,
              ),
              onPressed: () {
                controller.clear();
                debounceTimer.value?.cancel();
                ref.read(searchQueryProvider.notifier).state = '';
              }),
          hintText: 'Search',
          hintStyle: TextStyle(
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
    );
  }
}
