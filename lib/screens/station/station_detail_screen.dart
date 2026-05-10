import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../utils/currency_formatter.dart';
import 'charging_session_screen.dart';

class StationDetailScreen extends StatefulWidget {
  final String chargePointId;
  const StationDetailScreen({super.key, required this.chargePointId});

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  Map<String, dynamic>? _station;
  bool _loading = true;
  bool _starting = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchStation();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchStationSilent();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStationSilent() async {
    try {
      final response =
          await ApiService.get('/stations/${widget.chargePointId}');
      if (response['success'] == true && mounted) {
        setState(() => _station = response['station']);
      }
    } catch (_) {}
  }

  Future<void> _fetchStation() async {
    try {
      final response =
          await ApiService.get('/stations/${widget.chargePointId}');
      if (response['success'] == true) {
        setState(() => _station = response['station']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _startCharging() async {
    setState(() => _starting = true);
    try {
      final response = await ApiService.post('/charging/start', {
        'chargePointId': widget.chargePointId,
        'connectorId': 1,
      });

      if (response['success'] == true && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChargingSessionScreen(
              chargePointId: widget.chargePointId,
              justStarted: true,
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Connection error'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    setState(() => _starting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Station Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _station == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text('Station not found',
                          style: GoogleFonts.inter(fontSize: 16)),
                    ],
                  ),
                )
              : _buildContent(),
      bottomNavigationBar: _station != null ? _buildBottomBar() : null,
    );
  }

  static const Color _preparingColor = Color(0xFFF59E0B);

  Color _simpleStatusColor(String status) {
    switch (status) {
      case 'Ready':
        return AppColors.available;
      case 'Plug In':
        return _preparingColor;
      case 'In Use':
        return AppColors.charging;
      case 'Unavailable':
        return AppColors.faulted;
      default:
        return AppColors.offline;
    }
  }

  IconData _simpleStatusIcon(String status) {
    switch (status) {
      case 'Ready':
        return Icons.check_circle_rounded;
      case 'Plug In':
        return Icons.power_rounded;
      case 'In Use':
        return Icons.bolt_rounded;
      case 'Unavailable':
        return Icons.error_rounded;
      default:
        return Icons.cloud_off_rounded;
    }
  }

  Color _connectorRawColor(String status) {
    switch (status) {
      case 'Available':
        return AppColors.available;
      case 'Preparing':
        return _preparingColor;
      case 'Charging':
        return AppColors.charging;
      case 'SuspendedEV':
      case 'SuspendedEVSE':
        return const Color(0xFF6366F1);
      case 'Finishing':
        return AppColors.primary;
      case 'Faulted':
        return AppColors.faulted;
      default:
        return AppColors.offline;
    }
  }

  IconData _connectorRawIcon(String status) {
    switch (status) {
      case 'Available':
        return Icons.check_circle_outline_rounded;
      case 'Preparing':
        return Icons.power_rounded;
      case 'Charging':
        return Icons.bolt_rounded;
      case 'SuspendedEV':
      case 'SuspendedEVSE':
        return Icons.pause_circle_rounded;
      case 'Finishing':
        return Icons.task_alt_rounded;
      case 'Faulted':
        return Icons.error_rounded;
      default:
        return Icons.cloud_off_rounded;
    }
  }

  String _connectorRawLabel(String status) {
    switch (status) {
      case 'Available':
        return 'Available';
      case 'Preparing':
        return 'Gun Inserted';
      case 'Charging':
        return 'Charging';
      case 'SuspendedEV':
        return 'Suspended (EV)';
      case 'SuspendedEVSE':
        return 'Suspended';
      case 'Finishing':
        return 'Finishing';
      case 'Faulted':
        return 'Faulted';
      default:
        return 'Offline';
    }
  }

  Widget _buildContent() {
    final s = _station!;
    final simpleStatus = s['simpleStatus'] ?? 'Offline';
    final rawStatus = s['status'] ?? 'Unknown';
    final isOnline = s['isOnline'] == true;
    final connectors = (s['connectors'] as List?) ?? [];
    final address = s['address'] ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use raw status for richer top-level display
    final hasGunInserted = rawStatus == 'Preparing' ||
        connectors.any((c) => c['status'] == 'Preparing');
    final displayStatus = hasGunInserted && simpleStatus == 'Ready'
        ? 'Plug In'
        : simpleStatus;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Station Header Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isOnline
                    ? [const Color(0xFF00C853), const Color(0xFF00E676)]
                    : [const Color(0xFF6B7280), const Color(0xFF9CA3AF)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.ev_station_rounded,
                        color: Colors.white, size: 32),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _simpleStatusIcon(displayStatus),
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            displayStatus,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  s['name'] ?? widget.chargePointId,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          color: Colors.white.withOpacity(0.85), size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (s['latitude'] is num && s['longitude'] is num)
                        InkWell(
                          onTap: () => _openGoogleMaps(
                            (s['latitude'] as num).toDouble(),
                            (s['longitude'] as num).toDouble(),
                            s['name'] ?? widget.chargePointId,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.near_me_rounded,
                                    color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Navigate',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Real-time indicator
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withOpacity(0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Live',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
              const Spacer(),
              Text(
                'Updates every 3s',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Pricing & Wallet Section
          const SizedBox(height: 24),
          Text('Pricing',
              style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textDark : AppColors.text)),
          const SizedBox(height: 12),
          Row(
            children: [
              _infoCard(
                'Rate',
                '${s['pricePerKwh'] ?? '-'}/kWh',
                Icons.electric_bolt_rounded,
              ),
              const SizedBox(width: 12),
              _infoCard(
                'Min. Charge',
                CurrencyFormatter.format((s['minimumCharge'] ?? 150).toDouble()),
                Icons.receipt_long_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _walletCard(s),

          if (connectors.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Connectors',
                style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textDark : AppColors.text)),
            const SizedBox(height: 12),
            ...connectors.map<Widget>((c) {
              final cStatus = c['status'] ?? 'Unknown';
              final cColor = _connectorRawColor(cStatus);
              final cIcon = _connectorRawIcon(cStatus);
              final cLabel = _connectorRawLabel(cStatus);
              final isPreparing = cStatus == 'Preparing';

              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isPreparing
                      ? _preparingColor.withOpacity(isDark ? 0.15 : 0.05)
                      : (isDark ? AppColors.cardDark : Colors.white),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isPreparing
                        ? _preparingColor.withOpacity(0.5)
                        : (isDark ? AppColors.borderDark : AppColors.border),
                    width: isPreparing ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(cIcon, color: cColor, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Connector ${c['connectorId']}',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: isDark ? AppColors.textDark : AppColors.text,
                                  )),
                              const SizedBox(height: 2),
                              Text(
                                'OCPP: $cStatus',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: cColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isPreparing)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(Icons.cable_rounded,
                                      size: 14, color: cColor),
                                ),
                              Text(cLabel,
                                  style: TextStyle(
                                    color: cColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (isPreparing) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _preparingColor.withOpacity(isDark ? 0.2 : 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 16, color: _preparingColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'EV cable connected — ready to start charging',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _preparingColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value, IconData icon,
      {Color? valueColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: valueColor ?? AppColors.primary),
            const SizedBox(height: 10),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text(value,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: valueColor ?? (isDark ? AppColors.textDark : AppColors.text)),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _walletCard(Map<String, dynamic> s) {
    final balance = (s['walletBalance'] ?? 0).toDouble();
    final minCharge = (s['minimumCharge'] ?? 150).toDouble();
    final sufficient = balance >= minCharge;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: sufficient ? AppColors.success.withOpacity(0.05) : AppColors.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: sufficient ? AppColors.success.withOpacity(0.3) : AppColors.error.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_rounded,
            color: sufficient ? AppColors.success : AppColors.error,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Wallet Balance',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                Text(
                  CurrencyFormatter.format(balance),
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: sufficient ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
          if (!sufficient)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Low',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildBottomBar() {
    final simpleStatus = _station?['simpleStatus'] ?? 'Offline';
    final rawStatus = _station?['status'] ?? 'Unknown';
    final connectors = (_station?['connectors'] as List?) ?? [];
    final stationReady = simpleStatus == 'Ready';
    final walletBalance = (_station?['walletBalance'] ?? 0).toDouble();
    final minimumCharge = (_station?['minimumCharge'] ?? 150).toDouble();
    final walletOk = walletBalance >= minimumCharge;

    // Gun must be plugged in (Preparing) before starting
    final gunPlugged = rawStatus == 'Preparing' ||
        connectors.any((c) => c['status'] == 'Preparing');
    final canStart = stationReady && walletOk && gunPlugged;

    String buttonText;
    if (!stationReady) {
      buttonText = simpleStatus == 'Offline'
          ? 'Station Offline'
          : simpleStatus == 'In Use'
              ? 'Station In Use'
              : 'Station Unavailable';
    } else if (!gunPlugged) {
      buttonText = 'Plug In Cable to Start';
    } else if (!walletOk) {
      buttonText = 'Insufficient Balance (min ${CurrencyFormatter.format(minimumCharge)})';
    } else {
      buttonText = 'Start Charging';
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show plug-in guide when station is ready but gun not inserted
    if (stationReady && !gunPlugged) {
      return Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          border: Border(top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.cable_rounded,
                          color: AppColors.warning, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Connect the charging cable',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.textDark : AppColors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _guideStep(1, 'Open your vehicle\'s charging port', Icons.directions_car_rounded, isDark),
                  const SizedBox(height: 8),
                  _guideStep(2, 'Take the connector from the station', Icons.ev_station_rounded, isDark),
                  const SizedBox(height: 8),
                  _guideStep(3, 'Plug it into your car until it clicks', Icons.power_rounded, isDark),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Waiting for cable connection...',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                ),
                child: Text(buttonText),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        border: Border(top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.border)),
      ),
      child: ElevatedButton(
        onPressed: canStart && !_starting ? _startCharging : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canStart ? AppColors.primary : Colors.grey[300],
        ),
        child: _starting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : Text(buttonText),
      ),
    );
  }

  Widget _guideStep(int step, String text, IconData icon, bool isDark) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$step',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.warning,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openGoogleMaps(double lat, double lng, String name) async {
    final googleMapsUrl = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final webUrl = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open Google Maps: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
