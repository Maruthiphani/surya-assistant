import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/reminder.dart';
import '../models/user_profile.dart';
import '../providers/providers.dart';
import '../services/ai_service.dart';
import 'paywall_screen.dart';
import 'pick_location_screen.dart';

/// Review-and-save screen for a reminder (CLAUDE.md §9 — always confirm).
///
/// Used three ways, all editable before saving:
/// - manual "Add reminder" (empty),
/// - voice/text RESOLVED (prefilled from the parse),
/// - CLARIFY (prefilled with the known slot; the missing one is blank).
///
/// Dynamic (chain/category) reminders save with no coordinates. Specific places
/// are geocoded via `/v1/nearby` (picker if >1). A parsed time is shown but not
/// yet scheduled (location remains the trigger).
class AddReminderScreen extends ConsumerStatefulWidget {
  const AddReminderScreen({super.key, this.initial});

  /// Optional prefill (from voice/text parsing).
  final Reminder? initial;

  @override
  ConsumerState<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends ConsumerState<AddReminderScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _taskController;
  late final TextEditingController _locationController;
  late final TextEditingController _radiusController;
  late bool _anyBranch;
  DateTime? _remindAt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _taskController = TextEditingController(text: i?.task ?? '');
    _locationController = TextEditingController(text: i?.locationName ?? '');
    // Pre-fill radius from the prefill if present, else the user's configured
    // default (Settings, Phase 5), else the model default.
    final defaultRadius =
        ref.read(userProfileProvider).valueOrNull?.defaultRadiusMeters ??
            UserProfile.defaultRadius;
    _radiusController = TextEditingController(
        text: (i?.radiusMeters ?? defaultRadius).toString());
    _anyBranch = i == null || i.locationType == LocationType.query;
    _remindAt = i?.remindAt;
  }

  @override
  void dispose() {
    _taskController.dispose();
    _locationController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  String get _assistantName =>
      ref.read(userProfileProvider).valueOrNull?.assistantName ??
      UserProfile.defaultAssistantName;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    // Free-tier cap (CLAUDE.md §1): block a new active reminder past the limit
    // unless the user is Pro, and offer the upgrade.
    if (!await _ensureWithinFreeLimit()) return;

    final task = _taskController.text.trim();
    final location = _locationController.text.trim();
    final radius = int.tryParse(_radiusController.text.trim()) ?? 500;

    setState(() => _busy = true);
    try {
      Reminder reminder;
      if (_anyBranch) {
        // Dynamic: no coordinates; branches discovered at runtime. Works offline.
        reminder = Reminder(
          task: task,
          locationName: location,
          locationType: LocationType.query,
          locationQuery: location,
          radiusMeters: radius,
          remindAt: _remindAt,
          status: ReminderStatus.active,
        );
      } else {
        // Specific: geocode via Places (picker if >1). Needs location + network.
        final chosen = await _resolveSpecific(location);
        if (chosen == null) return; // cancelled or failed (message already shown)
        reminder = Reminder(
          task: task,
          locationName: chosen.name,
          locationType: LocationType.specific,
          address: chosen.address,
          lat: chosen.lat,
          lng: chosen.lng,
          radiusMeters: radius,
          remindAt: _remindAt,
          status: ReminderStatus.active,
        );
      }

      await ref.read(reminderRepositoryProvider).addReminder(uid, reminder);
      final message = await _confirmationMessage(task, reminder.locationName);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop();
    } catch (_) {
      _snack('Could not save reminder. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Returns true if a new active reminder is allowed. On the Free tier, once
  /// the active count hits the limit, routes to the paywall and returns false.
  Future<bool> _ensureWithinFreeLimit() async {
    final isPro = ref.read(isProProvider).valueOrNull ?? false;
    if (isPro) return true;
    final activeCount = ref.read(activeReminderCountProvider);
    if (activeCount < AppConfig.freeActiveReminderLimit) return true;

    _snack('Free tier allows ${AppConfig.freeActiveReminderLimit} active '
        'reminders. Upgrade to Pro for unlimited.');
    if (!mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
    // Re-check: the user may have upgraded on the paywall.
    final nowPro = ref.read(isProProvider).valueOrNull ?? false;
    return nowPro;
  }

  /// Resolve a specific place name to one candidate (picker if several).
  Future<PlaceCandidate?> _resolveSpecific(String query) async {
    final here = await ref.read(locationServiceProvider).currentLatLng();
    if (here == null) {
      _snack('Need your location to find that place. Enable location, or use '
          '"Match any branch".');
      return null;
    }
    List<PlaceCandidate> candidates;
    try {
      candidates =
          await ref.read(aiServiceProvider).nearby(query, here.lat, here.lng, limit: 3);
    } catch (_) {
      _snack('Could not reach the server to find that place (offline?).');
      return null;
    }
    if (candidates.isEmpty) {
      _snack('Couldn\'t find "$query" near you.');
      return null;
    }
    if (candidates.length == 1) return candidates.first;
    if (!mounted) return null;
    return Navigator.of(context).push<PlaceCandidate>(
      MaterialPageRoute(builder: (_) => PickLocationScreen(candidates: candidates)),
    );
  }

  /// Friendly confirmation using the assistant name; falls back locally offline.
  Future<String> _confirmationMessage(String task, String locationName) async {
    try {
      return await ref
          .read(aiServiceProvider)
          .confirm(task, locationName, _assistantName);
    } catch (_) {
      return 'Got it — I\'ll remind you to $task when you reach $locationName.';
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New reminder')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _taskController,
                autofocus: _taskController.text.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Task',
                  hintText: 'e.g. buy rice',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a task' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _anyBranch ? 'Chain or category' : 'Place name',
                  hintText:
                      _anyBranch ? 'e.g. Costco, pharmacy' : 'e.g. Costco, Cumming',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a location' : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _anyBranch,
                onChanged: (v) => setState(() => _anyBranch = v),
                title: const Text('Match any branch'),
                subtitle: Text(_anyBranch
                    ? 'Fires at any nearby branch of this chain/category.'
                    : 'Fires only at this one specific place.'),
              ),
              if (_remindAt != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Heard a time ($_remindAtLabel) — time-based reminders are '
                        'coming soon; this fires by location for now.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _radiusController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Radius (metres)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n <= 0) return 'Enter a positive number';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save reminder'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _remindAtLabel {
    final t = _remindAt!;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m $ampm';
  }
}
