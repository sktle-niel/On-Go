import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:on_go_shared/on_go_shared.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/auth_background_controller.dart';

/// Keeps the Sign In / Welcome background in step with what the console
/// published (`GET /platform/appearance`).
///
/// The API hands back a URL; [AuthBackgroundController] paints a file it
/// keeps across launches. This downloads the one into the other, once per
/// URL, and drops the photo when the console clears it. A failed download
/// leaves whatever was already painted.
class AppearanceSync {
  AppearanceSync({
    required PlatformAppearanceApi api,
    AuthBackgroundController? controller,
    http.Client? httpClient,
  })  : _api = api,
        _controller = controller ?? AuthBackgroundController.instance,
        _http = httpClient ?? http.Client();

  /// The URL the cached photo was downloaded from.
  static const String _sourceKey = 'auth_background_source_url';

  final PlatformAppearanceApi _api;
  final AuthBackgroundController _controller;
  final http.Client _http;

  StreamSubscription<PlatformAppearance>? _watch;
  Future<void> _pending = Future<void>.value();

  void start() {
    _watch ??= _api.watch().listen(
      (appearance) => _pending = _pending.then((_) => _apply(appearance)),
      onError: (Object _) {
        // Unreachable or refused: keep painting what is cached.
      },
    );
  }

  void stop() {
    unawaited(_watch?.cancel());
    _watch = null;
  }

  Future<void> _apply(PlatformAppearance appearance) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedFrom = prefs.getString(_sourceKey);
      final url = appearance.authBackgroundUrl;

      if (url == null) {
        // Only a photo this class downloaded is the console's to clear.
        if (cachedFrom != null) {
          await _controller.removePhoto();
          await prefs.remove(_sourceKey);
        }
        return;
      }
      if (url == cachedFrom && _controller.hasPhoto) return;

      final uri = Uri.tryParse(url);
      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;

      final response = await _http.get(uri).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}ongo_background${_extensionOf(uri.path)}');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      if (await _controller.setPhoto(file.path)) await prefs.setString(_sourceKey, url);
      try {
        await file.delete();
      } catch (_) {
        // A leftover temp file is harmless.
      }
    } catch (_) {
      // No network, no storage: the current background stays.
    }
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    final slash = path.lastIndexOf('/');
    if (dot <= slash + 1 || dot == path.length - 1) return '.jpg';
    return path.substring(dot);
  }
}
