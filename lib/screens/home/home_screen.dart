import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../auth/login_screen.dart';
import '../station/search_station_screen.dart';
import '../station/qr_scan_screen.dart';
import '../station/charging_session_screen.dart';
import '../../services/api_service.dart';
import '../../widgets/sliding_ads_board.dart';
import '../../utils/currency_formatter.dart';

class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigateToTab;
  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _activeSession;
  // ignore: unused_field
  bool _checkingSession = false;
  double _walletBalance = 0.0;
  Timer? _refreshTimer;
  int _batteryPercentage = 0;

  @override
  void initState() {
    super.initState();
    _checkActiveSession();
    _fetchWalletBalance();
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchWalletBalance();
      if (_activeSession != null) {
        _fetchBatteryPercentage();
      }
    });
  }

  Future<void> _fetchBatteryPercentage() async {
    if (_activeSession == null) return;
    try {
      final response = await ApiService.get('/charging/status/${_activeSession!['chargePointId']}');
      if (response['success'] == true && response['session'] != null) {
        setState(() {
          _batteryPercentage = response['session']['soc'] ?? 0;
        });
      }
    } catch (_) {
      // Ignore errors
    }
  }

  Future<void> _fetchWalletBalance() async {
    try {
      final response = await ApiService.get('/wallet/balance');
      if (response['success'] == true) {
        setState(() {
          _walletBalance = response['balance']?.toDouble() ?? 0.0;
        });
      }
    } catch (_) {
      // Silent fail, keep showing current balance
    }
  }

  Future<void> _checkActiveSession() async {
    setState(() => _checkingSession = true);
    try {
      final response = await ApiService.get('/transactions');
      if (response['success'] == true && response['transactions'] != null) {
        final txList = response['transactions'] as List;
        final active = txList.cast<Map<String, dynamic>>().where(
            (t) => t['status'] == 'InProgress').toList();
        setState(() {
          if (active.isNotEmpty) {
            _activeSession = active.first;
          } else {
            _activeSession = null;
            _batteryPercentage = 0;
          }
        });
        if (_activeSession != null) {
          await _fetchBatteryPercentage();
        }
      } else {
        setState(() {
          _activeSession = null;
          _batteryPercentage = 0;
        });
      }
    } catch (_) {
      setState(() {
        _activeSession = null;
        _batteryPercentage = 0;
      });
    }
    setState(() => _checkingSession = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final size = MediaQuery.of(context).size;
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;

    return SafeArea(
      child: Container(
        color: isDark ? AppColors.backgroundDark : AppColors.background,
        child: RefreshIndicator(
          onRefresh: () async {
            await _checkActiveSession();
            await _fetchWalletBalance();
          },
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, ${auth.userName.split(' ').first}',
                              style: GoogleFonts.inter(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: isDark ? AppColors.textDark : AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ready to charge?',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primaryLight,
                          child: Text(
                            auth.userName.isNotEmpty
                                ? auth.userName[0].toUpperCase()
                                : 'U',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        onSelected: (value) async {
                          if (value == 'logout') {
                            await auth.logout();
                            if (context.mounted) {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                    builder: (_) => const LoginScreen()),
                                (_) => false,
                              );
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem<String>(
                            enabled: false,
                            child: ListTile(
                              leading: const Icon(Icons.person_outline),
                              title: Text(auth.userName),
                              subtitle: Text(auth.userEmail,
                                  style: const TextStyle(fontSize: 12)),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            value: 'logout',
                            child: ListTile(
                              leading: Icon(Icons.logout, color: AppColors.error),
                              title: Text('Logout',
                                  style: TextStyle(color: AppColors.error)),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Active Session Banner
                  if (_activeSession != null)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChargingSessionScreen(
                              chargePointId: _activeSession!['chargePointId'],
                            ),
                          ),
                        ).then((_) => _checkActiveSession());
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00C853), Color(0xFF00E676)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.bolt_rounded,
                                  color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Charging in Progress',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      )),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Station: ${_activeSession!['chargePointId']}',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.battery_charging_full_rounded,
                                          color: Colors.white, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$_batteryPercentage%',
                                        style: TextStyle(
                                            color: Colors.white.withOpacity(0.9),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_ios_rounded,
                                color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    ),

                  if (_activeSession != null) const SizedBox(height: 24),

                  // Wallet Balance Card
                  GestureDetector(
                    onTap: () {
                      widget.onNavigateToTab?.call(2); // Navigate to wallet tab (index 2)
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, Color(0xFF1976D2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Wallet Balance',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  CurrencyFormatter.format(_walletBalance),
                                  style: GoogleFonts.inter(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white.withOpacity(0.9),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Main Action Cards
                  SizedBox(
                    height: size.height * 0.25,
                    child: Row(
                      children: [
                        // Scan QR Code
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.qr_code_scanner_rounded,
                            title: 'Scan QR Code\non Available\nCharging Pile',
                            subtitle: '',
                            gradient: const [
                              Color(0xFF3DD68C),
                              Color(0xFF2DB376)
                            ],
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const QrScanScreen()),
                              ).then((_) => _checkActiveSession());
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Search Station
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.location_on_rounded,
                            title: 'Find Nearest\nCharging Pile',
                            subtitle: '',
                            gradient: const [
                              Color(0xFF1B2150),
                              Color(0xFF121838)
                            ],
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const SearchStationScreen()),
                              ).then((_) => _checkActiveSession());
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Ads Board - Sliding ads
                  const SlidingAdsBoard(
                    height: 100.0,
                  ),
                  const SizedBox(height: 24),

                  // Quick Stats
                  Text(
                    'Quick Info',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.textDark : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.badge_outlined,
                          label: 'Your Tag ID',
                          value: auth.userTagId,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          value: auth.userPhone,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
      );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.borderDark : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 10),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value.isNotEmpty ? value : '---',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textDark : AppColors.text,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
