import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../l10n/app_language.dart';
import '../models/user_profile.dart';
import '../providers/providers.dart';
import 'family_screen.dart';
import 'paywall_screen.dart';

/// Settings (CLAUDE.md Phase 5): rename the assistant and set the default
/// geofence radius used to pre-fill new reminders.
///
/// Both values live on the `users/{uid}` profile doc and are written via
/// [UserRepository], so changes sync and the live [userProfileProvider] stream
/// updates the rest of the app automatically.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _radiusController;
  bool _busy = false;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _radiusController = TextEditingController();
  }

  /// Seed the fields from the profile once it has loaded (the provider may
  /// still be loading on first build).
  void _seedFromProfile(UserProfile profile) {
    if (_initialised) return;
    _nameController.text = profile.assistantName;
    _radiusController.text = profile.defaultRadiusMeters.toString();
    _initialised = true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    final name = _nameController.text.trim();
    final radius = int.parse(_radiusController.text.trim());

    setState(() => _busy = true);
    try {
      final repo = ref.read(userRepositoryProvider);
      await repo.setAssistantName(uid, name);
      await repo.setDefaultRadius(uid, radius);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text(ref.read(stringsProvider).settingsSaved)));
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
              const SnackBar(content: Text('Could not save. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final s = ref.watch(stringsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(s.settingsTitle)),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load settings.\n$e')),
          data: (profile) {
            final p = profile ??
                UserProfile(
                  uid: ref.read(currentUidProvider) ?? '',
                  assistantName: UserProfile.defaultAssistantName,
                );
            _seedFromProfile(p);
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(s.assistantSection,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: s.assistantNameLabel,
                      helperText: 'Used in confirmations and notifications.',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 28),
                  Text(s.languageSection,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _LanguageTile(),
                  const SizedBox(height: 28),
                  Text(s.remindersSection,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _radiusController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: s.defaultRadiusLabel,
                      helperText:
                          'Pre-filled for new reminders. You can change it per '
                          'reminder.',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n <= 0) return 'Enter a positive number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  Text('Family',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _FamilyTile(),
                  const SizedBox(height: 28),
                  Text('Subscription',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _SubscriptionTile(),
                  const SizedBox(height: 32),
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
                        : Text(s.save),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Language picker — the language Hanu speaks, listens, and renders in
/// (CLAUDE.md Phase 9). Writes immediately to the profile so the whole app
/// (via `appLanguageProvider`/`stringsProvider`) updates live.
class _LanguageTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appLanguageProvider);
    final s = ref.watch(stringsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.translate),
            const SizedBox(width: 16),
            Expanded(child: Text(s.languageLabel)),
            DropdownButton<AppLanguage>(
              value: current,
              underline: const SizedBox.shrink(),
              items: AppLanguage.values
                  .map((l) =>
                      DropdownMenuItem(value: l, child: Text(l.displayName)))
                  .toList(),
              onChanged: (l) async {
                final uid = ref.read(currentUidProvider);
                if (l == null || uid == null) return;
                await ref
                    .read(userRepositoryProvider)
                    .setPreferredLanguage(uid, l);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the user's family (or "Not in a family") and opens the Family screen
/// to create/join/manage it (CLAUDE.md §10, Phase 7a).
class _FamilyTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final familyAsync = ref.watch(familyProvider);
    final family = familyAsync.valueOrNull;
    final inFamily = family != null;

    return Card(
      child: ListTile(
        leading: Icon(
          inFamily ? Icons.groups : Icons.group_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(inFamily ? family.name : 'Not in a family'),
        subtitle: Text(inFamily
            ? '${family.memberCount} '
                '${family.memberCount == 1 ? 'member' : 'members'} · shared inventory'
            : 'Create or join a family to share lists'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FamilyScreen()),
        ),
      ),
    );
  }
}

/// Shows the current tier (Free N/limit, or Pro) and opens the paywall.
class _SubscriptionTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider).valueOrNull ?? false;
    final activeCount = ref.watch(activeReminderCountProvider);

    return Card(
      child: ListTile(
        leading: Icon(
          isPro ? Icons.workspace_premium : Icons.star_outline,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(isPro ? 'Surya Pro' : 'Free'),
        subtitle: Text(isPro
            ? 'Unlimited active reminders'
            : '$activeCount of ${AppConfig.freeActiveReminderLimit} active '
                'reminders used'),
        trailing: isPro ? null : const Icon(Icons.chevron_right),
        onTap: isPro
            ? null
            : () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PaywallScreen()),
                ),
      ),
    );
  }
}
