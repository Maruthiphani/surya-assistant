import 'package:flutter/material.dart';

import '../services/ai_service.dart';

/// Lets the user choose among Places candidates for a *specific* reminder when
/// more than one match is returned (CLAUDE.md §5 — never silently pick one).
/// Returns the chosen [PlaceCandidate] via Navigator.pop.
class PickLocationScreen extends StatelessWidget {
  const PickLocationScreen({super.key, required this.candidates});

  final List<PlaceCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Which place?')),
      body: ListView.separated(
        itemCount: candidates.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = candidates[i];
          return ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(c.name),
            subtitle: Text(c.address),
            onTap: () => Navigator.of(context).pop(c),
          );
        },
      ),
    );
  }
}
