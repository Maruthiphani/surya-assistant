import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/inventory_item.dart';
import '../providers/providers.dart';
import '../services/inventory_repository.dart';

/// Shared / personal inventory (CLAUDE.md §10, Phase 7b). Two lists that are two
/// states of one product:
///  - **Present Items** — already at home.
///  - **Need to Buy** — still to purchase.
///
/// Any family member can add/edit/move/delete. The one-tap **Bought** action
/// flips a needed item to present for everyone at once — because the list is a
/// live shared listener, that's what stops two people buying the same thing.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(inventoryModeProvider);
    final family = ref.watch(familyProvider).valueOrNull;
    final inFamily = family != null;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(mode == InventoryMode.family
              ? (family?.name ?? 'Family inventory')
              : 'My inventory'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Present'),
              Tab(text: 'Need to Buy'),
            ],
          ),
        ),
        body: Column(
          children: [
            _ModeSwitch(mode: mode, inFamily: inFamily),
            Expanded(
              child: TabBarView(
                children: [
                  _ItemList(state: ItemState.present),
                  _ItemList(state: ItemState.needed),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton.extended(
            onPressed: () {
              // Default the new item to the list the user is currently viewing.
              final tab = DefaultTabController.of(ctx).index;
              _showItemSheet(
                context,
                ref,
                initialState:
                    tab == 0 ? ItemState.present : ItemState.needed,
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
        ),
      ),
    );
  }
}

/// Personal ⇄ Family toggle. Family is selectable only when the user is in one;
/// otherwise it's disabled with a hint pointing at the Family screen.
class _ModeSwitch extends ConsumerWidget {
  const _ModeSwitch({required this.mode, required this.inFamily});
  final InventoryMode mode;
  final bool inFamily;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<InventoryMode>(
            segments: const [
              ButtonSegment(
                value: InventoryMode.personal,
                label: Text('Personal'),
                icon: Icon(Icons.person_outline),
              ),
              ButtonSegment(
                value: InventoryMode.family,
                label: Text('Family'),
                icon: Icon(Icons.groups_outlined),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (sel) {
              final next = sel.first;
              if (next == InventoryMode.family && !inFamily) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(const SnackBar(
                    content: Text(
                        'Join or create a family first (Settings → Family).'),
                  ));
                return;
              }
              ref.read(inventoryModeProvider.notifier).state = next;
            },
          ),
          if (mode == InventoryMode.family)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Shared with everyone in your family.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemList extends ConsumerWidget {
  const _ItemList({required this.state});
  final ItemState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(inventoryItemsProvider);
    final scope = ref.watch(inventoryScopeProvider);

    if (scope == null) {
      return const _Empty(
        icon: Icons.group_off_outlined,
        message: 'Join or create a family to use the shared inventory.',
      );
    }

    return itemsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Empty(
        icon: Icons.error_outline,
        message: 'Could not load the inventory.\n$e',
      ),
      data: (_) {
        final items = state == ItemState.present
            ? ref.watch(presentItemsProvider)
            : ref.watch(neededItemsProvider);
        if (items.isEmpty) {
          return _Empty(
            icon: state == ItemState.present
                ? Icons.kitchen_outlined
                : Icons.shopping_cart_outlined,
            message: state == ItemState.present
                ? 'Nothing marked as at home yet.'
                : 'Nothing on the shopping list.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) => _ItemTile(item: items[i], scope: scope),
        );
      },
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item, required this.scope});
  final InventoryItem item;
  final InventoryScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(inventoryRepositoryProvider);
    final actor = ref.read(inventoryActorProvider);
    final subtitle = _subtitle(scope.isFamily);

    return ListTile(
      title: Text(item.name),
      subtitle: subtitle == null ? null : Text(subtitle),
      leading: Icon(item.isPresent
          ? Icons.check_circle_outline
          : Icons.radio_button_unchecked),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (actor != null && item.isNeeded)
            // The anti-duplicate loop: one tap moves it to Present for everyone.
            FilledButton.tonalIcon(
              onPressed: () => repo.moveTo(scope, item.id, ItemState.present,
                  actor: actor),
              icon: const Icon(Icons.shopping_bag_outlined, size: 18),
              label: const Text('Bought'),
            )
          else if (actor != null && item.isPresent)
            TextButton.icon(
              onPressed: () => repo.moveTo(scope, item.id, ItemState.needed,
                  actor: actor),
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text('Need'),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') {
                _showItemSheet(context, ref, existing: item);
              } else if (v == 'delete') {
                _confirmDelete(context, repo, scope, item);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  /// "2 bags · updated 5m ago by Asha". Quantity always shown; the "by" part
  /// only for a shared (family) inventory where it's meaningful.
  String? _subtitle(bool showWho) {
    final parts = <String>[];
    if (item.quantity != null) parts.add(item.quantity!);
    final when = _relativeTime(item.lastUpdatedAt);
    if (when != null) {
      final who = (showWho && item.updatedByName != null)
          ? ' by ${item.updatedByName}'
          : '';
      parts.add('updated $when$who');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  InventoryRepository repo,
  InventoryScope scope,
  InventoryItem item,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${item.name}"?'),
      content: const Text(
          'This removes it from the inventory for everyone. This is different '
          'from dismissing a notification.'),
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
    await repo.deleteItem(scope, item.id);
  }
}

/// Add/edit bottom sheet. On add, warns if the same product already exists in
/// Present Items (the duplicate-purchase guard, CLAUDE.md §10).
Future<void> _showItemSheet(
  BuildContext context,
  WidgetRef ref, {
  InventoryItem? existing,
  ItemState initialState = ItemState.needed,
}) async {
  final scope = ref.read(inventoryScopeProvider);
  final actor = ref.read(inventoryActorProvider);
  if (scope == null || actor == null) return;

  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final qtyCtrl = TextEditingController(text: existing?.quantity ?? '');
  final hintCtrl = TextEditingController(text: existing?.locationQuery ?? '');
  var state = existing?.state ?? initialState;
  final repo = ref.read(inventoryRepositoryProvider);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(existing == null ? 'Add item' : 'Edit item',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Item',
                  hintText: 'e.g. rice',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Quantity (optional)',
                  hintText: 'e.g. 2 bags',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hintCtrl,
                decoration: const InputDecoration(
                  labelText: 'Where to buy (optional)',
                  hintText: 'e.g. grocery store',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<ItemState>(
                segments: const [
                  ButtonSegment(
                      value: ItemState.present, label: Text('At home')),
                  ButtonSegment(
                      value: ItemState.needed, label: Text('Need to buy')),
                ],
                selected: {state},
                onSelectionChanged: (s) => setState(() => state = s.first),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;

                  if (existing == null) {
                    // Duplicate guard: already at home?
                    final present = ref.read(presentItemsProvider);
                    final dupe = present.any(
                        (p) => p.dedupeKey == name.toLowerCase().trim());
                    if (dupe && state == ItemState.needed) {
                      final proceed = await _confirmDuplicate(ctx, name);
                      if (proceed != true) return;
                    }
                    await repo.addItem(
                      scope,
                      name: name,
                      state: state,
                      quantity: qtyCtrl.text,
                      locationQuery: hintCtrl.text,
                      actor: actor,
                    );
                  } else {
                    await repo.updateItem(
                      scope,
                      existing.id,
                      name: name,
                      quantity: qtyCtrl.text,
                      locationQuery: hintCtrl.text,
                      actor: actor,
                    );
                    if (state != existing.state) {
                      await repo.moveTo(scope, existing.id, state,
                          actor: actor);
                    }
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: Text(existing == null ? 'Add' : 'Save'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<bool?> _confirmDuplicate(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Already at home'),
      content: Text(
          '"$name" is already in Present Items. Add it to the shopping list '
          'anyway?'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add anyway')),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Compact relative time ("just now", "5m ago", "3h ago", "2d ago"). Returns
/// null for a not-yet-synced server timestamp so the label simply omits it.
String? _relativeTime(DateTime? t) {
  if (t == null) return null;
  final diff = DateTime.now().difference(t);
  if (diff.isNegative) return 'just now';
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final weeks = diff.inDays ~/ 7;
  return '${weeks}w ago';
}
