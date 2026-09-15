import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Internal padding shared by every job card on the Client and Mechanic Jobs
/// screens — uploaded, pending, available, emergency and active alike — so no
/// card's content sits tighter against its edges than another's. One value,
/// one place to change it.
const EdgeInsets jobCardPadding = EdgeInsets.all(16);

/// Vertical gap between one job card and the next, in every job list on the
/// Client and Mechanic Jobs screens. Set from the Mechanic Accepted list,
/// which is the reference spacing.
const double jobCardSpacing = 12;

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? elevation;
  final BorderRadiusGeometry? borderRadius;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.elevation,
    this.borderRadius,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation ?? AppElevation.raised,
      color: color ?? Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: borderRadius ?? AppRadii.borderLg),
      margin: EdgeInsets.zero,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The small uppercase label over a group of settings or details.
///
/// Tracked out a little: capitals set this small run together otherwise.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppColors.textdark.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

/// A round icon action on a job card, such as Call.
///
/// The circle stays 36 points across; the area that takes the tap is 44, the
/// smallest a thumb reliably hits.
class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small ✕ on a photo preview. The badge stays 24 points, and a
/// 36-point area around it takes the tap, so removing a photo is not a
/// precision tap.
class PhotoRemoveButton extends StatelessWidget {
  final VoidCallback onPressed;

  /// The badge colour: the error colour, unless the screen already uses
  /// another for this badge.
  final Color? color;

  const PhotoRemoveButton({super.key, required this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Remove photo',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: CircleAvatar(
              radius: 12,
              backgroundColor: color ?? AppColors.error,
              child: Icon(Icons.close, size: 14, color: AppColors.textmedium),
            ),
          ),
        ),
      ),
    );
  }
}

/// Says plainly that [feature] isn't in the app yet, instead of a button that
/// silently does nothing.
void showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('$feature is coming soon.'), duration: AppDurations.snackBar),
    );
}

/// Asks before signing out. True when the user confirmed.
Future<bool> confirmSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text('You will need to sign in again to use On Go on this device.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Sign Out', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// What the call button on a job opens.
///
/// The app can't place a call itself yet, so this shows the number with a way
/// to copy it, and always offers the job chat, which works whether or not a
/// number is on file.
Future<void> showContactSheet(
  BuildContext context, {
  required String name,
  required String phone,
  required VoidCallback onMessage,
}) {
  final number = phone.trim();
  final hasNumber = number.isNotEmpty;
  final muted = AppColors.textdark.withValues(alpha: 0.55);

  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.textdark),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 18, color: hasNumber ? AppColors.success : muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasNumber ? number : 'No phone number on file',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: hasNumber ? FontWeight.w600 : FontWeight.w400,
                      color: hasNumber ? AppColors.textdark : muted,
                    ),
                  ),
                ),
                if (hasNumber)
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: number));
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Phone number copied'), duration: AppDurations.snackBar),
                      );
                    },
                    style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(sheetContext);
                onMessage();
              },
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Send a Message'),
            ),
          ],
        ),
      ),
    ),
  );
}
