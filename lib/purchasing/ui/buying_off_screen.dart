import 'package:flutter/material.dart';

import '../../ui/failure_notice.dart';
import '../../ui/theme.dart';

/// 2A-3a R2: the Buyer switch was turned off. No price screen is shown; the
/// phone's saved copy is wiped. Purchases not yet sent stay on the phone and
/// can still be sent if buying is turned on again.
class BuyingOffScreen extends StatelessWidget {
  const BuyingOffScreen({super.key, required this.onRetry, required this.onSignOut, this.unsent = 0});

  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  /// Purchases waiting on this phone for this account.
  final int unsent;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: WmColors.canvas,
        // The page look of WmPage (24 / 800 title, 20-px sides) without its back
        // button: this is a root screen, there is nothing to go back to.
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              Semantics(header: true, child: const Text('Buying', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2))),
              const SizedBox(height: 16),
              const FailureNotice(
                english: 'Buying is turned off for your account. Ask the owner if this is a mistake.',
                tagalog: 'Naka-off ang pagbili sa account mo. Tanungin ang may-ari kung mali ito.',
              ),
              if (unsent > 0) ...[
                const SizedBox(height: 12),
                Text(
                  key: const Key('buying-off-unsent'),
                  unsent == 1
                      ? '1 purchase not sent yet stays on this phone. It can be sent if buying is turned on again.'
                      : '$unsent purchases not sent yet stay on this phone. They can be sent if buying is turned on again.',
                  style: const TextStyle(fontSize: 14, color: WmColors.textSecondary),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('TRY AGAIN')),
              const SizedBox(height: 8),
              TextButton(onPressed: onSignOut, child: const Text('Log out')),
            ],
          ),
        ),
      );
}
