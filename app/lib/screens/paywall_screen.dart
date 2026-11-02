import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/app_config.dart';
import '../providers/providers.dart';

/// Upgrade screen for Surya Pro (CLAUDE.md §1, Phase 6).
///
/// Free unlocks up to [AppConfig.freeActiveReminderLimit] active reminders;
/// Pro removes the cap. Lists RevenueCat packages and handles purchase/restore.
/// When billing isn't configured (no key) it explains that gracefully instead
/// of showing a broken store.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _loading = true;
  bool _busy = false;
  List<Package> _packages = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final packages = await ref.read(subscriptionServiceProvider).offerings();
    if (!mounted) return;
    setState(() {
      _packages = packages;
      _loading = false;
    });
  }

  Future<void> _buy(Package package) async {
    setState(() => _busy = true);
    try {
      final pro = await ref.read(subscriptionServiceProvider).purchase(package);
      if (!mounted) return;
      if (pro) {
        _snack('You\'re on Surya Pro — thanks!');
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      _snack('Purchase failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final pro = await ref.read(subscriptionServiceProvider).restore();
      if (!mounted) return;
      _snack(pro ? 'Pro restored.' : 'No previous purchase found.');
      if (pro) Navigator.of(context).pop(true);
    } catch (_) {
      _snack('Could not restore purchases.');
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final isPro = ref.watch(isProProvider).valueOrNull ?? false;
    final configured = ref.read(subscriptionServiceProvider).isConfigured;

    return Scaffold(
      appBar: AppBar(title: const Text('Surya Pro')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.workspace_premium,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Go unlimited', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Free includes up to ${AppConfig.freeActiveReminderLimit} active '
              'location reminders. Pro removes the limit.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            const _ProBenefit(text: 'Unlimited active location reminders'),
            const _ProBenefit(text: 'Dynamic reminders for any chain or category'),
            const _ProBenefit(text: 'Support ongoing development'),
            const SizedBox(height: 24),
            if (isPro)
              Card(
                color: theme.colorScheme.primaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.check_circle),
                  title: Text('You\'re on Pro'),
                  subtitle: Text('Thanks for your support!'),
                ),
              )
            else if (!configured)
              _InfoCard(
                text: 'In-app purchases aren\'t available in this build. '
                    'You can use up to ${AppConfig.freeActiveReminderLimit} '
                    'active reminders on the Free tier.',
              )
            else if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_packages.isEmpty)
              const _InfoCard(
                text: 'No subscription options are available right now. '
                    'Please try again later.',
              )
            else
              ..._packages.map((p) => _PackageTile(
                    package: p,
                    busy: _busy,
                    onBuy: () => _buy(p),
                  )),
            if (configured && !isPro) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _restore,
                child: const Text('Restore purchases'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProBenefit extends StatelessWidget {
  const _ProBenefit({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.busy,
    required this.onBuy,
  });

  final Package package;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final product = package.storeProduct;
    return Card(
      child: ListTile(
        title: Text(product.title),
        subtitle: product.description.isEmpty
            ? null
            : Text(product.description),
        trailing: FilledButton(
          onPressed: busy ? null : onBuy,
          child: Text(product.priceString),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
