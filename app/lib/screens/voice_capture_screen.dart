import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/reminder_composer.dart';
import 'add_reminder_screen.dart';

/// Capture a reminder by voice (or typed — a fallback that also makes this
/// testable on an emulator without a working mic). The transcript is routed
/// through the local-first [ReminderComposer] (CLAUDE.md §9): RESOLVED/CLARIFY
/// open the review screen prefilled; UNPARSEABLE already hit the LLM inside the
/// composer; failures let the user retry.
class VoiceCaptureScreen extends ConsumerStatefulWidget {
  const VoiceCaptureScreen({super.key, this.initialText});

  /// Optional pre-filled command text (e.g. from a Siri Shortcut, Phase 5).
  /// When provided, it's shown in the field and composed automatically.
  final String? initialText;

  @override
  ConsumerState<VoiceCaptureScreen> createState() => _VoiceCaptureScreenState();
}

class _VoiceCaptureScreenState extends ConsumerState<VoiceCaptureScreen> {
  final _textController = TextEditingController();
  String _transcript = '';
  bool _listening = false;
  bool _busy = false;
  bool _speechAvailable = true;

  @override
  void initState() {
    super.initState();
    final prefill = widget.initialText?.trim();
    if (prefill != null && prefill.isNotEmpty) {
      _textController.text = prefill;
      _transcript = prefill;
      // Compose after first frame so provider reads + navigation are safe.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _process(prefill));
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    final speech = ref.read(speechServiceProvider);
    if (_listening) {
      await speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await speech.init();
    if (!ok) {
      setState(() => _speechAvailable = false);
      _snack('Speech recognition unavailable — type your reminder below.');
      return;
    }
    setState(() {
      _listening = true;
      _transcript = '';
    });
    await speech.listen(
      onResult: (text, isFinal) {
        setState(() {
          _transcript = text;
          _textController.text = text;
        });
        if (isFinal && text.trim().isNotEmpty) _process(text);
      },
      onDone: () => setState(() => _listening = false),
    );
  }

  Future<void> _process(String transcript) async {
    if (_busy) return;
    final text = transcript.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);

    final here = await ref.read(locationServiceProvider).currentLatLng();
    final result = await ref
        .read(reminderComposerProvider)
        .compose(text, lat: here?.lat, lng: here?.lng);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case ComposeResolved(:final draft):
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AddReminderScreen(initial: draft)),
        );
      case ComposeClarify(:final prompt, :final partialDraft):
        _snack(prompt);
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => AddReminderScreen(initial: partialDraft)),
        );
      case ComposeFailed(:final message):
        _snack(message);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Speak a reminder')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _busy ? null : _toggleMic,
                child: CircleAvatar(
                  radius: 56,
                  backgroundColor: _listening
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primaryContainer,
                  child: Icon(
                    _listening ? Icons.mic : Icons.mic_none,
                    size: 56,
                    color: _listening
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _listening
                    ? 'Listening…'
                    : _speechAvailable
                        ? 'Tap the mic and say your reminder'
                        : 'Mic unavailable — type below',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'e.g. "remind me to buy milk at Walmart"',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              if (_transcript.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('"$_transcript"',
                    style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              ],
              const Spacer(),
              // Typed fallback (also used on emulators without speech).
              TextField(
                controller: _textController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Or type a command',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: _busy ? null : _process,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    _busy ? null : () => _process(_textController.text),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_forward),
                label: const Text('Continue'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
