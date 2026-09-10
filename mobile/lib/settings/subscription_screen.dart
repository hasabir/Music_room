import 'package:mobile/core/responsive/responsive.dart';
import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../core/api/api_client.dart';
import 'premium_checkout_screen.dart';

class _SubscriptionColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const premium = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// Bonus: Free vs. Premium subscription (see docs/SUBSCRIPTION_BONUS.md).
///
/// A **mock** upgrade/Cancel subscription— `POST /api/v1/user/subscription/` just
/// flips the stored tier server-side, no payment gateway involved. What
/// Premium actually unlocks, enforced server-side regardless of anything
/// this screen shows: editing a playlist (public or private, own or
/// invited — see `backend/playlists/permissions.py`), and no cap on
/// suggestions/votes (Free is limited to 10 suggestions / 20 distinct
/// votes per day, across every event, not per event).
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.authUser});

  final AuthUser authUser;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _authApi = AuthApi();

  late AuthUser _authUser;
  bool _isSwitching = false;

  @override
  void initState() {
    super.initState();
    _authUser = widget.authUser;
  }

  Future<void> _switchTo(String tier) async {
    setState(() => _isSwitching = true);
    try {
      final updated = await _authApi.switchSubscriptionTier(tier: tier);
      if (!mounted) return;
      setState(() => _authUser = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tier == subscriptionTierPremium
                ? "You're now on Premium."
                : "You're back on the Free plan.",
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  Future<void> _onUpgrade() async {
    final updated = await Navigator.of(context).push<AuthUser>(
      MaterialPageRoute(
        builder: (_) => PremiumCheckoutScreen(
          onActivate: () =>
              _authApi.switchSubscriptionTier(tier: subscriptionTierPremium),
        ),
      ),
    );
    if (updated != null && mounted) setState(() => _authUser = updated);
  }

  Future<void> _onDowngrade() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _SubscriptionColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Cancel subscription?',
          style: TextStyle(fontFamily: 'Sora', color: _SubscriptionColors.body),
        ),
        content: const Text(
          "You'll immediately lose the ability to edit any playlist, and "
          "go back to a 10-suggestion / 20-vote cap per day, across every "
          "event. Anything you've already suggested or voted on stays "
          "as-is — nothing is undone.",
          style: TextStyle(color: _SubscriptionColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _SubscriptionColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Downgrade',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await _switchTo(subscriptionTierFree);
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = _authUser.isPremium;

    return Scaffold(
      backgroundColor: _SubscriptionColors.background,
      appBar: AppBar(
        backgroundColor: _SubscriptionColors.background,
        elevation: 0,
        title: const Text(
          'Subscription',
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w800,
            color: _SubscriptionColors.headline,
          ),
        ),
      ),
      body: ResponsiveContent(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _TierCard(
              isPremium: isPremium,
              expiresAt: _authUser.subscriptionExpiresAt,
            ),
            const SizedBox(height: 20),
            Text(
              isPremium ? 'WHAT PREMIUM UNLOCKS' : 'FREE PLAN LIMITS',
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: _SubscriptionColors.muted,
              ),
            ),
            const SizedBox(height: 10),
            const _PerkRow(
              icon: Icons.edit_rounded,
              text: 'Edit playlists (add, reorder, or remove songs — own or invited). '
                  'Free: view-only, even on playlists you were invited to.',
            ),
            const _PerkRow(
              icon: Icons.queue_music_rounded,
              text: 'Track suggestions per day, across every event — Premium: unlimited, '
                  'Free: capped at 10',
            ),
            const _PerkRow(
              icon: Icons.how_to_vote_rounded,
              text: 'Distinct tracks voted per day, across every event — Premium: unlimited, '
                  'Free: capped at 20',
            ),
            const SizedBox(height: 24),
            const Text(
              'Try Premium with a demo checkout. Use test card details; no charge is made.',
              style: TextStyle(
                fontSize: 12,
                color: _SubscriptionColors.muted,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            if (!isPremium)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(
                      colors: [
                        _SubscriptionColors.gradientStart,
                        _SubscriptionColors.gradientEnd,
                      ],
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: _isSwitching ? null : _onUpgrade,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isSwitching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'UPGRADE TO PREMIUM',
                            style: TextStyle(
                              fontFamily: 'Sora',
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: _isSwitching ? null : _onDowngrade,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isSwitching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.redAccent,
                          ),
                        )
                      : const Text(
                          'Cancel subscription',
                          style: TextStyle(
                            fontFamily: 'Sora',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.isPremium, this.expiresAt});

  final bool isPremium;
  final DateTime? expiresAt;

  String? _expiryLabel() {
    if (!isPremium || expiresAt == null) return null;
    final remaining = expiresAt!.difference(DateTime.now());
    final datePart = '${_month(expiresAt!.month)} ${expiresAt!.day}, ${expiresAt!.year}';
    if (remaining.isNegative) return 'Expired on $datePart';
    final days = remaining.inDays;
    final timeLeft = days >= 1
        ? '$days day${days == 1 ? '' : 's'} left'
        : '${remaining.inHours.clamp(1, 23)} hour${remaining.inHours == 1 ? '' : 's'} left';
    return 'Renews on $datePart · $timeLeft';
  }

  static String _month(int month) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][month - 1];

  @override
  Widget build(BuildContext context) {
    final expiryLabel = _expiryLabel();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _SubscriptionColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPremium
              ? _SubscriptionColors.premium
              : _SubscriptionColors.border,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: _SubscriptionColors.background,
            child: Icon(
              isPremium
                  ? Icons.workspace_premium_rounded
                  : Icons.person_outline_rounded,
              color: isPremium
                  ? _SubscriptionColors.premium
                  : _SubscriptionColors.headline,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPremium ? 'Premium Plan' : 'Free Plan',
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    color: _SubscriptionColors.body,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPremium
                      ? 'Unlimited suggestions, votes, and playlist editing.'
                      : 'Limited suggestions/votes per day; no playlist editing.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _SubscriptionColors.muted,
                  ),
                ),
                if (expiryLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    expiryLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _SubscriptionColors.premium,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: _SubscriptionColors.premium),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: _SubscriptionColors.body,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
