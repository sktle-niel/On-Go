import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// The Details card on a mechanic's profile: how to reach them.
///
/// One widget for both profiles — the mechanic's own and the one a client
/// opens — so what a mechanic sees on their profile is exactly what a client
/// sees on it. The two screens differ only in where the values come from: the
/// signed-in account on one, `MechanicContactStore` on the other.
class MechanicDetailsCard extends StatelessWidget {
  const MechanicDetailsCard({
    super.key,
    required this.phone,
    required this.email,
  });

  final String phone;
  final String email;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _DetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone number',
            value: phone,
          ),
          const SizedBox(height: 10),
          _DetailRow(
            icon: Icons.email_outlined,
            label: 'Email account',
            value: email,
          ),
        ],
      ),
    );
  }
}

/// One contact line. A missing value says so rather than leaving a blank the
/// reader has to interpret.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final missing = value.trim().isEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: missing ? AppColors.textdark.withValues(alpha: 0.35) : AppColors.info,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 2),
              Text(
                missing ? 'Not provided' : value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: missing ? FontWeight.w400 : FontWeight.w600,
                  color: missing
                      ? AppColors.textdark.withValues(alpha: 0.55)
                      : AppColors.textdark,
                ),
              ),
            ],
          ),
        ),
        // The app can't dial or open mail yet, so the number and address can
        // at least be copied out instead of retyped from the screen.
        if (!missing)
          IconButton(
            tooltip: 'Copy ${label.toLowerCase()}',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value.trim()));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label copied'), duration: AppDurations.snackBar),
              );
            },
            icon: Icon(Icons.copy, size: 16, color: AppColors.textdark.withValues(alpha: 0.55)),
          ),
      ],
    );
  }
}
