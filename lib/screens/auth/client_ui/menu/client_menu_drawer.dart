import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../data/client_account_store.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/common_widgets.dart';
import '../../sign_in_screen.dart';
import '../profile/client_profile_screen.dart';
import '../rewards/client_rewards_screen.dart';
import '../settings/client_settings_screen.dart';
import '../../../../widgets/glass.dart';

class ClientMenuDrawer extends StatefulWidget {
  const ClientMenuDrawer({super.key});

  @override
  State<ClientMenuDrawer> createState() => _ClientMenuDrawerState();
}

class _ClientMenuDrawerState extends State<ClientMenuDrawer> {
  final _store = ClientAccountStore.instance;

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

  /// Closes the drawer and says the page isn't built yet. A menu row that
  /// only closes the menu reads as broken.
  void _comingSoon(String feature) {
    Navigator.pop(context);
    showComingSoon(context, feature);
  }

  /// Signing out is the one menu action Back can't undo, so it asks first.
  Future<void> _signOut() async {
    final confirmed = await confirmSignOut(context);
    if (!confirmed) return;
    if (!mounted) return;
    // Clears this device's session at once; telling the server is not
    // something the user waits for.
    unawaited(MobileBackend.instance.auth.signOut());
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = _store.photoPath;
    final displayName = _store.name.isEmpty ? 'Client' : _store.name;

    final c = AppColors.palette;
    return Drawer(
      // The drawer is a sheet of frosted glass: the page shows through it.
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadii.xl)),
      ),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: Glass.blur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Glass.floating,
            border: Border(right: BorderSide(color: Glass.edge)),
          ),
          child: Column(
            children: [
              // The person: their photo or initials in a ring of the brand
              // colour, their name, and what kind of account this is.
              Padding(
                // Clears the status bar on every phone rather than guessing
                // its height, so the name never tucks under a notch.
                padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 24, 20, 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color.lerp(c.primary, Colors.white, 0.25)!, c.primarydark],
                        ),
                        boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.35), blurRadius: 18)],
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.background,
                        backgroundImage: photo == null
                            ? null
                            : (_store.photoIsNetwork ? NetworkImage(photo) : FileImage(File(photo))) as ImageProvider?,
                        child: photo == null ? GlassGlyph(Icons.person_rounded, size: 30) : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Expanded, so a long name ellipses inside the drawer
                    // instead of running past its edge.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: c.textdark),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: c.primary.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _store.isDemo ? 'Demo Mode' : 'Client',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: Glass.edge),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  children: [
                    _DrawerItem(
                      icon: Icons.person_outline_rounded,
                      label: 'My Profile',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientProfileScreen()));
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.star_outline_rounded,
                      label: 'Rewards & Points',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ClientRewardsScreen()),
                        );
                      },
                    ),
                    _DrawerItem(
                      icon: Icons.settings_outlined,
                      label: 'Settings',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientSettingsScreen()));
                      },
                    ),
                    _DrawerItem(icon: Icons.help_outline_rounded, label: 'Help & Support', onTap: () => _comingSoon('Help & Support')),
                    _DrawerItem(icon: Icons.call_outlined, label: 'Contact Us', onTap: () => _comingSoon('Contact Us')),
                  ],
                ),
              ),
              // Pinned to the bottom, apart from the pages above it: always in
              // the same place, and never hit on the way to Settings.
              Divider(height: 1, color: Glass.edge),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _DrawerItem(
                    icon: Icons.logout_rounded,
                    label: 'Sign Out',
                    destructive: true,
                    onTap: _signOut,
                  ),
                ),
              ),
            ],
          ),
        ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.borderMd,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                // The glyph on a small pane of glass, like the home tiles.
                GlassPanel(
                  radius: 12,
                  padding: EdgeInsets.zero,
                  tint: destructive ? AppColors.error : null,
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Center(child: Icon(icon, size: 20, color: color)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                if (!destructive) Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textmedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
