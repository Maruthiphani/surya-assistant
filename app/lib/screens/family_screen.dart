import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Hide Riverpod's internal `Family` type so it doesn't clash with our model.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import '../models/family.dart';
import '../providers/providers.dart';
import '../services/family_repository.dart';

/// Family sharing (CLAUDE.md §10, Phase 7a): create a family, share the invite
/// code, join one with a code, and see members. This is the foundation — the
/// shared inventory (Phase 7b) is built under the same family later.
///
/// Entirely additive: reachable from Settings and never touches reminders.
class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final familyId = ref.watch(familyIdProvider);
    final familyAsync = ref.watch(familyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Family')),
      body: SafeArea(
        child: uid == null
            ? const Center(child: Text('Please sign in.'))
            : familyAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Could not load your family.\n$e')),
                data: (family) {
                  if (family != null) {
                    return _FamilyDetails(uid: uid, family: family);
                  }
                  // No live family. If a pointer is still set, it's stale
                  // (the family was disbanded) — offer to clear it.
                  if (familyId != null && familyId.isNotEmpty) {
                    return _StalePointer(uid: uid);
                  }
                  return _NoFamily(uid: uid);
                },
              ),
      ),
    );
  }
}

/// Create-or-join entry point shown when the user isn't in a family.
class _NoFamily extends ConsumerStatefulWidget {
  const _NoFamily({required this.uid});
  final String uid;

  @override
  ConsumerState<_NoFamily> createState() => _NoFamilyState();
}

class _NoFamilyState extends ConsumerState<_NoFamily> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on FamilyException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _create() => _run(() async {
        await ref.read(familyRepositoryProvider).createFamily(
              uid: widget.uid,
              name: _nameController.text,
              displayName: ref.read(currentDisplayNameProvider),
            );
        _snack('Family created. Share your invite code with the family.');
      });

  Future<void> _join() => _run(() async {
        await ref.read(familyRepositoryProvider).joinByCode(
              uid: widget.uid,
              code: _codeController.text,
              displayName: ref.read(currentDisplayNameProvider),
            );
        _snack('Joined the family.');
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Share one inventory with your family — everyone can add what you '
          'have at home and what you still need to buy.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 28),
        Text('Create a family', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Family name',
            hintText: 'e.g. Sharma family',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.group_add),
          label: const Text('Create family'),
        ),
        const SizedBox(height: 36),
        const Divider(),
        const SizedBox(height: 24),
        Text('Join a family', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Invite code',
            hintText: 'e.g. 7KQ4MP',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _join,
          icon: const Icon(Icons.login),
          label: const Text('Join with code'),
        ),
        if (_busy) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }
}

/// Shown when the user still points at a family that no longer exists.
class _StalePointer extends ConsumerWidget {
  const _StalePointer({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Your family was disbanded by its owner.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await ref.read(familyRepositoryProvider).clearStalePointer(uid);
            },
            child: const Text('OK, leave it'),
          ),
        ],
      ),
    );
  }
}

/// The in-family view: invite code, members, and leave/disband.
class _FamilyDetails extends ConsumerWidget {
  const _FamilyDetails({required this.uid, required this.family});
  final String uid;
  final Family family;

  Future<void> _confirmAndRun(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Done.')));
      }
    } on FamilyException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
              const SnackBar(content: Text('Something went wrong.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isOwner = family.isOwner(uid);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(family.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          '${family.memberCount} '
          '${family.memberCount == 1 ? 'member' : 'members'}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.key),
            title: const Text('Invite code'),
            subtitle: Text(
              family.inviteCode,
              style: theme.textTheme.titleLarge
                  ?.copyWith(letterSpacing: 2, fontFeatures: const []),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy',
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: family.inviteCode));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(
                        content: Text('Invite code copied.')));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Share this code so family members can join.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 28),
        Text('Members', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        ...family.memberUids.map((m) => _MemberTile(
              displayName: family.displayNameFor(m),
              isYou: m == uid,
              isOwner: m == family.ownerUid,
            )),
        const SizedBox(height: 32),
        if (isOwner)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Disband family'),
            onPressed: () => _confirmAndRun(
              context,
              ref,
              title: 'Disband family?',
              message:
                  'This removes the family for everyone. Shared data is '
                  'deleted. This cannot be undone.',
              confirmLabel: 'Disband',
              action: () => ref
                  .read(familyRepositoryProvider)
                  .disbandFamily(uid: uid, familyId: family.id),
            ),
          )
        else
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Leave family'),
            onPressed: () => _confirmAndRun(
              context,
              ref,
              title: 'Leave family?',
              message: 'You will stop sharing this family\'s inventory.',
              confirmLabel: 'Leave',
              action: () => ref
                  .read(familyRepositoryProvider)
                  .leaveFamily(uid: uid, familyId: family.id),
            ),
          ),
      ],
    );
  }
}

/// A member row, showing the member's shared display name (from the family's
/// `memberNames` map, Phase 7b) with a "You"/"Owner" badge.
class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.displayName,
    required this.isYou,
    required this.isOwner,
  });

  final String displayName;
  final bool isYou;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(isYou ? '$displayName (You)' : displayName),
      trailing: isOwner
          ? const Chip(label: Text('Owner'), visualDensity: VisualDensity.compact)
          : null,
    );
  }
}
