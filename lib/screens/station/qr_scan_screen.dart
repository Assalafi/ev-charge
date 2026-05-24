import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../config/theme.dart';
import 'station_detail_screen.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  MobileScannerController? _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final value = barcode.rawValue!.trim();
    if (value.isEmpty) return;

    setState(() => _scanned = true);

    // Extract station code from QR code
    final stationCode = _extractStationCode(value);

    // Navigate to station detail
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => StationDetailScreen(chargePointId: stationCode),
      ),
    );
  }

  String _extractStationCode(String qrValue) {
    // If it's a URL with qcodeNum parameter, extract the number
    if (qrValue.contains('qcodeNum=')) {
      final uri = Uri.tryParse(qrValue);
      if (uri != null) {
        final code = uri.queryParameters['qcodeNum'];
        if (code != null && code.isNotEmpty) {
          return code;
        }
      }
    }
    // Otherwise return the value as-is (plain text QR code)
    return qrValue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Scan QR Code',
            style: GoogleFonts.inter(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
            onPressed: () => _controller?.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera
          MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
          ),

          // Overlay
          _buildOverlay(),

          // Bottom instruction
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text(
                  'Scan QR Code to Start Charging',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanArea = constraints.maxWidth * 0.65;
        final top = (constraints.maxHeight - scanArea) / 2;
        final left = (constraints.maxWidth - scanArea) / 2;

        return Stack(
          children: [
            // Dark overlay with hole
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withOpacity(0.5),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    top: top,
                    left: left,
                    child: Container(
                      width: scanArea,
                      height: scanArea,
                      decoration: BoxDecoration(
                        color: Colors.red, // any color
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Corner markers
            Positioned(
              top: top - 2,
              left: left - 2,
              child: _corner(Alignment.topLeft),
            ),
            Positioned(
              top: top - 2,
              right: left - 2,
              child: _corner(Alignment.topRight),
            ),
            Positioned(
              bottom: (constraints.maxHeight - top - scanArea) - 2,
              left: left - 2,
              child: _corner(Alignment.bottomLeft),
            ),
            Positioned(
              bottom: (constraints.maxHeight - top - scanArea) - 2,
              right: left - 2,
              child: _corner(Alignment.bottomRight),
            ),
          ],
        );
      },
    );
  }

  Widget _corner(Alignment alignment) {
    const size = 28.0;
    const thickness = 4.0;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(alignment: alignment, thickness: thickness),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Alignment alignment;
  final double thickness;

  _CornerPainter({required this.alignment, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();

    if (alignment == Alignment.topLeft) {
      path.moveTo(0, size.height * 0.5);
      path.lineTo(0, 0);
      path.lineTo(size.width * 0.5, 0);
    } else if (alignment == Alignment.topRight) {
      path.moveTo(size.width * 0.5, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height * 0.5);
    } else if (alignment == Alignment.bottomLeft) {
      path.moveTo(0, size.height * 0.5);
      path.lineTo(0, size.height);
      path.lineTo(size.width * 0.5, size.height);
    } else {
      path.moveTo(size.width * 0.5, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, size.height * 0.5);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
