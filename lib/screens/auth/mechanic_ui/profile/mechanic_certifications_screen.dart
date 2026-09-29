import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../data/mechanic_account_store.dart';
import '../../../../data/mechanic_credential_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../widgets/credential_widgets.dart';

/// The mechanic's certificates, where they add and remove them.
///
/// The list is [MechanicCredentialStore]'s, keyed by the mechanic's name, so
/// anything added here is on their profile the moment it lands — the profile
/// screens listen to the same store rather than being told about the change.
///
/// Registration documents (the NC II, the valid ID) are shown but cannot be
/// removed: they are what the account was approved on, and a mechanic deleting
/// them from their own phone would leave the approval standing on nothing.
class MechanicCertificationsScreen extends StatefulWidget {
  const MechanicCertificationsScreen({super.key});

  @override
  State<MechanicCertificationsScreen> createState() =>
      _MechanicCertificationsScreenState();
}

class _MechanicCertificationsScreenState
    extends State<MechanicCertificationsScreen> {
  final _credentials = MechanicCredentialStore.instance;
  final _account = MechanicAccountStore.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _credentials.addListener(_onChange);
    _account.addListener(_onChange);
  }

  @override
  void dispose() {
    _credentials.removeListener(_onChange);
    _account.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String get _mechanicName => _account.name;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: AppDurations.snackBar),
    );
  }

  Future<void> _upload() async {
    if (_mechanicName.isEmpty) {
      _notify('Register a mechanic account before uploading certificates.');
      return;
    }

    setState(() => _busy = true);
    try {
      // The same picker registration uses, so a certificate can be a photo or
      // a PDF here exactly as it could there.
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: false,
      );
      final paths = (result?.files ?? const <PlatformFile>[])
          .map((f) => f.path)
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList();
      if (paths.isEmpty) return;

      for (final path in paths) {
        await _credentials.addCertification(
          mechanicName: _mechanicName,
          sourcePath: path,
        );
      }
      _notify(paths.length == 1
          ? 'Certificate added'
          : '${paths.length} certificates added');
    } catch (e) {
      _notify('Could not add that file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(MechanicCredential credential) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this certificate?'),
        content: Text(
          '${credential.label} will be taken off your profile. '
          'You can upload it again later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _credentials.remove(credential.id);
    _notify('Certificate removed');
  }

  @override
  Widget build(BuildContext context) {
    final certifications =
        _credentials.ofKind(_mechanicName, CredentialKind.certification);
    final documents =
        _credentials.ofKind(_mechanicName, CredentialKind.document);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Certifications'),
      ),
      body: ListView(
        padding: context.layout.pageInsets,
        children: [
          Text(
            'Certificates you add here appear on your profile, where clients '
            'can see them.',
            style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Expanded so the heading gives way to the count beside
                    // it. Bare, it demands its full width, which at the
                    // largest text size a reader can ask for is wider than a
                    // small phone.
                    const Expanded(
                      child: Text('Your certificates',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${certifications.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textdark.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (certifications.isEmpty)
                  Text(
                    'No certificates yet. Add one to show it on your profile.',
                    style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                  )
                else
                  ...certifications.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: CredentialRow(
                              credential: c,
                              onView: () => showCredentialPreview(context, c),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove ${c.label}',
                            onPressed: _busy ? null : () => _remove(c),
                            icon: Icon(Icons.delete_outline, size: 19, color: AppColors.error),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: Icon(Icons.upload_file_outlined, color: AppColors.textlight),
                  label: const Text('Upload certificate'),
                ),
              ],
            ),
          ),
          if (documents.isNotEmpty) ...[
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.all(16),
              color: AppColors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('From your registration',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Your account was approved on these, so they stay on your '
                    'profile.',
                    style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 12),
                  ...documents.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: CredentialRow(
                        credential: c,
                        onView: () => showCredentialPreview(context, c),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
