import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Active access always comes from RevenueCat, including grace periods.
/// Cancellation does not remove access until the store entitlement expires.
class SubscriptionStatus {
  const SubscriptionStatus({
    this.isPro = false,
    this.isTrial = false,
    this.willRenew = false,
    this.hasBillingIssue = false,
    this.expirationDate,
    this.managementUrl,
    this.productIdentifier,
  });
  final bool isPro;
  final bool isTrial;
  final bool willRenew;
  final bool hasBillingIssue;
  final DateTime? expirationDate;
  final String? managementUrl;
  final String? productIdentifier;

  factory SubscriptionStatus.fromCustomerInfo(CustomerInfo info) {
    final entitlement = info.entitlements.all['pro'];
    return SubscriptionStatus(
      isPro: entitlement?.isActive ?? false,
      isTrial:
          entitlement?.isActive == true &&
          entitlement?.periodType == PeriodType.trial,
      willRenew: entitlement?.willRenew ?? false,
      hasBillingIssue: entitlement?.billingIssueDetectedAt != null,
      expirationDate: DateTime.tryParse(entitlement?.expirationDate ?? ''),
      managementUrl: info.managementURL,
      productIdentifier: entitlement?.productIdentifier,
    );
  }
}

class SubscriptionService {
  final _changes = StreamController<SubscriptionStatus>.broadcast();
  Stream<SubscriptionStatus> get changes => _changes.stream;
  bool _configured = false;
  String? _userId;
  bool _acceptUpdates = false;
  int _generation = 0;
  Future<void> _identityWork = Future<void>.value();
  bool get isConfigured => _configured;

  /// Owner of accepted SDK updates. The controller also checks this against its
  /// current Firebase UID while a different account is still opening.
  String? get activeUserId => _acceptUpdates ? _userId : null;
  SubscriptionStatus _status = const SubscriptionStatus();
  SubscriptionStatus get status => _status;

  Future<void> configure({
    required String iosApiKey,
    required String androidApiKey,
    required String userId,
  }) async {
    final generation = _invalidateAccount();
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return;
    }
    final key = defaultTargetPlatform == TargetPlatform.iOS
        ? iosApiKey
        : androidApiKey;
    if (key.isEmpty || userId.isEmpty) return;
    await _queueIdentity(() async {
      if (generation != _generation) return;
      CustomerInfo? customerInfo;
      if (_configured) {
        customerInfo = (await Purchases.logIn(userId)).customerInfo;
      } else {
        await Purchases.setLogLevel(
          kReleaseMode ? LogLevel.error : LogLevel.warn,
        );
        if (generation != _generation) return;
        await Purchases.configure(
          PurchasesConfiguration(key)..appUserID = userId,
        );
        Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
        _configured = true;
      }
      if (generation != _generation) return;
      _userId = userId;
      _acceptUpdates = true;
      if (customerInfo != null) {
        _onCustomerInfo(customerInfo);
      } else {
        await refresh();
      }
    });
  }

  Future<Offerings> offerings() {
    _requireConfigured();
    return Purchases.getOfferings();
  }

  /// Display the returned store price and native eligibility before checkout.
  Future<Map<String, IntroEligibility>> trialEligibility(
    List<String> productIds,
  ) {
    _requireConfigured();
    return Purchases.checkTrialOrIntroductoryPriceEligibility(productIds);
  }

  Future<SubscriptionStatus> purchase(Package package) async {
    _requireConfigured();
    final generation = _generation;
    final result = await Purchases.purchase(PurchaseParams.package(package));
    _assertCurrent(generation);
    _onCustomerInfo(result.customerInfo);
    return _status;
  }

  Future<SubscriptionStatus> restore() async {
    _requireConfigured();
    final generation = _generation;
    final info = await Purchases.restorePurchases();
    _assertCurrent(generation);
    _onCustomerInfo(info);
    return _status;
  }

  Future<SubscriptionStatus> refresh() async {
    _requireConfigured();
    final generation = _generation;
    final info = await Purchases.getCustomerInfo();
    _assertCurrent(generation);
    _onCustomerInfo(info);
    return _status;
  }

  Future<void> manageSubscription() async {
    _requireConfigured();
    final generation = _generation;
    final info = await Purchases.getCustomerInfo();
    _assertCurrent(generation);
    final url =
        info.managementURL ??
        (defaultTargetPlatform == TargetPlatform.iOS
            ? 'https://apps.apple.com/account/subscriptions'
            : 'https://play.google.com/store/account/subscriptions');
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw StateError('Unable to open subscription settings.');
    }
  }

  Future<void> signOut() async {
    final generation = _invalidateAccount();
    await _queueIdentity(() async {
      if (generation != _generation) return;
      if (_configured && !await Purchases.isAnonymous) await Purchases.logOut();
    });
  }

  int _invalidateAccount() {
    ++_generation;
    _acceptUpdates = false;
    _userId = null;
    _status = const SubscriptionStatus();
    if (!_changes.isClosed) _changes.add(_status);
    return _generation;
  }

  Future<void> _queueIdentity(Future<void> Function() operation) {
    // Native logIn/logOut also mutate global SDK identity. Serialize those calls,
    // so an older slow logIn cannot become the last active native account.
    final next = _identityWork
        .catchError((Object _) {})
        .then((_) => operation());
    _identityWork = next;
    return next;
  }

  void _assertCurrent(int generation) {
    if (generation != _generation) {
      throw StateError('Your subscription account changed. Please try again.');
    }
    _requireConfigured();
  }

  void _onCustomerInfo(CustomerInfo info) {
    if (!_acceptUpdates) return;
    _status = SubscriptionStatus.fromCustomerInfo(info);
    if (!_changes.isClosed) _changes.add(_status);
  }

  void _requireConfigured() {
    if (!_configured || _userId == null || !_acceptUpdates) {
      throw StateError(
        'Subscriptions require a signed-in account and store configuration.',
      );
    }
  }

  Future<void> dispose() async {
    _invalidateAccount();
    await _identityWork.catchError((Object _) {});
    if (_configured) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    }
    await _changes.close();
  }
}
