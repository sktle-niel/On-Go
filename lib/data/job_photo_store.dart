import 'package:flutter/foundation.dart';

import '../services/local/record_box.dart';

/// The photos a client attached when booking, kept on the device and keyed by
/// the job's id.
///
/// These are deliberately **not** part of the job record. `ServiceRequestApi`
/// carries no photos because the server has nowhere to put them yet, and a
/// photo here is a path into this phone's own storage — a string that means
/// nothing to anybody else's phone. Keeping them beside the job rather than on
/// it says that plainly, instead of putting a field on the contract that only
/// works when both roles happen to be running on one device.
///
/// What that means in practice:
///
/// * The client who booked always sees their own photos, on either backend.
/// * On one device — an `ONGO_BACKEND=local` build, or a demo — the mechanic
///   side reads the same paths and sees them too, exactly as before.
/// * Against the API, with a mechanic on another phone, that mechanic sees
///   nothing. Neither did they before; the paths were never going to resolve
///   on a second device. Serving job photos needs an upload route and storage
///   on the server, the way credential documents and chat images already have.
///
/// Saved between launches, so reopening the app does not empty a job's photos.
class JobPhotoStore extends ChangeNotifier {
  JobPhotoStore._internal();
  static final JobPhotoStore instance = JobPhotoStore._internal();

  RecordWriter _writer = RecordWriter(const SharedPreferencesRecordBox('job_photos'));

  /// Job id to the file paths attached to it, in the order they were picked.
  final Map<String, List<String>> _byJob = {};

  Future<void> load() async {
    for (final json in await _writer.box.load()) {
      final jobId = json['jobId'];
      final paths = json['paths'];
      if (jobId is! String || jobId.isEmpty || paths is! List) continue;
      final kept = [for (final path in paths) if (path is String && path.isNotEmpty) path];
      if (kept.isEmpty) continue;
      _byJob[jobId] = kept;
    }
    notifyListeners();
  }

  /// The photos on [jobId], or an empty list. Never null: a screen asks and
  /// draws what it gets.
  List<String> pathsFor(String jobId) => List.unmodifiable(_byJob[jobId] ?? const <String>[]);

  bool hasPhotos(String jobId) => (_byJob[jobId] ?? const <String>[]).isNotEmpty;

  /// Files [paths] against [jobId]. Called right after a booking is accepted,
  /// with the id the backend gave it — so the photos follow the job the server
  /// created rather than one this device made up.
  void attach(String jobId, List<String> paths) {
    final kept = [for (final path in paths) if (path.trim().isNotEmpty) path];
    if (kept.isEmpty) return;
    _byJob[jobId] = kept;
    _save();
    notifyListeners();
  }

  /// Forgets a job's photos — when its booking was called off, so the device
  /// does not keep growing a list of pictures for jobs that no longer exist.
  void forget(String jobId) {
    if (_byJob.remove(jobId) == null) return;
    _save();
    notifyListeners();
  }

  void _save() => _writer.write([
        for (final entry in _byJob.entries) {'jobId': entry.key, 'paths': entry.value},
      ]);

  @visibleForTesting
  void debugUse(RecordBox box) {
    _writer = RecordWriter(box);
    _byJob.clear();
    notifyListeners();
  }
}
