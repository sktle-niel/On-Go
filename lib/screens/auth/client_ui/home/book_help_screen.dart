import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../data/job_photo_store.dart';
import '../../../../data/quote_store.dart';
import '../../../../data/vehicle_type.dart';
import '../../../../services/backend/mobile_backend.dart';
import '../../../../services/location/place_sources.dart';
import '../../../../theme/app_theme.dart';
import '../../../../widgets/auth_widgets.dart';
import '../../../../widgets/common_widgets.dart';
import '../../../../widgets/location_selector.dart';

/// Booking help for one vehicle, in two steps: what is wrong, then where
/// and how urgently. One screen keeps everything typed while the client
/// walks back and forth.
///
/// Pops with the [ServiceRequest] the backend took, or nothing if the
/// client left.
class BookHelpScreen extends StatefulWidget {
  final VehicleType vehicle;

  /// The step to open on: 0 the problem, 1 the place and urgency. For a
  /// test or a deep link; a client always starts at the problem.
  final int initialStep;

  const BookHelpScreen({super.key, required this.vehicle, this.initialStep = 0});

  @override
  State<BookHelpScreen> createState() => _BookHelpScreenState();
}

class _BookHelpScreenState extends State<BookHelpScreen> {
  static const int _stepCount = 2;

  late int _step = widget.initialStep;

  String? _problem;
  final _detailsCtrl = TextEditingController();
  final List<XFile> _photos = [];

  final _locationCtrl = TextEditingController();
  String _urgency = 'Normal';

  // Only set when the device located the client — cleared the moment the
  // field is edited by hand, so stale coordinates never go out with a place
  // the client typed. This is what lets the mechanic side detect arrival.
  double? _capturedLat;
  double? _capturedLng;

  String? _problemError;
  String? _locationError;
  bool _booking = false;

  bool get _lastStep => _step == _stepCount - 1;

  @override
  void initState() {
    super.initState();
    _locationCtrl.addListener(_clearLocationError);
  }

  @override
  void dispose() {
    _locationCtrl.removeListener(_clearLocationError);
    _detailsCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _clearLocationError() {
    if (_locationError == null || _locationCtrl.text.trim().isEmpty) return;
    setState(() => _locationError = null);
  }

  // ----------------------------------------------------------------- steps ---

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.maybePop(context);
    }
  }

  void _next() {
    if (_step == 0) {
      if (_problem == null) {
        setState(() => _problemError = 'Choose what is wrong, so mechanics know what to quote.');
        return;
      }
      setState(() => _step = 1);
      return;
    }
    _book();
  }

  // ----------------------------------------------------------------- photos ---

  Future<void> _addPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file != null && mounted) setState(() => _photos.add(file));
    } catch (e) {
      _snack('Could not open the camera or gallery: $e');
    }
  }

  // --------------------------------------------------------------- location ---

  /// Coordinates are kept only when they came from the device. A place picked
  /// from suggestions is a named area, not a position precise enough to
  /// detect a mechanic arriving, so it carries none.
  void _onLocationChanged(SelectedLocation? selection) {
    final point = selection?.gps?.point;
    if (point?.latitude == _capturedLat && point?.longitude == _capturedLng) return;
    setState(() {
      _capturedLat = point?.latitude;
      _capturedLng = point?.longitude;
    });
  }

  // ------------------------------------------------------------------- book ---

  Future<void> _book() async {
    if (_booking) return;
    if (_locationCtrl.text.trim().isEmpty) {
      setState(() => _locationError = 'Add your location so mechanics can reach you.');
      return;
    }

    setState(() => _booking = true);

    // Through the seam, so this reads the same whether the job is the
    // server's or this device's. The priority fee and the deadline are set
    // by whichever backend took it and read back off the answer.
    final ServiceRequest booked;
    try {
      booked = await MobileBackend.instance.serviceRequests.bookRequest(NewServiceRequest(
        problem: '${widget.vehicle.label} · $_problem',
        description: _detailsCtrl.text.trim().isEmpty ? null : _detailsCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        urgency: JobUrgency.fromWire(_urgency),
        point: _capturedLat == null || _capturedLng == null ? null : GeoPoint(_capturedLat!, _capturedLng!),
      ));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _booking = false);
      // The refusal is the backend's to word: an open request already, an
      // account that cannot book.
      _snack(error.message);
      return;
    }

    // The photos stay on this device, filed against the id the backend gave
    // the job; the server has nowhere to put them yet. See JobPhotoStore.
    JobPhotoStore.instance.attach(booked.id, _photos.map((f) => f.path).toList());

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Booked. You will be told as mechanics send their quotes.'),
        duration: AppDurations.snackBar,
      ),
    );
    Navigator.pop(context, booked);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: AppDurations.snackBar));
  }

  // ------------------------------------------------------------------ build ---

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    final layout = context.layout;

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: AppBar(
          leading: BackButton(onPressed: _back),
          title: const Text('Book a mechanic'),
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: layout.pageInsets.copyWith(top: 24, bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StepProgressBar(step: _step, count: _stepCount),
                    const SizedBox(height: 12),
                    Text(
                      'STEP ${_step + 1} OF $_stepCount',
                      style: AppText.overline(context).copyWith(color: c.textmedium),
                    ),
                    const SizedBox(height: 8),
                    AuthIntro(
                      title: _step == 0 ? 'What is wrong with ${widget.vehicle.inSentence}?' : 'Where are you?',
                      subtitle: _step == 0
                          ? 'Pick the closest one. You can say more below.'
                          : 'So a mechanic can reach you, and how soon you need them.',
                    ),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: AppMotion.normal,
                      switchInCurve: AppMotion.enter,
                      switchOutCurve: AppMotion.enter,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previous, ?current],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_step),
                        child: _step == 0 ? _problemStep() : _placeStep(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The button stays put under the thumb while the step scrolls.
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: AppHairline.side(c.textmedium)),
              ),
              padding: EdgeInsets.fromLTRB(layout.gutter, 12, layout.gutter, 12),
              child: SafeArea(
                top: false,
                child: AuthPrimaryButton(
                  label: _lastStep ? (_booking ? 'Booking…' : 'Book now') : 'Continue',
                  busy: _booking,
                  onPressed: _next,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Step 1: the problem as a list to tap, then room to say more.
  Widget _problemStep() {
    final c = AppColors.palette;
    final problems = widget.vehicle.commonProblems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One tap each, in a single rounded list rather than a wall of
        // tiles: the rows read top to bottom and the chosen one is marked.
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: AppRadii.borderLg,
            border: Border.all(color: _problemError != null ? c.error : AppHairline.outline(c.textmedium)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < problems.length; i++) ...[
                if (i > 0) Divider(height: 1, color: AppHairline.of(c.textmedium)),
                _ProblemRow(
                  label: problems[i],
                  selected: _problem == problems[i],
                  onTap: () => setState(() {
                    _problem = problems[i];
                    _problemError = null;
                  }),
                ),
              ],
            ],
          ),
        ),
        if (_problemError != null) ...[
          const SizedBox(height: 8),
          Text(_problemError!, style: TextStyle(fontSize: 12, color: c.error)),
        ],
        const SizedBox(height: 24),
        Text(
          'Tell us more (optional)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textdark),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _detailsCtrl,
          maxLines: 4,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: c.textdark, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'E.g. it started after I hit a pothole. The more you say, the better the quotes.',
            hintStyle: TextStyle(color: c.textmedium, fontSize: 15),
            border: OutlineInputBorder(
              borderRadius: AppRadii.borderMd,
              borderSide: BorderSide(color: AppHairline.outline(c.textmedium)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.borderMd,
              borderSide: BorderSide(color: AppHairline.outline(c.textmedium)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.borderMd,
              borderSide: BorderSide(color: c.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addPhoto,
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: Text(_photos.isEmpty ? 'Add photos' : 'Add photos (${_photos.length})'),
            style: TextButton.styleFrom(
              foregroundColor: c.primary,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 44),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (_photos.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 74,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: AppRadii.borderSm,
                    child: Image.file(File(_photos[index].path), width: 74, height: 74, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: PhotoRemoveButton(
                      color: c.primary,
                      onPressed: () => setState(() => _photos.removeAt(index)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Step 2: the place, then how urgent it is and what that costs.
  Widget _placeStep() {
    final c = AppColors.palette;
    final charge = additionalChargeFor(_urgency);
    final urgencyColor = switch (_urgency) {
      'Emergency' => c.error,
      'Urgent' => c.warning,
      _ => c.success,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your location',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textdark),
        ),
        const SizedBox(height: 8),
        // One field for typing, searching, browsing and the device's own
        // location. Typing over a GPS location drops its coordinates.
        LocationSelector(
          controller: _locationCtrl,
          onChanged: _onLocationChanged,
          directory: PlaceSources.directory,
          geocoder: PlaceSources.geocoder,
          hintText: 'Enter your location or use current location',
        ),
        if (_locationError != null) ...[
          const SizedBox(height: 6),
          Text(_locationError!, style: TextStyle(fontSize: 12, color: c.error)),
        ],
        if (_capturedLat != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.gps_fixed, size: 12, color: c.success),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Precise location captured — mechanic arrival will be detected automatically',
                  style: TextStyle(fontSize: 11, color: c.success),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'How urgent is it?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textdark),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final level in const ['Normal', 'Urgent', 'Emergency']) ...[
              if (level != 'Normal') const SizedBox(width: 10),
              _UrgencyChip(
                label: level,
                color: switch (level) {
                  'Emergency' => c.error,
                  'Urgent' => c.warning,
                  _ => c.success,
                },
                selected: _urgency == level,
                onTap: () => setState(() => _urgency = level),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // What the choice means and costs, from the admin's settings.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: urgencyColor.withValues(alpha: 0.10),
            borderRadius: AppRadii.borderMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.schedule, size: 16, color: urgencyColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      completionWindowLabel(_urgency),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: urgencyColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.payments_outlined, size: 16, color: urgencyColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      charge > 0
                          ? 'Priority fee +${formatAdditionalCharge(charge)}, added to your total when you pay'
                          : 'No priority fee',
                      style: TextStyle(fontSize: 12, color: urgencyColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: c.textmedium),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Mechanics quote a price after they see your request. Choose the best offer, and pay the mechanic directly when the job is done.',
                style: TextStyle(fontSize: 13, height: 1.4, color: c.textmedium),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One problem in the list: its name, and a mark when it is the one chosen.
class _ProblemRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ProblemRow({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          color: selected ? c.primary.withValues(alpha: 0.06) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: c.textdark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                size: 22,
                color: selected ? c.primary : AppHairline.outline(c.textmedium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the three urgency choices, sharing a row equally with the others.
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
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.borderMd,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: selected ? 0.14 : 0.06),
              // Always drawn, just clear when unselected, so picking one
              // never makes the row jump by the width of the border.
              border: Border.all(color: selected ? color : color.withValues(alpha: 0), width: 1.5),
              borderRadius: AppRadii.borderMd,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
