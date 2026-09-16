import 'package:flutter/material.dart';

import '../../../../widgets/mechanic_rankings_widgets.dart';
import '../profile/mechanic_profile_view_screen.dart';

/// The client's Rankings tab: browse mechanics by rank, rating and reviews,
/// and open a profile to read or leave a review.
///
/// Mechanic discovery — not the competitive seasonal leaderboard.
class RankingsScreen extends StatelessWidget {
  const RankingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MechanicRankingsView(
      onOpenMechanic: (name) => MechanicProfileViewScreen.open(context, name),
    );
  }
}
