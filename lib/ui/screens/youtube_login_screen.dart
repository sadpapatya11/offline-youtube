import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:offlineyoutube/ui/theme/amoled_theme.dart';

class YoutubeLoginScreen extends StatefulWidget {
  const YoutubeLoginScreen({super.key});

  @override
  State<YoutubeLoginScreen> createState() => _YoutubeLoginScreenState();
}

class _YoutubeLoginScreenState extends State<YoutubeLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AmoledTheme.pureBlack)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final host = Uri.parse(request.url).host.toLowerCase();
            if (host.contains('youtube.com') || host.contains('accounts.google.com') || host.contains('myaccount.google.com')) {
              return NavigationDecision.navigate;
            }
            debugPrint('Blocked navigation to unauthorized domain: $host');
            return NavigationDecision.prevent;
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://m.youtube.com'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AmoledTheme.pureBlack,
      appBar: AppBar(
        title: const Text('YouTube\'a Giriş Yap'),
        backgroundColor: AmoledTheme.cardDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AmoledTheme.brandRed),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AmoledTheme.brandRed,
        foregroundColor: AmoledTheme.pureWhite,
        onPressed: () {
          // Cookies are automatically shared with Android's CookieManager
          // We just need to pop. The Native side will extract them when downloading.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Oturum bilgileri (çerezler) indirme motoruna aktarıldı!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        },
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('Giriş Yaptım, Kaydet'),
      ),
    );
  }
}
