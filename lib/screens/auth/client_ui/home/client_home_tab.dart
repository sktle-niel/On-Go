import 'package:flutter/material.dart';

import '../../../../data/client_account_store.dart';
import '../../../../data/vehicle_type.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import 'book_help_screen.dart';

/// The client's home: a greeting, and the one thing to do here — pick what
/// they drive and book help for it. The details of the problem, the place
/// and the urgency come afterwards, one screen at a time, in
/// [BookHelpScreen].
///
/// Modelled on a ride-hailing home: the services are tiles, and a tile is
/// the start of a booking, not a form.
class ClientHomeTab extends StatelessWidget {
  /// Called once a booking has been taken, so the shell can show it.
  final ValueChanged<ServiceRequest>? onBooked;

  const ClientHomeTab({super.key, this.onBooked});

  Future<void> _book(BuildContext context, VehicleType vehicle) async {
    final booked = await Navigator.push<ServiceRequest>(
      context,
      MaterialPageRoute(builder: (_) => BookHelpScreen(vehicle: vehicle)),
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
        // The greeting follows the account, so registering mid-session
        // changes it without a restart.
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
          'What needs a mechanic today?',
          style: TextStyle(fontSize: 14, color: c.textmedium),
        ),
        const SizedBox(height: 24),
        Text(
          'Book help for your',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textdark),
        ),
        const SizedBox(height: 12),
        GridView(
          // As many tiles across as the width allows at about a thumb's
          // width each, every tile the same fixed height: three on a phone,
          // more on a tablet, and never a tile squeezed shorter than its
          // glyph and name.
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 132,
            mainAxisExtent: 104,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final vehicle in VehicleType.values)
              _VehicleTile(vehicle: vehicle, onTap: () => _book(context, vehicle)),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          'How it works',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textdark),
        ),
        const SizedBox(height: 12),
        const _HowRow(1, 'Tell us the problem', 'Pick your vehicle, then what is wrong with it.'),
        const _HowRow(2, 'Get quotes', 'Mechanics near you send their price and how soon they can come.'),
        const _HowRow(3, 'Pay after the job', 'Choose the best offer and pay the mechanic when the work is done.'),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// One vehicle: its glyph in a soft tile, its name under it.
class _VehicleTile extends StatelessWidget {
  final VehicleType vehicle;
  final VoidCallback onTap;

  const _VehicleTile({required this.vehicle, required this.onTap});

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
            label: 'Book help for ${vehicle.inSentence}',
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(vehicle.icon, color: c.primary, size: 26),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    vehicle.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textdark),
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

/// A numbered line of the "how it works" strip.
class _HowRow extends StatelessWidget {
  final int number;
  final String title;
  final String text;

  const _HowRow(this.number, this.title, this.text);

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.primary.withValues(alpha: 0.10),
            ),
            child: Text(
              '$number',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textdark)),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: c.textmedium)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
