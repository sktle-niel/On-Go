import 'package:flutter/material.dart';

import '../../../../data/client_account_store.dart';
import '../../../../data/motorcycle_problem.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import 'book_help_screen.dart';

/// The client's home: a greeting, and the one thing to do here — say what is
/// wrong with the motorcycle and book help for it. The details, the place and
/// the urgency come afterwards, one screen at a time, in [BookHelpScreen].
///
/// Modelled on a ride-hailing home: the services are tiles, and a tile is
/// the start of a booking, not a form.
class ClientHomeTab extends StatelessWidget {
  /// Called once a booking has been taken, so the shell can show it.
  final ValueChanged<ServiceRequest>? onBooked;

  const ClientHomeTab({super.key, this.onBooked});

  Future<void> _book(BuildContext context, MotorcycleProblem problem) async {
    final booked = await Navigator.push<ServiceRequest>(
      context,
      MaterialPageRoute(builder: (_) => BookHelpScreen(problem: problem)),
    );
    if (booked != null) onBooked?.call(booked);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final layout = context.layout;

    return ListView(
      padding: layout.pageInsets,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The greeting follows the account, so registering
                  // mid-session changes it without a restart.
                  AnimatedBuilder(
                    animation: ClientAccountStore.instance,
                    builder: (context, _) {
                      final first = ClientAccountStore.instance.firstName.trim();
                      return Text(
                        first.isEmpty ? 'Hi there' : 'Hi, $first',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: c.textdark,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'What is wrong with your motorcycle?',
                    style: TextStyle(fontSize: 14, color: c.textmedium),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // The bike itself, beside the question about it.
            Image.asset(
              MotorcycleProblem.motorcyclePicture,
              width: 76,
              height: 76,
              errorBuilder: (_, _, _) => const SizedBox(width: 76, height: 76),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Book a mechanic for',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textdark),
        ),
        const SizedBox(height: 12),
        GridView(
          // As many tiles across as the width allows at about a thumb's
          // width each, every tile the same fixed height: three on a phone,
          // more on a tablet, and never a tile squeezed shorter than its
          // picture and name.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 132,
            // Room for a two-line name at the largest text size the app allows.
            mainAxisExtent: 118,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final problem in MotorcycleProblem.values)
              _ProblemTile(problem: problem, onTap: () => _book(context, problem)),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// One problem: its picture, its name under it.
class _ProblemTile extends StatelessWidget {
  final MotorcycleProblem problem;
  final VoidCallback onTap;

  const _ProblemTile({required this.problem, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return PressScale(
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.borderLg,
          side: AppHairline.side(c.textmedium),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            button: true,
            label: 'Book a mechanic: ${problem.label}',
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // The render carries its own colour and depth; no tinted
                  // tile behind it.
                  Image.asset(
                    problem.picture,
                    width: 52,
                    height: 52,
                    errorBuilder: (_, _, _) => const SizedBox(width: 52, height: 52),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    problem.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: c.textdark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
