import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/ui/app_theme.dart';
import '../../core/ui/widgets/bold_controls.dart';

/// Screen 4c — the camera barcode scanner.
///
/// Deliberately dumb: it finds a barcode and pops with the raw string. Resolving
/// that code through the source chain (custom → cache → pack → online) and
/// deciding what to do with the result is the caller's job, so the same scanner
/// serves logging into a meal and picking a recipe ingredient.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    // Retail barcodes only: narrowing the formats speeds up detection and
    // avoids matching a stray QR code lying on the counter.
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
    ],
  );

  /// One barcode per screen: the detection stream fires many times a second, so
  /// without this the pop would run repeatedly and unwind the wrong routes.
  bool _handled = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    String? code;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        code = value;
        break;
      }
    }
    if (code == null) return;

    _handled = true;
    Navigator.of(context).pop(code);
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (mounted) setState(() => _torchOn = !_torchOn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // The aiming window. A plain lime frame, not a real cut-out — the
          // guidance is "hold the barcode here", which a border conveys.
          Center(
            child: Container(
              width: 260,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.lime, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Row(
                    children: [
                      SquareIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Zurück',
                        onPressed: Navigator.of(context).pop,
                      ),
                      const Spacer(),
                      SquareIconButton(
                        icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                        tooltip: 'Blitz',
                        onPressed: _toggleTorch,
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: Text(
                    'Barcode in den Rahmen halten',
                    style: AppText.grotesk(
                      size: 14,
                      weight: 600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
