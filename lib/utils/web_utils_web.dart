import 'package:web/web.dart' as web;

/// Web implementation — forces a hard page reload
class WebUtils {
  static void forceReload() {
    web.window.location.reload();
  }
}
