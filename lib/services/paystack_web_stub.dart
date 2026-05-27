/// Stub implementation for non-web platforms
typedef PaystackSuccessCallback = void Function(String reference);
typedef PaystackCloseCallback = void Function();

Future<void> openPaystackPopup({
  required String publicKey,
  required String email,
  required int amountInKobo,
  required String reference,
  required String accessCode,
  required PaystackSuccessCallback onSuccess,
  required PaystackCloseCallback onClose,
}) async {
  throw UnsupportedError('Paystack web popup is only supported on web');
}
