import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/idea.dart';
import '../providers/providers.dart';
import '../services/speech_service.dart';

/// "My Ideas" (CLAUDE.md Phase 10): a private place to jot and search ideas,
/// by typing or by voice. Backed by `users/{uid}/ideas` via a live listener.
class IdeasScreen extends ConsumerWidget {
  const IdeasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ideas = ref.watch(filteredIdeasProvider);
    final loading = ref.watch(ideasProvider).isLoading;
    final query = ref.watch(ideaSearchProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Ideas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('New idea'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search ideas',
                  border: const OutlineInputBorder(),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () =>
                              ref.read(ideaSearchProvider.notifier).state = '',
                        ),
                ),
                onChanged: (v) =>
                    ref.read(ideaSearchProvider.notifier).state = v,
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ideas.isEmpty
                      ? _Empty(searching: query.trim().isNotEmpty)
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 96),
                          itemCount: ideas.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _IdeaTile(idea: ideas[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeaTile extends ConsumerWidget {
  const _IdeaTile({required this.idea});
  final Idea idea;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.lightbulb_outline),
      title: Text(idea.title),
      subtitle: idea.description == null && idea.createdAt == null
          ? null
          : Text(
              [
                if (idea.description != null) idea.description!,
                if (idea.createdAt != null) _dateLabel(idea.createdAt!),
              ].join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
      isThreeLine: idea.description != null,
      onTap: () => _openEditor(context, existing: idea),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete',
        onPressed: () => _confirmDelete(context, ref, idea),
      ),
    );
  }
}

Future<void> _confirmDelete(
    BuildContext context, WidgetRef ref, Idea idea) async {
  final uid = ref.read(currentUidProvider);
  if (uid == null) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${idea.title}"?'),
      content: const Text('This permanently removes the idea.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete')),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(ideaRepositoryProvider).deleteIdea(uid, idea.id);
  }
}

void _openEditor(BuildContext context, {Idea? existing}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _IdeaEditor(existing: existing),
  );
}

/// Add/edit sheet with voice dictation on both fields.
class _IdeaEditor extends ConsumerStatefulWidget {
  const _IdeaEditor({this.existing});
  final Idea? existing;

  @override
  ConsumerState<_IdeaEditor> createState() => _IdeaEditorState();
}

class _IdeaEditorState extends ConsumerState<_IdeaEditor> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _descCtrl =
        TextEditingController(text: widget.existing?.description ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = ref.read(currentUidProvider);
    final title = _titleCtrl.text.trim();
    if (uid == null || title.isEmpty) return;
    final repo = ref.read(ideaRepositoryProvider);
    final desc = _descCtrl.text.trim();
    if (widget.existing == null) {
      await repo.addIdea(uid, title: title, description: desc);
    } else {
      await repo.updateIdea(uid, widget.existing!.id,
          title: title, description: desc);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.existing == null ? 'New idea' : 'Edit idea',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _DictationField(
            controller: _titleCtrl,
            label: 'Title',
            hint: 'e.g. weekend hiking app',
            autofocus: widget.existing == null,
          ),
          const SizedBox(height: 12),
          _DictationField(
            controller: _descCtrl,
            label: 'Details (optional)',
            hint: 'Describe the idea…',
            maxLines: 4,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _save,
            child: Text(widget.existing == null ? 'Save idea' : 'Save'),
          ),
        ],
      ),
    );
  }
}

/// A text field with a mic button that dictates into it (reuses the Phase 4
/// [SpeechService]). Tap to start/stop; transcripts replace the field text.
class _DictationField extends ConsumerStatefulWidget {
  const _DictationField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final bool autofocus;

  @override
  ConsumerState<_DictationField> createState() => _DictationFieldState();
}

class _DictationFieldState extends ConsumerState<_DictationField> {
  bool _listening = false;
  String _base = '';

  Future<void> _toggle() async {
    final speech = ref.read(speechServiceProvider);
    if (_listening) {
      await speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ok = await speech.init();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
              const SnackBar(content: Text('Speech not available.')));
      }
      return;
    }
    // Keep existing text and append what's dictated.
    _base = widget.controller.text.trim();
    setState(() => _listening = true);
    await speech.listen(
      onResult: (text, isFinal) {
        final joined = _base.isEmpty ? text : '$_base $text';
        widget.controller.text = joined;
        widget.controller.selection =
            TextSelection.collapsed(offset: joined.length);
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      autofocus: widget.autofocus,
      maxLines: widget.maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _listening ? 'Stop' : 'Dictate',
          icon: Icon(_listening ? Icons.mic : Icons.mic_none,
              color: _listening ? Theme.of(context).colorScheme.primary : null),
          onPressed: _toggle,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(searching ? Icons.search_off : Icons.lightbulb_outline,
                size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              searching
                  ? 'No ideas match your search.'
                  : 'No ideas yet. Tap "New idea" to capture one — type or use the mic.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _dateLabel(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[t.month - 1]} ${t.day}, ${t.year}';
}
