import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../theme/app_theme.dart';

/// Live camera QR scanner. Pops with the raw scanned string, or null if the
/// client backs out. Camera permission is requested by MobileScanner itself
/// the moment this widget mounts; [errorBuilder] covers the denied case.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final barcode = capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
    final raw = barcode?.rawValue ?? barcode?.displayValue;
    if (raw == null) return;
    _handled = true;
    Navigator.pop(context, raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan QR Code'),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable. Please allow camera access in your device Settings and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textmedium),
                ),
              ),
            ),
          ),
          Center(
            child: Builder(builder: (context) {
              // The scanning window stays square, and the SAME number drives
              // both sides so it cannot stretch. Derived from the screen's
              // height rather than its width because that is the dimension
              // that runs out first — a phone held sideways has plenty of
              // width and very little height, and a 240-point box there would
              // reach past the top and bottom of the viewfinder.
              final side = context.layout.panelHeight(240, maxFraction: 0.45);
              return Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.surface, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              );
            }),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              "Point your camera at the mechanic's QR code",
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textmedium, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}