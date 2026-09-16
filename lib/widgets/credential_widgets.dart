import 'dart:io';

import 'package:flutter/material.dart';

import '../data/mechanic_credential_store.dart';
import '../theme/app_theme.dart';

/// One uploaded credential, rendered the same way everywhere it appears —
/// the mechanic's own profile, the client's view of it, and the moderator /
/// admin review sheets.
class CredentialRow extends StatelessWidget {
  final MechanicCredential credential;
  final VoidCallback onView;

  const CredentialRow({super.key, required this.credential, required this.onView});

  IconData get _icon {
    switch (credential.kind) {
      case CredentialKind.mechanicId:
        return Icons.badge_outlined;
      case CredentialKind.document:
        return Icons.check_circle;
      case CredentialKind.certification:
        return Icons.workspace_premium_outlined;
    }
  }

  Color get _iconColor =>
      credential.kind == CredentialKind.mechanicId ? AppColors.info : AppColors.success;

  @override
  Widget build(BuildContext context) {
    final missing = !credential.fileExists;
    return Row(
      children: [
        Icon(_icon, color: missing ? AppColors.textdark.withValues(alpha: 0.55) : _iconColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(credential.label, style: const TextStyle(fontSize: 13)),
              Text(
                missing ? '${credential.fileName} — file unavailable' : credential.fileName,
                style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onView,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(48, 44)),
          child: Text('View', style: TextStyle(color: AppColors.info, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// Opens an uploaded file. Images render for real; anything else (a PDF
/// scan, say) reports what it is rather than pretending to preview it —
/// the app has no renderer for those formats.
void showCredentialPreview(BuildContext context, MechanicCredential credential) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(credential.label, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(credential.fileName,
                style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
            const SizedBox(height: 12),
            _CredentialPreviewBody(credential: credential),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ],
    ),
  );
}

class _CredentialPreviewBody extends StatelessWidget {
  final MechanicCredential credential;

  const _CredentialPreviewBody({required this.credential});

  @override
  Widget build(BuildContext context) {
    if (!credential.fileExists) {
      return _placeholder(
        context,
        Icons.broken_image_outlined,
        'This file is no longer on this device.',
      );
    }
    if (credential.isImage) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(credential.path),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _placeholder(
              context,
              Icons.broken_image_outlined,
              'This image could not be opened.',
            ),
          ),
        ),
      );
    }
    return _placeholder(
      context,
      credential.isPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined,
      credential.isPdf
          ? 'PDF uploaded. Open it outside the app to read it.'
          : 'Uploaded file. This format has no in-app preview.',
    );
  }

  Widget _placeholder(BuildContext context, IconData icon, String message) {
    return Container(
      height: context.layout.panelHeight(180),
      width: double.infinity,
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textdark.withValues(alpha: 0.55)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textdark.withValues(alpha: 0.55))),
          ),
        ],
      ),
    );
  }
}

/// A titled group of credentials, used by the moderator and admin review
/// sheets where the ID, documents and certifications are shown separately.
class CredentialGroup extends StatelessWidget {
  final String title;
  final List<MechanicCredential> credentials;

  const CredentialGroup({super.key, required this.title, required this.credentials});

  @override
  Widget build(BuildContext context) {
    if (credentials.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...credentials.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CredentialRow(credential: c, onView: () => showCredentialPreview(context, c)),
            )),
        const SizedBox(height: 8),
      ],
    );
  }
}
