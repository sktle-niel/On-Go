import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../data/mechanic_account_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import '../../sign_in_screen.dart';
import '../settings/mechanic_settings_screen.dart';
import '../profile/mechanic_certifications_screen.dart';
import '../profile/mechanic_profile_info_screen.dart';

class MechanicMenuDrawer extends StatefulWidget {
  const MechanicMenuDrawer({super.key});

  @override
  State<MechanicMenuDrawer> createState() => _MechanicMenuDrawerState();
}

class _MechanicMenuDrawerState extends State<MechanicMenuDrawer> {
  final _store = MechanicAccountStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  String get _subtitle {
    if (_store.isDemo) return 'Demo Mode';
    if (!_store.isRegistered) return 'Mechanic';
    switch (_store.status) {
      case ApprovalStatus.approved:
        return 'Mechanic';
      case ApprovalStatus.rejected:
        return 'Account Rejected';
      case ApprovalStatus.pending:
      default:
        return 'Pending Approval';
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _store.name.isEmpty ? 'Mechanic' : _store.name;
    final photo = _store.photoPath;

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadii.xl)),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primary,
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.surface.withValues(alpha: 0.25),
                  backgroundImage: photo == null
                      ? null
                      : (_store.photoIsNetwork ? NetworkImage(photo) : FileImage(File(photo))) as ImageProvider?,
                  child: photo == null ? Icon(Icons.person_outline, color: AppColors.textlight, size: 32) : null,
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textlight, fontWeight: FontWeight.w700)),
                    Text(_subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textlight.withValues(alpha: 0.7))),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              children: [
                _DrawerItem(
                  icon: Icons.person_outline,
                  label: 'My Profile',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MechanicProfileInfoScreen()));
                  },
                ),
                _DrawerItem(
                  icon: Icons.badge_outlined,
                  label: 'Certifications',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MechanicCertificationsScreen()),
                    );
                  },
                ),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const MechanicSettingsScreen()));
                  },
                ),
                _DrawerItem(icon: Icons.help_outline, label: 'Help & Support', onTap: () => Navigator.pop(context)),
                _DrawerItem(icon: Icons.call_outlined, label: 'Contact Us', onTap: () => Navigator.pop(context)),
                _DrawerItem(
                  icon: Icons.logout,
                  label: 'Sign Out',
                  destructive: true,
                  onTap: () {
                    // Clears this device's session at once; telling the
                    // server is not something the user waits for.
                    unawaited(MobileBackend.instance.auth.signOut());
                    // Deliberately NOT calling _store.clear() — signing out
                    // preserves the registered account so the mechanic can
                    // sign back in later without re-registering.
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const SignInScreen()),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    // Destructive rows read in the error color, the way the reference
    // treats its log-out entry.
    final color = destructive ? AppColors.error : AppColors.textdark;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      horizontalTitleGap: 12,
      minLeadingWidth: 20,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.borderMd),
      leading: Icon(icon, size: 20, color: color),
      title: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500, fontSize: 14)),
      onTap: onTap,
    );
  }
}