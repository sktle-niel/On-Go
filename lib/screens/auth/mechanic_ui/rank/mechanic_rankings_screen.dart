import 'package:flutter/material.dart';

import '../../../../data/quote_store.dart';
import '../../../../widgets/mechanic_rankings_widgets.dart';
import '../../client_ui/profile/mechanic_profile_view_screen.dart';
import '../profile/mechanic_profile_screen.dart';

/// The mechanic's Rankings tab: where they stand by rank, rating and reviews
/// among the mechanics this device knows.
///
/// Mechanic discovery — not the competitive seasonal leaderboard.
class MechanicRankingsScreen extends StatelessWidget {
  const MechanicRankingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = QuoteNotificationStore.currentMechanicName;
    return MechanicRankingsView(
      highlightName: me,
      onOpenMechanic: (name) {
        if (name == me) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const MechanicProfileScreen()));
        } else {
          // Read-only for a mechanic: writing a review is the Client UI's.
          MechanicProfileViewScreen.open(context, name);
        }
      },
    );
  }
}
