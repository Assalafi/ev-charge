import 'package:web/web.dart' as web;

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
  String? authorizationUrl,
}) async {
  // Redirect to Paystack authorization_url which enforces channels: ['card']
  if (authorizationUrl != null && authorizationUrl.isNotEmpty) {
    // Store reference for verification after redirect back
    web.window.localStorage.setItem('paystack_reference', reference);
    web.window.location.href = authorizationUrl;
    return;
  }

  // Fallback: shouldn't reach here if backend provides authorization_url
  throw Exception('Authorization URL is required for web payments');
}
