import 'package:flutter/material.dart';

import '../../../../data/client_account_store.dart';
import '../../../../data/points_wallet_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../widgets/points_widgets.dart';

/// The client's points: what they hold, how they earned it, what it is for.
///
/// The balance is read from [PointsWalletStore] rather than computed here.
/// What a job awards is deliberately NOT shown — not as a rate, and not per
/// job in the history: the rates are configured and seen by the admin only.
class ClientRewardsScreen extends StatefulWidget {
  const ClientRewardsScreen({super.key});

  @override
  State<ClientRewardsScreen> createState() => _ClientRewardsScreenState();
}

class _ClientRewardsScreenState extends State<ClientRewardsScreen> {
  final _wallet = PointsWalletStore.instance;
  final _account = ClientAccountStore.instance;

  @override
  void initState() {
    super.initState();
    _wallet.addListener(_onChange);
    _account.addListener(_onChange);
  }

  @override
  void dispose() {
    _wallet.removeListener(_onChange);
    _account.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String get _owner => _account.name;

  @override
  Widget build(BuildContext context) {
    final balance = _wallet.balanceFor(_owner);
    final entries = _wallet.entriesFor(_owner);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textlight,
        title: const Text('Rewards & Points'),
      ),
      body: ListView(
        padding: context.layout.pageInsets,
        children: [
          PointsBalanceCard(
            points: balance,
            caption: 'Worth ${formatPesos(pesosForPoints(balance))} towards '
                'additional charges',
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('How you spend',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'At checkout on a job with an additional charge you can put your '
                  'points towards it, at 1 pt = ₱1. The option '
                  'appears when your balance covers the whole fee.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('History',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (entries.isEmpty)
                  Text(
                    'Nothing yet. Upload a job to earn your first points when it is completed.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                  )
                else
                  ...entries.map((e) => PointsEntryRow(entry: e)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
