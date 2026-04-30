import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _updatingProfile = false;
  bool _updatingPassword = false;
  bool _deletingAccount = false;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    setState(() {
      _nameController.text = auth.userName;
      _emailController.text = auth.userEmail;
      _phoneController.text = auth.userPhone;
    });
    
    // Fetch fresh data from API
    try {
      final response = await ApiService.get('/auth/me');
      if (response['success'] == true && mounted) {
        setState(() {
          _userData = response['user'];
        });
      }
    } catch (e) {
      // Silent fail, use cached data from auth provider
    }
  }

  Future<void> _updateProfile() async {
    if (_nameController.text.trim().isEmpty) {
      _showError('Name cannot be empty');
      return;
    }

    setState(() => _updatingProfile = true);
    
    try {
      final response = await ApiService.put('/auth/profile', {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
      });

      if (response['success'] == true) {
        // Update auth provider
        final auth = Provider.of<AuthProvider>(context, listen: false);
        await auth.updateUserData(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
        );
        
        _showSuccess('Profile updated successfully');
      } else {
        _showError(response['message'] ?? 'Failed to update profile');
      }
    } catch (e) {
      _showError('Failed to update profile');
    } finally {
      setState(() => _updatingProfile = false);
    }
  }

  Future<void> _updatePassword() async {
    if (_currentPasswordController.text.isEmpty ||
        _newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      _showError('All password fields are required');
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showError('New passwords do not match');
      return;
    }

    if (_newPasswordController.text.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _updatingPassword = true);
    
    try {
      final response = await ApiService.put('/auth/change-password', {
        'currentPassword': _currentPasswordController.text,
        'newPassword': _newPasswordController.text,
      });

      if (response['success'] == true) {
        _showSuccess('Password updated successfully');
        _clearPasswordFields();
      } else {
        _showError(response['message'] ?? 'Failed to update password');
      }
    } catch (e) {
      _showError('Failed to update password');
    } finally {
      setState(() => _updatingPassword = false);
    }
  }

  void _clearPasswordFields() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: AppColors.error, size: 28),
            const SizedBox(width: 12),
            Text(
              'Delete Account?',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This action cannot be undone. Deleting your account will:',
              style: GoogleFonts.inter(fontSize: 14, color: AppColors.text),
            ),
            const SizedBox(height: 12),
            ..._deleteWarningItems(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Are you sure you want to permanently delete your account?',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.error,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(100, 40),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final finalConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Final Confirmation',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.error),
        ),
        content: Text(
          'This is your last chance. Your account and all data will be permanently deleted.',
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Go Back', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(100, 40),
            ),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );

    if (finalConfirm != true) return;

    setState(() => _deletingAccount = true);

    try {
      await ApiService.delete('/auth/account');
      
      if (mounted) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        await auth.logout();
        
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
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
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  List<Widget> _deleteWarningItems() {
    return [
      _warningItem(Icons.account_balance_wallet_rounded, 'Delete your wallet and all funds'),
      _warningItem(Icons.receipt_long_rounded, 'Remove all transaction history'),
      _warningItem(Icons.credit_card_rounded, 'Cancel any active payment methods'),
      _warningItem(Icons.ev_station_rounded, 'Revoke access to all charging stations'),
    ];
  }

  Widget _warningItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Text(
                  'Profile',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.textDark : AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage your account information',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    color: Theme.of(context).brightness == Brightness.dark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),

                // Profile Header Card
                Container(
                  padding: const EdgeInsets.all(24),
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
                        width: 70,
                        height: 70,
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
                              fontSize: 28,
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
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _userData?['tagId'] ?? auth.userPhone,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Verified',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Profile Information Section
                _buildSection(
                  title: 'Personal Information',
                  children: [
                    _buildTextField(
                      controller: _nameController,
                      label: 'Full Name',
                      icon: Icons.person_rounded,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _emailController,
                      label: 'Email Address',
                      icon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _updatingProfile ? null : _updateProfile,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: _updatingProfile
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Update Profile'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Change Password Section
                _buildSection(
                  title: 'Security',
                  children: [
                    _buildTextField(
                      controller: _currentPasswordController,
                      label: 'Current Password',
                      icon: Icons.lock_rounded,
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _newPasswordController,
                      label: 'New Password',
                      icon: Icons.lock_outline_rounded,
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _confirmPasswordController,
                      label: 'Confirm New Password',
                      icon: Icons.lock_outline_rounded,
                      obscureText: true,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _updatingPassword ? null : _updatePassword,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: _updatingPassword
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Update Password'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Account Actions Section
                _buildSection(
                  title: 'Account Actions',
                  children: [
                    _buildActionTile(
                      icon: Icons.delete_forever_rounded,
                      title: 'Delete Account',
                      subtitle: 'Permanently delete your account and all data',
                      color: AppColors.error,
                      onTap: _deleteAccount,
                      isLoading: _deletingAccount,
                    ),
                  ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
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
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textDark : AppColors.text,
            ),
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: AppColors.error,
                  strokeWidth: 2,
                ),
              )
            else
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: color,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(color: isDark ? AppColors.textDark : AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        filled: true,
        fillColor: isDark ? AppColors.surfaceDark : AppColors.background,
      ),
    );
  }
}
