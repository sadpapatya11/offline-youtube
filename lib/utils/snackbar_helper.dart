import 'package:flutter/material.dart';

class SnackbarHelper {
  static void show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor ?? const Color(0xFF111111),
        duration: duration,
        action: action ??
            SnackBarAction(
              label: 'KAPAT',
              textColor: Colors.white70,
              // FIX(olu-context): Burada ScaffoldMessenger.of(context) çağrılıyordu
              // ama o context, snackbar'ı gösteren ekrana aitti. Alt sayfadan
              // gösterip hemen Navigator.pop yapan akışlarda snackbar ekranda
              // kalmaya devam ediyor, KAPAT'a basıldığında ise ağaçtan kalkmış
              // eleman üzerinden arama yapıldığı için "deactivated widget's
              // ancestor" hatası atılıyordu. SnackBarAction basıldıktan sonra
              // snackbar'ı zaten kendi canlı context'iyle kapatır, bu yüzden
              // burada ek iş yapmak hem gereksiz hem de tehlikeliydi.
              onPressed: () {},
            ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(
          bottom: 16,
          left: 16,
          right: 16,
        ),
        dismissDirection: DismissDirection.horizontal,
      ),
    );
  }

  /// UYARI: adının vaat ettiğinin aksine bu çağrı mesajı ÜSTTE göstermez,
  /// [show] ile birebir aynı davranır (altta, kayan snackbar).
  ///
  /// İsim yanıltıcı olduğu için burada susmuyoruz: konumu değiştirmek gerçek bir
  /// görsel karardır ve mesajlar alt gezinme çubuğunun üstünde çıkarken indirme
  /// kartlarını kapatıyor. Doğru kapanış, bu yardımcıyı silip sekiz çağrıyı
  /// [show]'a çevirmek ya da üst hizalı bir MaterialBanner'a geçmektir; ikisi de
  /// bu dosyanın dışına (home_screen) dokunduğu için burada yapılmadı. Yeni
  /// çağrı ekleyen doğrudan [show] kullanmalı.
  static void showTop(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    show(context, message, backgroundColor: backgroundColor, duration: duration, action: action);
  }
}
