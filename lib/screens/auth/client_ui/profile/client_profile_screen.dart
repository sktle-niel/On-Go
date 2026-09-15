import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../data/client_account_store.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/common_widgets.dart';

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
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

  String _formatDate(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _changePhoto() async {
    if (!_store.canChangePhoto) {
      final next = _store.nextPhotoChangeAt;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You can change your photo again on ${next != null ? _formatDate(next) : 'a later date'}.'), duration: AppDurations.snackBar),
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1200, imageQuality: 85);
      if (file == null) return;
      final ok = _store.changePhoto(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Profile photo updated' : 'You can only change your photo once every 30 days.'), duration: AppDurations.snackBar),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update photo: $e'), duration: AppDurations.snackBar));
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _store.photoPath;
    final canChange = _store.canChangePhoto;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textmedium,
        title: const Text('My Profile'),
      ),
      body: ListView(
        padding: context.layout.pageInsets,
        children: [
          Center(
            child: Stack(
              children: [
                // Inset by the camera button's overhang, so the whole button
                // lies inside the stack: a tap outside a stack's bounds never
                // reaches its children.
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(70),
                    child: photo == null
                        ? Container(
                            width: context.layout.scale(120),
                            height: context.layout.scale(120),
                            color: AppColors.background,
                            child: Icon(Icons.person, size: context.layout.scale(56), color: AppColors.textdark.withValues(alpha: 0.55)),
                          )
                        : (_store.photoIsNetwork
                            ? Image.network(photo, width: context.layout.scale(120), height: context.layout.scale(120), fit: BoxFit.cover)
                            : Image.file(File(photo), width: context.layout.scale(120), height: context.layout.scale(120), fit: BoxFit.cover)),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Tooltip(
                    message: 'Change photo',
                    child: InkResponse(
                      onTap: _changePhoto,
                      radius: 22,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: canChange ? AppColors.primary : AppColors.textdark.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.surface, width: 2),
                            ),
                            child: Icon(Icons.camera_alt, color: AppColors.textlight, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Center(
            child: Text(
              canChange
                  ? 'You can change your photo'
                  : 'Next photo change: ${_formatDate(_store.nextPhotoChangeAt!)}',
              style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55)),
            ),
          ),
          const SizedBox(height: 28),
          const SectionLabel('ACCOUNT INFORMATION'),
          const SizedBox(height: 12),
          _InfoRow(icon: Icons.person_outline, label: 'Full Name', value: _store.name.isEmpty ? '—' : _store.name),
          _InfoRow(icon: Icons.email_outlined, label: 'Email', value: _store.email.isEmpty ? '—' : _store.email),
          _InfoRow(icon: Icons.home_outlined, label: 'Address', value: _store.address.isEmpty ? '—' : _store.address),
          _InfoRow(icon: Icons.phone_outlined, label: 'Mobile Number', value: _store.phone.isEmpty ? '—' : _store.phone),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: AppColors.textdark.withValues(alpha: 0.2)), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textdark.withValues(alpha: 0.55)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: AppColors.textdark.withValues(alpha: 0.55))),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}