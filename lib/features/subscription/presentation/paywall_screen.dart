import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/state.dart';
import '../../dashboard/presentation/design.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});
  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool annual = true;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() async {
      await ref.read(appProvider.notifier).loadOfferings();
      if (mounted) setState(() => loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final annualPackages = state.packages.where(
      (p) => p.packageType == PackageType.annual,
    );
    final monthlyPackages = state.packages.where(
      (p) => p.packageType == PackageType.monthly,
    );
    final annualProduct = annualPackages.isEmpty
        ? null
        : annualPackages.first.storeProduct;
    final monthlyProduct = monthlyPackages.isEmpty
        ? null
        : monthlyPackages.first.storeProduct;
    final product = annual ? annualProduct : monthlyProduct;
    final trial = annual && state.trialEligible;
    final status = state.subscription;
    return ScreenFrame(
      back: true,
      child: Column(
        children: [
          gap(10),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: lime,
              borderRadius: BorderRadius.circular(21),
              boxShadow: [
                BoxShadow(
                  color: lime.withValues(alpha: 0.15),
                  blurRadius: 45,
                  spreadRadius: 15,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: ink, size: 34),
          ),
          gap(20),
          eyebrow('LeanGuard Pro', color: lime),
          gap(12),
          heading(
            state.isPro ? 'Your strength.\nYour plan.' : 'Keep the weight off.',
            size: 31,
          ),
          if (!state.isPro) ...[
            gap(4),
            Text(
              'Keep what makes\nyou strong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: lime,
                fontSize: 31,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.9,
                height: 1.1,
              ),
            ),
          ],
          gap(16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Personal guidance that adapts as your body, habits and strength change.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 14, height: 1.5),
            ),
          ),
          gap(24),
          for (final benefit in [
            'Personalized strength plans & progression',
            'AI weekly insights & up to 100 coach messages',
            'Adaptive protein & walking targets',
            'Advanced health trends & workout sync',
            'Optional appetite-aware GLP-1 support',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Row(
                children: [
                  Container(
                    width: 23,
                    height: 23,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2B3825),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: lime,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(benefit, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          gap(15),
          if (state.isPro) ...[
            DesignCard(
              border: const Color(0xFF596E3F),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.isTrial
                        ? 'Your trial is active'
                        : 'Your Pro membership is active',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  gap(8),
                  subtext(
                    status.hasBillingIssue
                        ? 'There is a billing issue. Update your payment method in your store settings. Access follows your current store entitlement.'
                        : !status.willRenew
                        ? 'Renewal is canceled. Your Pro access continues until your current period ends.'
                        : 'Your membership renews automatically until canceled.',
                  ),
                  if (status.expirationDate != null) ...[
                    gap(8),
                    subtext(
                      'Current period ends ${status.expirationDate!.toLocal().toString().split(' ').first}',
                    ),
                  ],
                ],
              ),
            ),
            gap(18),
            PrimaryAction(
              'Manage subscription',
              onPressed: () =>
                  ref.read(appProvider.notifier).manageSubscription(),
            ),
            gap(8),
          ] else ...[
            _option(
              title: 'Annual',
              subtitle:
                  '${annualProduct?.priceString ?? '\$119.99'} billed yearly',
              price: annualProduct?.priceString ?? '\$119.99',
              period: '/year',
              selected: annual,
              onTap: () => setState(() => annual = true),
              badge: 'BEST VALUE',
            ),
            gap(12),
            _option(
              title: 'Monthly',
              subtitle: 'Billed monthly · Cancel anytime',
              price: monthlyProduct?.priceString ?? '\$19.99',
              period: '/month',
              selected: !annual,
              onTap: () => setState(() => annual = false),
            ),
            gap(20),
            PrimaryAction(
              trial
                  ? 'Start 7-day free trial'
                  : annual
                  ? 'Continue with annual'
                  : 'Continue with monthly',
              busy: state.purchasing || loading,
              onPressed: product == null || state.demo
                  ? null
                  : () => ref.read(appProvider.notifier).purchase(annual),
            ),
            gap(12),
            Text(
              product == null
                  ? (state.demo
                        ? 'Purchases are unavailable in sample preview. Sign in to see store offers.'
                        : 'Store offers are currently unavailable. You can continue using Free.')
                  : trial
                  ? '7 days free, then ${product.priceString} per year. Renews automatically unless canceled before the trial ends.'
                  : '${product.priceString} ${annual ? 'per year' : 'per month'}. Payment is charged to your store account. Renews automatically unless canceled.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 11, height: 1.5),
            ),
            gap(6),
            if (product == null && !state.demo)
              TextButton(
                onPressed: loading
                    ? null
                    : () async {
                        setState(() => loading = true);
                        await ref.read(appProvider.notifier).loadOfferings();
                        if (mounted) setState(() => loading = false);
                      },
                child: const Text('Retry store connection'),
              ),
          ],
          if (state.purchaseMessage != null) ...[
            gap(10),
            DesignCard(
              child: Text(
                state.purchaseMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ),
          ],
          TextButton(
            onPressed: state.purchasing || state.demo
                ? null
                : () => ref.read(appProvider.notifier).restorePurchases(),
            child: const Text('Restore purchases'),
          ),
          if (!state.isPro)
            TextButton(
              onPressed: () => context.go('/today'),
              child: const Text(
                'Continue with Free',
                style: TextStyle(color: paper),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              TextButton(
                onPressed: () => context.push('/privacy'),
                child: const Text(
                  'Privacy',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/terms'),
                child: const Text(
                  'Terms',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(appProvider.notifier).manageSubscription(),
                child: const Text(
                  'Subscription settings',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
          ),
          const Text(
            'Your existing logs always remain accessible, even after Pro expires.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 11, height: 1.5),
          ),
          gap(12),
        ],
      ),
    );
  }

  Widget _option({
    required String title,
    required String subtitle,
    required String price,
    required String period,
    required bool selected,
    required VoidCallback onTap,
    String? badge,
  }) => Semantics(
    selected: selected,
    button: true,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        DesignCard(
          onTap: onTap,
          color: selected ? const Color(0xFF20271D) : const Color(0xFF1B1F1C),
          border: selected ? lime : const Color(0xFF343A35),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    gap(5),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    period,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (badge != null)
          Positioned(
            right: 14,
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: lime,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: ink,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
