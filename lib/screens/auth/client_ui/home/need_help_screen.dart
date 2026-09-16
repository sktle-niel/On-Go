import 'dart:io';

import 'package:flutter/material.dart';
import 'package:on_go_shared/on_go_shared.dart' show formatAdditionalCharge;
import '../../../../../services/location/place_sources.dart';
import '../../../../../widgets/location_selector.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../theme/app_theme.dart';
import '../../../../../widgets/common_widgets.dart';
// Todo: adjust this path to wherever quote_store.dart lives in your project
import '../../../../../data/quote_store.dart';
import '../../../../../data/review_store.dart';

class NeedHelpScreen extends StatefulWidget {
  /// Called after the request has been successfully uploaded.
  /// Quotes will start arriving on the notification bell shortly after.
  final VoidCallback? onRequestUploaded;

  const NeedHelpScreen({super.key, this.onRequestUploaded});

  @override
  State<NeedHelpScreen> createState() => _NeedHelpScreenState();
}

class _NeedHelpScreenState extends State<NeedHelpScreen> {
  final _problemCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  String _urgency = 'Normal';
  String? _selectedIssue;

  final List<XFile> _photos = [];
  bool _uploading = false;

  // Only set when "Use Current Location" succeeds — cleared the moment the
  // client edits the field by hand, so we never send stale/mismatched
  // coordinates for a location string the client typed themselves. This is
  // what lets the mechanic side auto-detect En Route / Arrived; without it,
  // MechanicActiveJobScreen falls back to a manual arrival confirmation.
  double? _capturedLat;
  double? _capturedLng;

  // A getter, not a const: the colors come from the active theme.
  static List<Map<String, dynamic>> get _issues => [
    {'icon': Icons.car_repair, 'label': 'Engine Problem', 'color': AppColors.warning},
    {'icon': Icons.album_outlined, 'label': 'Brake Issue', 'color': AppColors.error},
    {'icon': Icons.tire_repair, 'label': 'Flat Tire', 'color': AppColors.success},
    {'icon': Icons.battery_alert_outlined, 'label': 'Battery Dead', 'color': AppColors.success},
    {'icon': Icons.settings_input_component_outlined, 'label': 'Chain Problem', 'color': AppColors.info},
    {'icon': Icons.electrical_services_outlined, 'label': 'Electrical Issue', 'color': AppColors.warning},
  ];

  // Sampled directly from the design reference: light-blue card, deep navy text.
  static Color get _pricingCardBg => AppColors.surface;

  @override
  void dispose() {
    _problemCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Camera / gallery
  // ---------------------------------------------------------------------

  Future<void> _addPhotos() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() => _photos.add(file));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access camera/gallery: $e'), duration: AppDurations.snackBar),
      );
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  // ---------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------

  /// Everything about finding the location — GPS, permission, suggestions —
  /// lives in [LocationSelector] and the shared LocationService. This screen
  /// only keeps what it submits.
  ///
  /// Coordinates are kept only when they came from the device. A place picked
  /// from suggestions is a named area, not a position precise enough to detect
  /// a mechanic arriving, so it carries none — and the mechanic side falls back
  /// to confirming arrival by hand rather than trusting a guess.
  void _onLocationChanged(SelectedLocation? selection) {
    final point = selection?.gps?.point;
    if (point?.latitude == _capturedLat && point?.longitude == _capturedLng) return;
    setState(() {
      _capturedLat = point?.latitude;
      _capturedLng = point?.longitude;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: AppDurations.snackBar));
  }

  // ---------------------------------------------------------------------
  // Upload
  // ---------------------------------------------------------------------

  Future<void> _uploadRequest() async {
    if (_problemCtrl.text.trim().isEmpty) {
      _showSnack('Please describe the problem.');
      return;
    }
    if (_locationCtrl.text.trim().isEmpty) {
      _showSnack('Please add your location.');
      return;
    }

    setState(() => _uploading = true);

    // What picking this urgency costs, from the admin's settings — the same
    // ones the job's deadline is set from.
    final charge = additionalChargeFor(_urgency);
    final request = HelpRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      problem: _problemCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      urgency: _urgency,
      photoPaths: _photos.map((f) => f.path).toList(),
      createdAt: DateTime.now(),
      surcharge: charge,
      // Who the job belongs to — what its evaluation, points and history are
      // recorded against.
      clientName: ReviewStore.currentClientName,
      clientLat: _capturedLat,
      clientLng: _capturedLng,
    );

    // Hands the request off to mechanics. Quotes will arrive asynchronously
    // and show up as a badge on the notification bell.
    QuoteNotificationStore.instance.submitRequest(request);

    if (!mounted) return;
    setState(() => _uploading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Request uploaded! You will get notified when mechanics send their quotes.'),
        duration: AppDurations.snackBar,
      ),
    );

    widget.onRequestUploaded?.call();

    setState(() {
      _problemCtrl.clear();
      _locationCtrl.clear();
      _selectedIssue = null;
      _photos.clear();
      _urgency = 'Normal';
      _capturedLat = null;
      _capturedLng = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // What picking this urgency costs, from the admin's settings — the same
    // ones the job's deadline is set from.
    final charge = additionalChargeFor(_urgency);
    final urgencyColor = _urgency == 'Emergency'
      ? AppColors.error
      : _urgency == 'Urgent'
        ? AppColors.warning
        : AppColors.success;

    return SingleChildScrollView(
      padding: context.layout.pageInsets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Need Help?',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textdark),
          ),
          const SizedBox(height: 4),
          Text(
            'Describe your motorcycle problem to help mechanics understand your situation better. The more details you provide, the better quotes you will receive.',
            style: TextStyle(fontSize: 13, color: AppColors.textdark),
          ),
          const SizedBox(height: 20),
          const Text('Common Issues',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          GridView.count(
            // Three across on a phone, more on a wider screen — the tiles
            // keep their size and the grid gains columns, rather than three
            // tiles stretching across a tablet.
            crossAxisCount: context.layout.isTablet ? 4 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
            children: _issues.map((issue) {
              final selected = _selectedIssue == issue['label'];
              final color = issue['color'] as Color;
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() {
                  _selectedIssue = issue['label'] as String;
                  _problemCtrl.text = '${issue['label']}: ';
                }),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? color.withValues(alpha: 0.08) : AppColors.surface,
                    border: Border.all(
                      color: selected ? color : AppColors.textdark.withValues(alpha: 0.2),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(issue['icon'] as IconData, color: color, size: 26),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          issue['label'] as String,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text('Describe the Problem',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _problemCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: "E.g. My motorcycle won't start, and I hear a clicking sound when I turn the key.",
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addPhotos,
              icon: Icon(Icons.photo_camera_outlined, size: 18, color: AppColors.primary),
              label: Text(
                _photos.isEmpty ? 'Add Photos' : 'Add Photos (${_photos.length})',
                style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
            ),
          ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final photo = _photos[index];
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(photo.path),
                          width: 74,
                          height: 74,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => _removePhoto(index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close, size: 14, color: AppColors.textmedium),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Your Location',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          // One field for typing, searching, browsing and the device's own
          // location. Typing over a GPS location drops its coordinates, as the
          // plain field did.
          LocationSelector(
            controller: _locationCtrl,
            onChanged: _onLocationChanged,
            directory: PlaceSources.directory,
            geocoder: PlaceSources.geocoder,
            hintText: 'Enter your location or use current location',
          ),
          if (_capturedLat != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.gps_fixed, size: 12, color: AppColors.success),
                ),
                const SizedBox(width: 4),
                // Wraps rather than running off the screen: on one line this
                // is far wider than any phone.
                Expanded(
                  child: Text('Precise location captured — mechanic arrival will be detected automatically',
                      style: TextStyle(fontSize: 11, color: AppColors.success)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Text('Urgency Level !!!',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              _UrgencyChip(
                label: 'Normal',
                color: AppColors.success,
                selected: _urgency == 'Normal',
                onTap: () => setState(() => _urgency = 'Normal'),
              ),
              const SizedBox(width: 10),
              _UrgencyChip(
                label: 'Urgent',
                color: AppColors.warning,
                selected: _urgency == 'Urgent',
                onTap: () => setState(() => _urgency = 'Urgent'),
              ),
              const SizedBox(width: 10),
              _UrgencyChip(
                label: 'Emergency',
                color: AppColors.error,
                selected: _urgency == 'Emergency',
                onTap: () => setState(() => _urgency = 'Emergency'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: urgencyColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: urgencyColor.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: urgencyColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(completionWindowLabel(_urgency),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: urgencyColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: urgencyColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        charge > 0
                            ? 'Additional charge applies: +${formatAdditionalCharge(charge)}, '
                                'added to your total when you pay'
                            : 'No additional charge',
                        style: TextStyle(
                          fontSize: 12,
                          color: urgencyColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            padding: const EdgeInsets.all(14),
            color: _pricingCardBg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.attach_money, color: AppColors.info),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('How pricing works',
                          style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w700, fontSize: 16)),
                      SizedBox(height: 4),
                      Text(
                        'Mechanics quote a price for the job after they see your request. You can choose the best offer, and pay the mechanic directly after the job is done.',
                        style: TextStyle(color: AppColors.info, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _uploading ? null : _uploadRequest,
            icon: _uploading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface),
                  )
                : const Icon(Icons.cloud_upload_outlined, size: 18),
            label: Text(_uploading ? 'Uploading…' : 'Upload'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _UrgencyChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _UrgencyChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            border: selected ? Border.all(color: color, width: 2) : null,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}