import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useEffect, useTextEditingController;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:tts_mod_vault/src/state/provider.dart'
    show searchQueryProvider, selectedModTypeProvider;

class Search extends HookConsumerWidget {
  const Search({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModType = ref.watch(selectedModTypeProvider);
    final controller = useTextEditingController();

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.clear();
      });
      return null;
    }, [selectedModType]);

    return SizedBox(
      height: 32,
      width: 335,
      child: TextField(
        controller: controller,
        onChanged: (value) =>
            ref.read(searchQueryProvider.notifier).state = value,
        style: TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w600,
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
                ref.read(searchQueryProvider.notifier).state = '';
              }),
          hintText: 'Search',
          hintStyle: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
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
