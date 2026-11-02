import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/app_config.dart';

/// Billing / entitlements (CLAUDE.md §1, Phase 6) via RevenueCat.
///
/// Two tiers: Free (capped active reminders) and Pro (unlimited), gated by the
/// `pro` entitlement. Kept behind an interface (CLAUDE.md §5) so it can be
/// faked in tests and so the UI depends on the contract, not RevenueCat.
///
/// **Graceful degradation (CLAUDE.md §9 spirit — never block the core app on a
/// paid service):** if no RevenueCat key is configured for the platform (the
/// dev default), billing is considered unavailable: [isConfigured] is false,
/// the user is treated as Free, offerings are empty and purchases are no-ops.
/// The free-tier limit still applies, so the app is fully usable without keys.
abstract class SubscriptionService {
  /// Whether a RevenueCat key is configured for this platform. When false the
  /// app runs in Free-only mode and the paywall explains billing is off.
  bool get isConfigured;

  /// Configure the SDK (no-op when not [isConfigured]). Call once at startup.
  Future<void> init();

  /// Associate purchases with the signed-in user (RevenueCat appUserID = uid).
  Future<void> identify(String uid);

  /// Detach the user (on sign-out).
  Future<void> logOut();

  /// Current Pro status (false when billing is unavailable).
  Future<bool> isPro();

  /// Live Pro status; emits on purchase/restore/expiry. Starts with the
  /// current value.
  Stream<bool> get proStatus;

  /// Packages the user can buy (empty when billing is unavailable).
  Future<List<Package>> offerings();

  /// Purchase a package; returns the resulting Pro status. Throws on a real
  /// store error (callers should catch and show a message); a user cancel
  /// resolves to the current (false) status rather than throwing.
  Future<bool> purchase(Package package);

  /// Restore previous purchases; returns the resulting Pro status.
  Future<bool> restore();
}

class RevenueCatSubscriptionService implements SubscriptionService {
  final _proController = StreamController<bool>.broadcast();
  bool _lastPro = false;
  bool _initialised = false;

  /// Resolve the platform key; empty string means "not configured".
  String get _apiKey {
    try {
      if (Platform.isAndroid) return AppConfig.revenueCatApiKeyAndroid;
      if (Platform.isIOS) return AppConfig.revenueCatApiKeyIos;
    } catch (_) {
      // Platform unavailable (tests/desktop) → unconfigured.
    }
    return '';
  }

  @override
  bool get isConfigured => _apiKey.isNotEmpty;

  @override
  Stream<bool> get proStatus async* {
    yield _lastPro;
    yield* _proController.stream;
  }

  @override
  Future<void> init() async {
    if (_initialised || !isConfigured) return;
    _initialised = true;
    await Purchases.setLogLevel(
        kDebugMode ? LogLevel.debug : LogLevel.info);
    await Purchases.configure(PurchasesConfiguration(_apiKey));
    // Push entitlement changes into the stream.
    Purchases.addCustomerInfoUpdateListener((info) {
      _updateFrom(info);
    });
    try {
      _updateFrom(await Purchases.getCustomerInfo());
    } catch (e) {
      debugPrint('RevenueCat getCustomerInfo failed: $e');
    }
  }

  void _updateFrom(CustomerInfo info) {
    final pro =
        info.entitlements.active.containsKey(AppConfig.proEntitlementId);
    _lastPro = pro;
    if (!_proController.isClosed) _proController.add(pro);
  }

  @override
  Future<void> identify(String uid) async {
    if (!isConfigured) return;
    try {
      final result = await Purchases.logIn(uid);
      _updateFrom(result.customerInfo);
    } catch (e) {
      debugPrint('RevenueCat logIn failed: $e');
    }
  }

  @override
  Future<void> logOut() async {
    if (!isConfigured) return;
    try {
      // logOut throws if the user is already anonymous — ignore that.
      final info = await Purchases.logOut();
      _updateFrom(info);
    } catch (e) {
      debugPrint('RevenueCat logOut skipped: $e');
    }
  }

  @override
  Future<bool> isPro() async {
    if (!isConfigured) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      _updateFrom(info);
      return _lastPro;
    } catch (e) {
      debugPrint('RevenueCat isPro check failed: $e');
      return _lastPro;
    }
  }

  @override
  Future<List<Package>> offerings() async {
    if (!isConfigured) return const [];
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? const [];
    } catch (e) {
      debugPrint('RevenueCat getOfferings failed: $e');
      return const [];
    }
  }

  @override
  Future<bool> purchase(Package package) async {
    if (!isConfigured) return false;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _updateFrom(result.customerInfo);
      return _lastPro;
    } on PlatformException catch (e) {
      // A user cancellation is not an error we surface — stay on current tier.
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return _lastPro;
      rethrow;
    }
  }

  @override
  Future<bool> restore() async {
    if (!isConfigured) return false;
    final info = await Purchases.restorePurchases();
    _updateFrom(info);
    return _lastPro;
  }
}
