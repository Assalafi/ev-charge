import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/paystack_web.dart' as paystack_web;
import '../../utils/currency_formatter.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  double _balance = 0.0;
  bool _loading = true;
  bool _funding = false;
  String _publicKey = '';
  List<Map<String, dynamic>> _transactions = [];
  bool _loadingTransactions = false;
  String _filterStatus = 'ALL';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;

  @override
  void initState() {
    super.initState();
    _fetchPaystackConfig();
    _fetchWalletBalance();
    _fetchTransactions();
  }

  Future<void> _fetchPaystackConfig() async {
    try {
      final response = await ApiService.get('/wallet/paystack-config');
      if (response['success'] == true && response['publicKey'] != null) {
        setState(() {
          _publicKey = response['publicKey'];
        });
      }
    } catch (e) {
      print('Error fetching Paystack config: $e');
    }
  }

  Future<void> _fetchWalletBalance() async {
    setState(() => _loading = true);
    try {
      final response = await ApiService.get('/wallet/balance');
      if (response['success'] == true) {
        setState(() {
          _balance = response['balance']?.toDouble() ?? 0.0;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchTransactions() async {
    setState(() => _loadingTransactions = true);
    try {
      final response = await ApiService.get('/wallet/transactions');
      if (response['success'] == true) {
        setState(() {
          _transactions = List<Map<String, dynamic>>.from(response['transactions'] ?? []);
          _loadingTransactions = false;
        });
      } else {
        setState(() => _loadingTransactions = false);
      }
    } catch (e) {
      setState(() => _loadingTransactions = false);
    }
  }

  Future<void> _retryPayment(String reference) async {
    try {
      final response = await ApiService.get('/wallet/verify?reference=$reference');
      
      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment verified successfully'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        await _fetchWalletBalance();
        await _fetchTransactions();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Verification failed'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error verifying payment: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _addFunds(double amount) async {
    setState(() => _funding = true);
    
    // Show loading overlay while initializing payment
    BuildContext? overlayContext;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        overlayContext = ctx;
        return WillPopScope(
          onWillPop: () async => false,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Initializing payment...',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final response = await ApiService.post('/wallet/fund', {
        'amount': amount,
        'email': auth.userEmail,
      });

      // Dismiss loading overlay
      if (overlayContext != null && Navigator.canPop(overlayContext!)) {
        Navigator.pop(overlayContext!);
      }

      if (response['success'] == true) {
        // Both Web and Mobile: use Paystack authorization_url (has channel restrictions from backend)
        final ref = response['reference'] as String;
        final authUrl = response['authorization_url'] as String?;
        if (authUrl == null || authUrl.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Payment initialization failed'),
                backgroundColor: AppColors.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          setState(() => _funding = false);
          return;
        }

        if (kIsWeb) {
          // Web: use web popup implementation
          await paystack_web.openPaystackPopup(
            publicKey: _publicKey,
            email: auth.userEmail,
            amountInKobo: (amount * 100).toInt(),
            reference: ref,
            accessCode: response['access_code'] ?? '',
            authorizationUrl: authUrl,
            onSuccess: (reference) async {
              await _verifyPayment(reference);
              await _fetchTransactions();
            },
            onClose: () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Payment window closed'),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              setState(() => _funding = false);
            },
          );
        } else {
          // Mobile: use WebView for in-app payment
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PaystackWebView(
                url: authUrl,
                reference: ref,
              ),
            ),
          );
          if (result == 'success') {
            await _verifyPayment(ref);
            await _fetchTransactions();
          } else if (result == 'cancelled') {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Payment cancelled'),
                  backgroundColor: AppColors.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to initialize payment'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      // Dismiss loading overlay on error
      if (overlayContext != null && Navigator.canPop(overlayContext!)) {
        Navigator.pop(overlayContext!);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      setState(() => _funding = false);
    }
  }

  Future<void> _verifyPayment(String reference) async {
    try {
      final response = await ApiService.get('/wallet/verify?reference=$reference');
      
      if (response['success'] == true) {
        setState(() {
          _balance = response['balance']?.toDouble() ?? _balance;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${CurrencyFormatter.format(response['amount']?.toDouble() ?? 0.0)} added successfully'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Payment verification failed'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAmountDialog() {
    final controller = TextEditingController();
    final amounts = [500.0, 1000.0, 2000.0, 5000.0];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Add Funds',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Select amount or enter custom amount',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: amounts.map((amount) {
                  return ActionChip(
                    label: Text(CurrencyFormatter.formatInt(amount.toInt())),
                    onPressed: () {
                      controller.text = amount.toString();
                    },
                    backgroundColor: AppColors.primaryLight,
                    labelStyle: GoogleFonts.inter(color: Colors.white),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Custom Amount',
                  prefixText: '₦',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
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
            onPressed: _funding ? null : () {
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                Navigator.pop(context);
                _addFunds(amount);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid amount'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: _funding
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text('Pay'),
          ),
        ],
      ),
    );
  }

  void _showHistoryDialog() {
    setState(() {
      _filterStatus = 'ALL';
      _filterStartDate = null;
      _filterEndDate = null;
    });
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Transaction History',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                // Status Filter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterStatus,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('All Status')),
                        DropdownMenuItem(value: 'SUCCESS', child: Text('Success')),
                        DropdownMenuItem(value: 'FAILED', child: Text('Failed')),
                        DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          _filterStatus = value ?? 'ALL';
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Date Filter
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _filterStartDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setDialogState(() {
                              _filterStartDate = date;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _filterStartDate != null
                                      ? '${_filterStartDate!.day}/${_filterStartDate!.month}/${_filterStartDate!.year}'
                                      : 'Start Date',
                                  style: GoogleFonts.inter(fontSize: 12),
                                ),
                              ),
                              if (_filterStartDate != null)
                                InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      _filterStartDate = null;
                                    });
                                  },
                                  child: const Icon(Icons.clear, size: 16),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _filterEndDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setDialogState(() {
                              _filterEndDate = date;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _filterEndDate != null
                                      ? '${_filterEndDate!.day}/${_filterEndDate!.month}/${_filterEndDate!.year}'
                                      : 'End Date',
                                  style: GoogleFonts.inter(fontSize: 12),
                                ),
                              ),
                              if (_filterEndDate != null)
                                InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      _filterEndDate = null;
                                    });
                                  },
                                  child: const Icon(Icons.clear, size: 16),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Transaction List
                Expanded(
                  child: _loadingTransactions
                      ? const Center(child: CircularProgressIndicator())
                      : _getFilteredTransactions().isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.receipt_long_rounded,
                                    color: AppColors.textSecondary,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No transactions found',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _getFilteredTransactions().length,
                              separatorBuilder: (context, index) => const Divider(),
                              itemBuilder: (context, index) {
                                final transaction = _getFilteredTransactions()[index];
                                final isCredit = transaction['type'] == 'CREDIT';
                                final status = transaction['status'] ?? 'PENDING';
                                final statusColor = status == 'SUCCESS' 
                                    ? AppColors.success 
                                    : status == 'FAILED' 
                                        ? AppColors.error 
                                        : AppColors.warning;
                                
                                return ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isCredit 
                                          ? AppColors.success.withOpacity(0.1)
                                          : AppColors.error.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isCredit ? Icons.add_rounded : Icons.remove_rounded,
                                      color: isCredit ? AppColors.success : AppColors.error,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    transaction['description'] ?? 
                                        (isCredit ? 'Funds Added' : 'Payment'),
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatDate(transaction['createdAt']),
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          status,
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Text(
                                    '${isCredit ? '+' : '-'}${CurrencyFormatter.format(transaction['amount'] is String ? double.tryParse(transaction['amount']) ?? 0.0 : (transaction['amount']?.toDouble() ?? 0.0))}',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isCredit ? AppColors.success : AppColors.error,
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setDialogState(() {
                  _filterStatus = 'ALL';
                  _filterStartDate = null;
                  _filterEndDate = null;
                });
              },
              child: const Text('Clear Filters'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _fetchTransactions();
              },
              child: const Text('Refresh'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredTransactions() {
    var filtered = List<Map<String, dynamic>>.from(_transactions);
    
    // Filter by status
    if (_filterStatus != 'ALL') {
      filtered = filtered.where((t) => t['status'] == _filterStatus).toList();
    }
    
    // Filter by date range
    if (_filterStartDate != null) {
      filtered = filtered.where((t) {
        final date = DateTime.tryParse(t['createdAt'] ?? '');
        return date != null && date.isAfter(_filterStartDate!.subtract(const Duration(days: 1)));
      }).toList();
    }
    
    if (_filterEndDate != null) {
      filtered = filtered.where((t) {
        final date = DateTime.tryParse(t['createdAt'] ?? '');
        return date != null && date.isBefore(_filterEndDate!.add(const Duration(days: 1)));
      }).toList();
    }
    
    return filtered;
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchWalletBalance,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wallet',
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.textDark : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Manage your funds',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Balance Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Available Balance',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _loading
                          ? const SizedBox(
                              height: 40,
                              width: 40,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            )
                          : Text(
                              CurrencyFormatter.format(_balance),
                              style: GoogleFonts.inter(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Quick Actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick Actions',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.textDark : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.add_rounded,
                            label: 'Add Funds',
                            color: AppColors.success,
                            onTap: _showAmountDialog,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.history_rounded,
                            label: 'History',
                            color: AppColors.primary,
                            onTap: _showHistoryDialog,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Recent Transactions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Activity',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).brightness == Brightness.dark ? AppColors.textDark : AppColors.text,
                          ),
                        ),
                        if (_transactions.isNotEmpty)
                          TextButton(
                            onPressed: _fetchTransactions,
                            child: Text(
                              'Refresh',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_loadingTransactions)
                      const Center(child: CircularProgressIndicator())
                    else if (_transactions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark ? AppColors.cardDark : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.borderDark : AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.receipt_long_rounded,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No transactions yet',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._transactions.take(5).map((transaction) {
                        final isCredit = transaction['type'] == 'CREDIT';
                        final status = transaction['status'] ?? 'PENDING';
                        final statusColor = status == 'SUCCESS' 
                            ? AppColors.success 
                            : status == 'FAILED' 
                                ? AppColors.error 
                                : AppColors.warning;
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).brightness == Brightness.dark ? AppColors.cardDark : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.borderDark : AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isCredit 
                                      ? AppColors.success.withOpacity(0.1)
                                      : AppColors.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  isCredit ? Icons.add_rounded : Icons.remove_rounded,
                                  color: isCredit ? AppColors.success : AppColors.error,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      transaction['description'] ?? 
                                          (isCredit ? 'Funds Added' : 'Payment'),
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context).brightness == Brightness.dark ? AppColors.textDark : AppColors.text,
                                      ),
                                    ),
                                    Text(
                                      _formatDate(transaction['createdAt']),
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${isCredit ? '+' : '-'}₦${transaction['amount'] is String ? transaction['amount'] : (transaction['amount']?.toStringAsFixed(2) ?? '0.00')}',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isCredit ? AppColors.success : AppColors.error,
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          status,
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                      if (status == 'PENDING' && isCredit && transaction['reference'] != null)
                                        IconButton(
                                          icon: Icon(Icons.refresh, size: 16, color: AppColors.primary),
                                          onPressed: () => _retryPayment(transaction['reference']),
                                          padding: EdgeInsets.zero,
                                          constraints: BoxConstraints(),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaystackWebView extends StatefulWidget {
  final String url;
  final String reference;

  const PaystackWebView({
    super.key,
    required this.url,
    required this.reference,
  });

  @override
  State<PaystackWebView> createState() => _PaystackWebViewState();
}

class _PaystackWebViewState extends State<PaystackWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onNavigationRequest: (NavigationRequest request) {
            // Check if navigation is to the callback URL (payment complete)
            if (request.url.contains('evcharge.evworld.ng/#/wallet/verify')) {
              // Payment completed, close WebView and return success
              Navigator.pop(context, 'success');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Payment'),
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: () => Navigator.pop(context, 'cancelled'),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: color,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
