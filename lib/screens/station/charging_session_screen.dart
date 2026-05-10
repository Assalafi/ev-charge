import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../utils/currency_formatter.dart';

class ChargingSessionScreen extends StatefulWidget {
  final String chargePointId;
  final bool justStarted;
  const ChargingSessionScreen({
    super.key,
    required this.chargePointId,
    this.justStarted = false,
  });

  @override
  State<ChargingSessionScreen> createState() => _ChargingSessionScreenState();
}

class _ChargingSessionScreenState extends State<ChargingSessionScreen>
    with SingleTickerProviderStateMixin {
  Timer? _pollTimer;
  bool _loading = true;
  bool _stopping = false;
  bool _active = false;
  Map<String, dynamic>? _session;
  late AnimationController _pulseController;
  String? _autoStopType;
  double? _autoStopValue;
  double _minimumCharge = 150;
  bool _wasActive = false;
  bool _summaryShown = false;
  bool _waitingForSession = false;
  int _waitRetries = 0;
  static const int _maxWaitRetries = 15; // 15 retries × 2s = 30s max wait

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    if (widget.justStarted) {
      // Session was just started — charger needs time to respond
      _waitingForSession = true;
      _waitRetries = 0;
      _pollForNewSession();
    } else {
      _fetchStatus();
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchStatus());
    }
  }

  Future<void> _pollForNewSession() async {
    while (_waitRetries < _maxWaitRetries && mounted) {
      _waitRetries++;
      try {
        final response =
            await ApiService.get('/charging/status/${widget.chargePointId}');
        if (response['success'] == true && response['active'] == true) {
          // Session found — switch to normal mode
          if (mounted) {
            setState(() {
              _waitingForSession = false;
              _active = true;
              _wasActive = true;
              _session = response['session'] as Map<String, dynamic>?;
              _autoStopType = _session?['autoStopType'];
              _autoStopValue = _session?['autoStopValue']?.toDouble();
              _minimumCharge = (_session?['minimumCharge'] ?? 150).toDouble();
              _loading = false;
            });
            // Start normal polling
            _pollTimer = Timer.periodic(
                const Duration(seconds: 5), (_) => _fetchStatus());
          }
          return;
        }
      } catch (_) {}
      // Wait 2 seconds before retrying
      await Future.delayed(const Duration(seconds: 2));
    }
    // Timed out — give up and show normal state
    if (mounted) {
      setState(() {
        _waitingForSession = false;
        _loading = false;
      });
      _pollTimer = Timer.periodic(
          const Duration(seconds: 5), (_) => _fetchStatus());
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      final response =
          await ApiService.get('/charging/status/${widget.chargePointId}');
      if (response['success'] == true && mounted) {
        final isActive = response['active'] == true;
        
        // Detect session ended (was active, now inactive) — show summary
        if (_wasActive && !isActive && !_summaryShown) {
          _summaryShown = true;
          final lastSession = response['lastSession'] as Map<String, dynamic>?;
          if (lastSession != null) {
            _pollTimer?.cancel();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showSessionSummary(lastSession);
            });
          }
        }
        
        setState(() {
          _active = isActive;
          if (isActive) _wasActive = true;
          _session = response['session'] as Map<String, dynamic>?;
          _autoStopType = _session?['autoStopType'];
          _autoStopValue = _session?['autoStopValue']?.toDouble();
          _minimumCharge = (_session?['minimumCharge'] ?? 150).toDouble();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stopCharging() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Stop Charging?'),
        content: const Text('Are you sure you want to stop the charging session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(100, 44),
            ),
            child: const Text('Stop'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _stopping = true);
    try {
      await ApiService.post('/charging/stop', {
        'chargePointId': widget.chargePointId,
      });
      // Don't pop — let polling detect the stop and show summary dialog
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection error'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
    if (mounted) setState(() => _stopping = false);
  }

  void _showSessionSummary(Map<String, dynamic> session) {
    if (!mounted) return;
    final energy = (session['energyDelivered'] ?? 0).toDouble();
    final amount = (session['amount'] ?? 0).toDouble();
    final duration = session['duration'] ?? 0;
    final stopReason = session['stopReason'] ?? 'Session ended';

    // Determine icon and color based on stop reason
    IconData icon;
    Color color;
    if (stopReason.toString().contains('Insufficient')) {
      icon = Icons.account_balance_wallet_outlined;
      color = AppColors.error;
    } else if (stopReason.toString().contains('Auto-stop')) {
      icon = Icons.check_circle_rounded;
      color = AppColors.success;
    } else if (stopReason.toString().contains('by you')) {
      icon = Icons.stop_circle_rounded;
      color = AppColors.primary;
    } else {
      icon = Icons.info_rounded;
      color = AppColors.textSecondary;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              'Charging Complete',
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                stopReason,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _summaryItem(Icons.bolt_rounded, '${(energy / 1000).toStringAsFixed(2)} kWh', 'Energy'),
                const SizedBox(width: 12),
                _summaryItem(Icons.timer_outlined, _formatDuration(duration is int ? duration : 0), 'Duration'),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text('Amount Charged', style: GoogleFonts.inter(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                    CurrencyFormatter.format(amount),
                    style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
            Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  Future<void> _showAutoStopDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _AutoStopDialog(
        currentType: _autoStopType,
        currentValue: _autoStopValue,
        minimumCharge: _minimumCharge,
      ),
    );

    if (result == null) return;

    try {
      final response = await ApiService.post('/charging/autostop', {
        'chargePointId': widget.chargePointId,
        'autoStopType': result['type'],
        'autoStopValue': result['value'],
      });

      if (response['success'] == true && mounted) {
        setState(() {
          _autoStopType = result['type'];
          _autoStopValue = result['value'];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Auto-stop condition set'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to set auto-stop condition'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _clearAutoStop() async {
    try {
      final response = await ApiService.delete('/charging/autostop', body: {
        'chargePointId': widget.chargePointId,
      });

      if (response['success'] == true && mounted) {
        setState(() {
          _autoStopType = null;
          _autoStopValue = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Auto-stop condition cleared'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear auto-stop condition'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Charging Session'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _waitingForSession
              ? _buildWaitingForSession()
              : !_active
                  ? _buildNoSession()
                  : _buildSession(),
    );
  }

  Widget _buildWaitingForSession() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AnimBuilder(
              listenable: _pulseController,
              builder: (context, _) {
                return Opacity(
                  opacity: 0.5 + (_pulseController.value * 0.5),
                  child: Icon(Icons.ev_station_rounded,
                      size: 80, color: AppColors.primary),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Starting Charging...',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Waiting for the charger to confirm.\nThis may take a few seconds.',
              style: GoogleFonts.inter(
                  fontSize: 15, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Attempt $_waitRetries / $_maxWaitRetries',
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSession() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.power_off_rounded, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 24),
            Text(
              'No Active Session',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'There is no charging session at this station',
              style: GoogleFonts.inter(
                  fontSize: 15, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSession() {
    final energy = (_session?['energyDelivered'] ?? 0).toDouble(); // Always in Wh
    final energyKwh = energy / 1000; // Convert Wh to kWh for display
    final duration = _session?['duration'] ?? 0;
    final amount = (_session?['amount'] ?? 0).toDouble();
    final connStatus = _session?['connectorStatus'] ?? 'Charging';
    final soc = (_session?['soc'] ?? 0).toInt(); // State of Charge in percentage

    return Stack(
      children: [
        SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Animated Charging Indicator
          _AnimBuilder(
            listenable: _pulseController,
            builder: (context, _) {
              final glow = 0.15 + (_pulseController.value * 0.15);
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(glow),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: CircularPercentIndicator(
                  radius: 100,
                  lineWidth: 12,
                  percent: (soc / 100).clamp(0.0, 1.0),
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        soc >= 80 ? Icons.battery_full_rounded :
                        soc >= 60 ? Icons.battery_6_bar_rounded :
                        soc >= 40 ? Icons.battery_4_bar_rounded :
                        soc >= 20 ? Icons.battery_2_bar_rounded :
                        Icons.battery_0_bar_rounded,
                        color: _getBatteryColor(soc),
                        size: 36,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${soc}%',
                        style: GoogleFonts.inter(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      Text('Battery',
                          style: GoogleFonts.inter(
                              color: AppColors.textSecondary, fontSize: 14)),
                    ],
                  ),
                  progressColor: _getBatteryColor(soc),
                  backgroundColor: AppColors.border,
                  circularStrokeCap: CircularStrokeCap.round,
                  animation: false,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 255, 255, 255),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(connStatus,
                    style: GoogleFonts.inter(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Energy Card
          _energyCard(energyKwh),
          const SizedBox(height: 16),
          
          // Stats Cards
          Row(
            children: [
              _statCard(
                Icons.timer_outlined,
                'Duration',
                _formatDuration(duration is int ? duration : 0),
              ),
              const SizedBox(width: 12),
              _statCard(
                Icons.ev_station_rounded,
                'Station',
                widget.chargePointId,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statCard(
                '₦',
                'Cost',
                CurrencyFormatter.format(amount),
              ),
              const SizedBox(width: 12),
              _statCard(
                Icons.numbers_rounded,
                'Transaction',
                '#${_session?['transactionId'] ?? '-'}',
              ),
            ],
          ),
          const SizedBox(height: 40),

          // Stop Button
          ElevatedButton(
            onPressed: _stopping ? null : _stopCharging,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: _stopping
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.stop_circle_rounded, size: 22),
                      const SizedBox(width: 8),
                      Text('Stop Charging',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          // Auto-stop section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Auto-Stop',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    if (_autoStopType != null)
                      TextButton(
                        onPressed: _clearAutoStop,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_autoStopType != null && _autoStopValue != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _autoStopType == 'percentage'
                              ? Icons.battery_charging_full
                              : Icons.payments,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _autoStopType == 'percentage'
                                ? 'Stop at ${(_autoStopValue ?? 0).toInt()}% battery'
                                : 'Stop at ${CurrencyFormatter.format(_autoStopValue ?? 0)}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _showAutoStopDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Set Condition'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),

        // Stopping overlay
        if (_stopping)
          Container(
            color: Colors.black54,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 48),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        color: AppColors.error,
                        strokeWidth: 5,
                        backgroundColor: AppColors.error.withOpacity(0.15),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Stopping Session...',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please wait while we safely\nstop your charging session',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _energyCard(double energyKwh) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withOpacity(0.1), AppColors.primary.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.electric_bolt_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Energy Delivered',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${energyKwh.toStringAsFixed(2)} kWh',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (energyKwh / 50).clamp(0.0, 1.0), // Assuming 50kWh as full reference
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(dynamic icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            icon is IconData
                ? Icon(icon, color: AppColors.primary, size: 22)
                : Text(
                    icon as String,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
            const SizedBox(height: 12),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value,
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.text),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Color _getBatteryColor(int soc) {
    if (soc >= 80) return AppColors.success;
    if (soc >= 60) return AppColors.primary;
    if (soc >= 40) return Colors.orange;
    if (soc >= 20) return Colors.deepOrange;
    return AppColors.error;
  }
}

class _AnimBuilder extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;

  const _AnimBuilder({
    required Listenable listenable,
    required this.builder,
  }) : super(listenable: listenable);

  @override
  Widget build(BuildContext context) {
    return builder(context, null);
  }
}

class _AutoStopDialog extends StatefulWidget {
  final String? currentType;
  final double? currentValue;
  final double minimumCharge;

  const _AutoStopDialog({
    required this.currentType,
    required this.currentValue,
    required this.minimumCharge,
  });

  @override
  State<_AutoStopDialog> createState() => _AutoStopDialogState();
}

class _AutoStopDialogState extends State<_AutoStopDialog> {
  String _selectedType = 'percentage';
  final TextEditingController _valueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.currentType != null) {
      _selectedType = widget.currentType!;
      _valueController.text = widget.currentValue?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Set Auto-Stop Condition',
        style: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stop charging automatically when:',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'percentage',
                label: Text('Battery %'),
                icon: Icon(Icons.battery_charging_full),
              ),
              ButtonSegment(
                value: 'amount',
                label: Text('Amount'),
                icon: Icon(Icons.payments),
              ),
            ],
            selected: {_selectedType},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() {
                _selectedType = newSelection.first;
                _valueController.clear();
              });
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _valueController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: _selectedType == 'percentage' ? 'Target Percentage' : 'Target Amount',
              hintText: _selectedType == 'percentage' ? '0 - 100' : 'Amount in Naira',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_selectedType == 'percentage')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Charging will stop when battery reaches this percentage',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (_selectedType == 'amount')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Charging will stop when cost reaches this amount',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final value = double.tryParse(_valueController.text);
            if (value == null || value <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please enter a valid value'),
                  backgroundColor: AppColors.error,
                ),
              );
              return;
            }
            if (_selectedType == 'percentage' && value > 100) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Percentage cannot exceed 100'),
                  backgroundColor: AppColors.error,
                ),
              );
              return;
            }
            if (_selectedType == 'amount' && value <= widget.minimumCharge) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Amount must be greater than minimum charge (₦${widget.minimumCharge.toStringAsFixed(0)})'),
                  backgroundColor: AppColors.error,
                ),
              );
              return;
            }
            Navigator.pop(context, {
              'type': _selectedType,
              'value': value,
            });
          },
          child: const Text('Set'),
        ),
      ],
    );
  }
}
