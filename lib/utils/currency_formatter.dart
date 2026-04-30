import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final _nairaFormat = NumberFormat.currency(
    symbol: '₦',
    decimalDigits: 2,
    locale: 'en_NG',
  );

  static String format(double amount) {
    return _nairaFormat.format(amount);
  }

  static String formatInt(int amount) {
    return _nairaFormat.format(amount.toDouble());
  }
}
