import 'package:flutter/material.dart';

class SnackbarHelper {
  static void showTop(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 1),
    SnackBarAction? action,
  }) {
    final mediaQuery = MediaQuery.of(context);
    // Ekranın en üstünde, status bar'ın biraz altında görünmesi için alttan margin hesaplıyoruz
    final bottomMargin = mediaQuery.size.height - mediaQuery.padding.top - 120;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? const Color(0xFF111111),
        duration: duration,
        action: action,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: bottomMargin > 0 ? bottomMargin : 0,
          left: 16,
          right: 16,
        ),
        dismissDirection: DismissDirection.up,
      ),
    );
  }
}
