import 'dart:html' as html;

void initializeOAuthMessageListener(Function(String code) onCodeReceived) {
  print("Listener initialized!");
  html.window.addEventListener('message', (html.Event event) {
    if (event is html.MessageEvent) {
      print("LESSGOOOOOOOOO initialized!");
      final data = event.data;
      if (data is Map && data.containsKey('code')) {
        final String code = data['code'];
        // Call the provided callback function with the received OAuth2 code
        onCodeReceived(code);
      }
    }
  });
}
