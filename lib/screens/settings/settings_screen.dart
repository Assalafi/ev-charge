import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../auth/login_screen.dart';
import '../profile/profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _notificationsEnabled = true;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String _appVersion = '1.0.0';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if device supports biometrics
    bool canCheckBio = false;
    try {
      canCheckBio = await _localAuth.canCheckBiometrics;
      if (canCheckBio) {
        final availableBio = await _localAuth.getAvailableBiometrics();
        canCheckBio = availableBio.isNotEmpty;
      }
    } catch (_) {
      canCheckBio = false;
    }

    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
        _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
        _biometricAvailable = canCheckBio;
        _loading = false;
      });
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    await _saveSetting('notifications_enabled', value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Notifications enabled' : 'Notifications disabled'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    await themeProvider.toggleTheme(value);
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      // Verify biometric before enabling
      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Verify your identity to enable biometric login',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );
        if (!authenticated) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Biometric verification failed'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Biometric error: ${e.toString()}'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    setState(() => _biometricEnabled = value);
    await _saveSetting('biometric_enabled', value);

    // If disabling, clear saved credentials
    if (!value) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('bio_identifier');
      await prefs.remove('bio_password');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value
              ? 'Biometric login enabled. Sign in once to save credentials.'
              : 'Biometric login disabled'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final auth = Provider.of<AuthProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return SafeArea(
      child: Container(
        color: isDark ? AppColors.backgroundDark : AppColors.background,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Settings',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.textDark : AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Customize your app experience',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),

                // User Card
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            auth.userName.isNotEmpty
                                ? auth.userName[0].toUpperCase()
                                : 'U',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              auth.userName,
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              auth.userEmail,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white.withOpacity(0.8),
                        size: 16,
                      ),
                    ],
                  ),
                ),
                ),

                const SizedBox(height: 32),

                // Account Section
                _buildSection(
                  title: 'Account',
                  children: [
                    _buildSettingTile(
                      icon: Icons.person_rounded,
                      title: 'Profile Information',
                      subtitle: 'Update your personal details',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProfileScreen()),
                        );
                      },
                    ),
                    _buildDivider(),
                    _buildSettingTile(
                      icon: Icons.security_rounded,
                      title: 'Privacy & Security',
                      subtitle: 'Manage your privacy settings',
                      onTap: () => _showPrivacyDialog(),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Preferences Section
                _buildSection(
                  title: 'Preferences',
                  children: [
                    _buildSwitchTile(
                      icon: Icons.notifications_rounded,
                      title: 'Push Notifications',
                      subtitle: 'Receive charging updates',
                      value: _notificationsEnabled,
                      onChanged: _toggleNotifications,
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.dark_mode_rounded,
                      title: 'Dark Mode',
                      subtitle: 'Use dark theme',
                      value: isDark,
                      onChanged: _toggleDarkMode,
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.fingerprint_rounded,
                      title: 'Biometric Login',
                      subtitle: _biometricAvailable
                          ? 'Use fingerprint or face ID'
                          : 'Not available on this device',
                      value: _biometricEnabled,
                      onChanged: _biometricAvailable ? (v) => _toggleBiometric(v) : null,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Support Section
                _buildSection(
                  title: 'Support',
                  children: [
                    _buildSettingTile(
                      icon: Icons.help_rounded,
                      title: 'Help Center',
                      subtitle: 'Get help and support',
                      onTap: () => _showHelpDialog(),
                    ),
                    _buildDivider(),
                    _buildSettingTile(
                      icon: Icons.contact_support_rounded,
                      title: 'Contact Us',
                      subtitle: 'Get in touch with our team',
                      onTap: () => _showContactDialog(),
                    ),
                    _buildDivider(),
                    _buildSettingTile(
                      icon: Icons.description_rounded,
                      title: 'Terms & Conditions',
                      subtitle: 'Read our terms and conditions',
                      onTap: () => _showTermsDialog(),
                    ),
                    _buildDivider(),
                    _buildSettingTile(
                      icon: Icons.privacy_tip_rounded,
                      title: 'Privacy Policy',
                      subtitle: 'Read our privacy policy',
                      onTap: () => _showPrivacyDialog(),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // About Section
                _buildSection(
                  title: 'About',
                  children: [
                    _buildSettingTile(
                      icon: Icons.info_rounded,
                      title: 'App Version',
                      subtitle: _appVersion,
                      onTap: null,
                    ),
                    _buildDivider(),
                    _buildSettingTile(
                      icon: Icons.star_rounded,
                      title: 'Rate App',
                      subtitle: 'Rate us on the app store',
                      onTap: () => _showRateDialog(),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Logout Button
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: isDark ? [] : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: Icon(Icons.logout_rounded, color: AppColors.error),
                    title: Text(
                      'Logout',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                    subtitle: Text(
                      'Sign out of your account',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    onTap: () => _showLogoutDialog(),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark ? [] : [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.textDark : AppColors.text,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return ListTile(
      leading: Icon(
        icon,
        color: AppColors.primary,
        size: 24,
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: isDark ? AppColors.textDark : AppColors.text,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(
          fontSize: 13,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
        ),
      ),
      trailing: onTap != null
          ? Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            )
          : null,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final enabled = onChanged != null;
    return ListTile(
      leading: Icon(
        icon,
        color: enabled ? AppColors.primary : AppColors.offline,
        size: 24,
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: enabled
              ? (isDark ? AppColors.textDark : AppColors.text)
              : AppColors.textSecondary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(
          fontSize: 13,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    );
  }

  Widget _buildDivider() {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Divider(
        height: 1,
        color: isDark ? AppColors.borderDark : AppColors.border,
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Logout',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final auth = Provider.of<AuthProvider>(context, listen: false);
              await auth.logout();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Help Center',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpItem(
                'How to start charging?',
                '1. Go to Home\n2. Scan QR code or find location\n3. Tap "Start Charging"',
              ),
              const SizedBox(height: 16),
              _buildHelpItem(
                'How to add funds?',
                '1. Go to Wallet\n2. Tap "Add Funds"\n3. Select amount and pay',
              ),
              const SizedBox(height: 16),
              _buildHelpItem(
                'How to view history?',
                '1. Go to Transactions\n2. View all your charging sessions',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String question, String answer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          answer,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  void _showContactDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Contact Us',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildContactItem(Icons.email_rounded, 'Email', 'support@evcharge.ng'),
            const SizedBox(height: 16),
            _buildContactItem(Icons.phone_rounded, 'Phone', '+234 800 000 0000'),
            const SizedBox(height: 16),
            _buildContactItem(Icons.location_on_rounded, 'Address', 'Lagos, Nigeria'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Terms & Conditions',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'By using this app, you agree to our terms of service. '
          'The app is provided "as is" without warranties of any kind. '
          'We are not liable for any damages arising from the use of this service.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Privacy Policy',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'We value your privacy. Your personal information is securely stored '
          'and only used to provide our services. We do not share your data with '
          'third parties without your consent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showRateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Rate Our App',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enjoying EV Charge?',
              style: GoogleFonts.inter(fontSize: 16, color: AppColors.text),
            ),
            const SizedBox(height: 8),
            Text(
              'Your feedback helps us improve',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.star_rounded,
                    color: AppColors.warning,
                    size: 40,
                  ),
                );
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Thank you for your feedback!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: const Text('Rate Now'),
          ),
        ],
      ),
    );
  }
}
