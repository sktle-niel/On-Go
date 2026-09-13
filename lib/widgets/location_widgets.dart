import 'package:flutter/material.dart';

import '../services/location/location_service.dart';
import '../theme/app_theme.dart';

/// The Location row in Settings: whether On Go can use location, and the one
/// action that can change it.
///
/// What the action does depends on why location is off — a prompt can only be
/// shown while the user has not permanently declined, a permanent decline can
/// only be undone in the app's system settings, and services being switched
/// off can only be fixed in the device's location settings. It re-reads the
/// permission whenever the app comes back to the front, so returning from the
/// system settings shows the new state straight away.
class LocationAccessTile extends StatefulWidget {
  const LocationAccessTile({super.key, this.service});

  /// Defaults to the shared service; injectable for tests.
  final LocationService? service;

  @override
  State<LocationAccessTile> createState() => _LocationAccessTileState();
}

class _LocationAccessTileState extends State<LocationAccessTile> {
  LocationService get _service => widget.service ?? LocationService.instance;

  @override
  void initState() {
    super.initState();
    _service.refreshAccess();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final access = _service.access;
        final (subtitle, actionLabel, action) = switch (access) {
          LocationAccess.granted => (
              _service.isApproximate
                  ? 'On, approximate — used to fill in where you are'
                  : 'On — used to fill in where you are',
              'Manage',
              _service.openAppSettings,
            ),
          LocationAccess.notDetermined || LocationAccess.denied => (
              'Off — you can always type your location instead',
              'Turn on',
              _service.requestAccess,
            ),
          LocationAccess.deniedForever => (
              'Off in your phone\'s settings for On Go',
              'Open Settings',
              _service.openAppSettings,
            ),
          LocationAccess.servicesDisabled => (
              'Location services are switched off on this device',
              'Turn on',
              _service.openLocationSettings,
            ),
          LocationAccess.unknown => (
              'Location is not available on this device right now',
              null,
              null,
            ),
        };

        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Location access', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                  ),
                ],
              ),
            ),
            if (actionLabel != null && action != null)
              TextButton(
                onPressed: () => action(),
                child: Text(actionLabel),
              ),
          ],
        );
      },
    );
  }
}
