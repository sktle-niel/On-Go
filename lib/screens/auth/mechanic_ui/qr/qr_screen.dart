import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../data/quote_store.dart';
import '../../../../theme/app_theme.dart';

class QrScreen extends StatefulWidget {
  const QrScreen({super.key});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  bool _scanning = false;
  MobileScannerController? _controller;

  void _openScanner() {
    setState(() {
      _scanning = true;
      _controller = MobileScannerController();
    });
  }

  void _closeScanner() {
    _controller?.dispose();
    setState(() {
      _scanning = false;
      _controller = null;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
    final raw = barcode?.rawValue ?? barcode?.displayValue;
    if (raw == null) return;
    _closeScanner();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code Scanned'),
        content: Text('Scanned data:\n$raw'),
        // Todo: hand this off to whatever real cash-out/transfer flow you
        // integrate — for now this just confirms the scan worked.
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: raw));
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Positioned(
            top: 16,
            left: 16,
            child: _ScannerButton(icon: Icons.close, tooltip: 'Close scanner', onPressed: _closeScanner),
          ),
          // A dim room or a roadside at night is where a code most often
          // won't read, so the flashlight sits opposite Close.
          Positioned(
            top: 16,
            right: 16,
            child: _ScannerButton(
              icon: Icons.flashlight_on_outlined,
              tooltip: 'Flashlight',
              onPressed: () => _controller?.toggleTorch(),
            ),
          ),
        ],
      );
    }

    final mechanicName = QuoteNotificationStore.currentMechanicName;
    final qrData = buildMechanicAccountQrData(mechanicName);

    return Center(
      // Scrolls on a short phone at a large text size instead of overflowing.
      child: SingleChildScrollView(
        padding: context.layout.pageInsets,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'My QR Code',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.textdark),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(data: qrData, size: 200, backgroundColor: AppColors.textlight),
            ),
            const SizedBox(height: 12),
            Text(
              mechanicName,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textdark),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openScanner,
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Open Scanner'),
              style: ElevatedButton.styleFrom(minimumSize: const Size(200, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round button over the camera feed, dark so it reads against any scene.
class _ScannerButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ScannerButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.black54,
      child: IconButton(icon: Icon(icon, color: AppColors.textmedium), tooltip: tooltip, onPressed: onPressed),
    );
  }
}