import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../utils/currency_formatter.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ApiService.get('/transactions');
      if (response['success'] == true && response['transactions'] != null) {
        setState(() {
          _transactions = List<Map<String, dynamic>>.from(response['transactions']);
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load transactions';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load transactions';
        _loading = false;
      });
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy • hh:mm a').format(date);
    } catch (_) {
      return dateString;
    }
  }

  String _formatAmount(double amount) {
    return CurrencyFormatter.format(amount);
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'Completed':
        return AppColors.success;
      case 'InProgress':
        return AppColors.primary;
      case 'Stopped':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return SafeArea(
      child: Container(
        color: isDark ? AppColors.backgroundDark : AppColors.background,
        child: RefreshIndicator(
          onRefresh: _fetchTransactions,
          color: AppColors.primary,
          child: Column(
            children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transactions',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppColors.textDark : AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your charging history',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorWidget()
                      : _transactions.isEmpty
                          ? _buildEmptyWidget()
                          : _buildTransactionsList(),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: AppColors.error,
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchTransactions,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 64,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textDark : AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start charging to see your history here',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList() {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final transaction = _transactions[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transaction['chargePointId'] ?? 'Unknown Station',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textDark : AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(transaction['startTime'] ?? ''),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (transaction['amount'] != null)
                          Text(
                            _formatAmount(double.parse(transaction['amount'].toString())),
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppColors.textDark : AppColors.text,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(transaction['status']).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            transaction['status'] ?? 'Unknown',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(transaction['status']),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (transaction['energyDelivered'] != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(transaction['energyDelivered'] / 1000).toStringAsFixed(2)} kWh',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                        ),
                      ),
                      if (transaction['stopTime'] != null) ...[
                        const Spacer(),
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatDate(transaction['stopTime']),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
