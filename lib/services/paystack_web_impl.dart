import 'dart:js' as js;

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
  final popup = js.context['PaystackPop'];
  if (popup == null) {
    throw Exception('PaystackPop not loaded. Ensure Paystack inline.js is in index.html');
  }

  final handler = popup.callMethod('setup', [
    js.JsObject.jsify({
      'key': publicKey,
      'email': email,
      'amount': amountInKobo,
      'ref': reference,
      'onClose': js.allowInterop(() => onClose()),
      'callback': js.allowInterop((dynamic response) {
        final ref = (response as js.JsObject)['reference'].toString();
        onSuccess(ref);
      }),
    }),
  ]);
  handler.callMethod('openIframe', []);
}
