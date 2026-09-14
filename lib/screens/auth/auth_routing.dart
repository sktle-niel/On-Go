import 'package:flutter/material.dart';

import '../../data/client_account_store.dart';
import '../../data/mechanic_account_store.dart';
import '../../services/backend/mobile_backend.dart';
import 'client_ui/client_home_screen.dart';
import 'mechanic_ui/mechanic_home_screen.dart';

/// Opens the shell for [user]'s role, replacing everything on the stack.
///
/// When the account came from the On Go API, its store takes the account on
/// first, so every screen that reads the store sees who signed in. Returns
/// false — and opens nothing — for a role that belongs to the console.
bool enterAppAs(BuildContext context, AuthenticatedUser user) {
  final usesApi = MobileBackend.instance.usesApi;
  final Widget home;
  switch (user.role) {
    case UserRole.client:
      if (usesApi) {
        ClientAccountStore.instance.adoptServerAccount(email: user.email, displayName: user.displayName);
      }
      home = const ClientHomeScreen();
    case UserRole.mechanic:
      if (usesApi) {
        MechanicAccountStore.instance.adoptServerAccount(email: user.email, displayName: user.displayName);
      }
      home = const MechanicHomeScreen();
    case UserRole.admin:
    case UserRole.moderator:
      return false;
  }

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => home),
    (route) => false,
  );
  return true;
}
