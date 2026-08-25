import 'dart:io';
import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../models/video_item.dart';
import '../theme/amoled_theme.dart';
import 'amoled_card.dart';

class VideoTile extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  const VideoTile({
    super.key,
    required this.video,
    required this.onTap,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    // FIX(build-io): build'in ilk satırı her karede senkron bir File.existsSync
    // çağrısıydı. Arama kutusuna sekiz harf yazmak, ekrandaki her kart için ayrı
    // bir disk stat'i demekti; yavaş depolamalı cihazda yazarken ve hızlı
    // kaydırırken görünür takılma oluşuyordu. Dosyanın okunup okunamadığını
    // zaten Image.file'ın errorBuilder'ı bildiriyor, o yüzden build artık diske
    // hiç dokunmuyor.
    final hasThumbPath =
        video.thumbnailPath != null && video.thumbnailPath!.isNotEmpty;

    // Küçük resmin kod çözme genişliği (cihaz pikseli). Ölçülemediği bir anda
    // (genişlik sıfır) uydurma bir sayı koymuyoruz: cacheWidth sıfır olursa
    // Image.file assert atar, o yüzden sınır tamamen kalkar ve kaynak kendi
    // boyutuyla çözülür.
    final decodeWidthPx = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round();
    final thumbCacheWidth = decodeWidthPx > 0 ? decodeWidthPx : null;

    final hasDuration =
        video.durationSeconds != null && video.durationSeconds! > 0;
    final hasUploader =
        video.uploader != null && video.uploader!.isNotEmpty;

    final card = AmoledCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: EdgeInsets.zero,
      borderColor: isSelected
          ? const Color(0xFF00E676)
          : (isSelectionMode ? const Color(0xFF333333) : null),
      backgroundColor: isSelected ? const Color(0xFF0D2314) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 16:9 Thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // FIX(fallback): Yer tutucu artık her zaman en altta duruyor.
                // Eskiden "dosya yok" dalı 0xFF141414, errorBuilder dalı ise
                // AmoledTheme.cardDark çiziyordu; aynı eksik küçük resim, hangi
                // yoldan gelindiğine göre iki farklı arka planla görünüyordu.
                // Altta durması ayrıca kod çözme tamamlanana kadar boş kare
                // görünmesini de engelliyor.
                const _ThumbnailPlaceholder(),
                if (hasThumbPath)
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(14)),
                    child: Image.file(
                      File(video.thumbnailPath!),
                      fit: BoxFit.cover,
                      // FIX(bellek): yt-dlp'nin bıraktığı küçük resim tipik
                      // olarak 1280x720 ve çözülmüş kare tamponu yaklaşık
                      // 3.5 MB. Otuz videoluk bir kütüphanede kaydırırken
                      // ImageCache'in 100 MB'lık varsayılan sınırı doluyor,
                      // düşük bellekli cihazda kare atlamalarına yol açıyordu.
                      // Kart en fazla ekran genişliği kadar yer kapladığı için
                      // kod çözmeyi o boyutla sınırlıyoruz (kaynak daha küçükse
                      // Flutter büyütme yapmaz, hedefi kaynağa kırpar).
                      cacheWidth: thumbCacheWidth,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),

                // Play Butonu (seçim modunda değilse)
                if (!isSelectionMode)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: AmoledTheme.pureWhite,
                        size: 24,
                      ),
                    ),
                  ),

                // Seçim onay kutusu (sağ üst)
                if (isSelectionMode)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF00E676)
                            : Colors.black.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF00E676)
                              : Colors.white70,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        isSelected
                            ? Icons.check_rounded
                            : Icons.circle_outlined,
                        size: 18,
                        color:
                            isSelected ? Colors.black : Colors.transparent,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 2. Bilgi Alanı
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık
                Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AmoledTheme.pureWhite,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Kanal (Standart hale getirildi, her zaman çizilir)
                Row(
                  children: [
                    const Icon(
                      Icons.account_circle_outlined,
                      size: 12,
                      color: AmoledTheme.subText,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        hasUploader ? video.uploader! : 'Bilinmeyen Kanal',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AmoledTheme.subText,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),

                // Alt bilgi satırı: süre • boyut • tarih
                Row(
                  children: [
                    // Süre (Standart hale getirildi, her zaman çizilir)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: Colors.white12, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 10, color: AmoledTheme.subText),
                          const SizedBox(width: 3),
                          Text(
                            hasDuration ? video.formattedDuration : '--:--',
                            style: const TextStyle(
                              color: AmoledTheme.pureWhite,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Boyut
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF004D25)
                            : const Color(0xFF162518),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: const Color(0xFF00E676)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        video.formattedSize,
                        style: const TextStyle(
                          color: Color(0xFF00E676),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),
                    const Text('•',
                        style: TextStyle(color: AmoledTheme.borderDark, fontSize: 10)),
                    const SizedBox(width: 6),

                    // Tarih
                    Expanded(
                      child: Text(
                        video.formattedDisplayDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // YouTube Linki (Standart)
                const SizedBox(height: 6),
                // FIX(secim): Seçim modunda bağlantı satırına denk gelen dokunuş
                // videoyu seçmek yerine uygulamayı arka plana atıp YouTube'u
                // açıyordu. Kullanıcı on iki video seçerken akışı kesiliyor, geri
                // döndüğünde o video seçilmemiş oluyordu; aynı noktada uzun basmak
                // ise dıştaki karta düştüğü için çalışıyordu, yani davranış
                // tutarsızdı. onTap seçim modunda null olunca dokunuş dıştaki
                // AmoledCard'a geçer ve seçimi değiştirir.
                InkWell(
                  onTap: (!isSelectionMode &&
                          video.sourceUrl != null &&
                          video.sourceUrl!.isNotEmpty)
                      ? () async {
                          final url = Uri.parse(video.sourceUrl!);
                          try {
                            bool launched = false;
                            if (video.youtubeId != null && video.youtubeId!.isNotEmpty) {
                              final ytAppUri = Uri.parse('vnd.youtube:${video.youtubeId}');
                              launched = await launchUrl(ytAppUri, mode: LaunchMode.externalApplication);
                            }
                            if (!launched) {
                              launched = await launchUrl(url, mode: LaunchMode.externalNonBrowserApplication);
                            }
                            if (!launched) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            }
                          } catch (_) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        }
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        (video.sourceUrl != null && video.sourceUrl!.isNotEmpty)
                            ? Icons.link_rounded
                            : Icons.link_off_rounded,
                        size: 12,
                        color: (video.sourceUrl != null && video.sourceUrl!.isNotEmpty)
                            ? AmoledTheme.brandRed
                            : AmoledTheme.subText,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          (video.sourceUrl != null && video.sourceUrl!.isNotEmpty)
                              ? video.sourceUrl!
                              : 'Bağlantı Yok',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: (video.sourceUrl != null && video.sourceUrl!.isNotEmpty)
                                ? AmoledTheme.brandRed
                                : AmoledTheme.subText,
                            fontSize: 10.5,
                            decoration: (video.sourceUrl != null && video.sourceUrl!.isNotEmpty)
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            decorationColor: AmoledTheme.brandRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // FIX(erisilebilirlik): Seçim durumu ekranda yalnızca yeşil çerçeve ve onay
    // simgesiyle anlatılıyordu, erişilebilirlik ağacına ise hiç yazılmıyordu
    // (projede tek bir Semantics düğümü yoktu). TalkBack açık bir kullanıcı on
    // iki videoyu işaretlerken kartlar arasında gezinip hangisinin seçili
    // olduğunu duyamıyor, yanlış videoyu silme riskiyle ilerliyordu. Kart seçim
    // modunda tek bir düğüm olarak birleştirilip seçili bayrağını taşıyor.
    // Birleştirme yalnızca seçim modunda yapılıyor: normal modda bağlantı
    // satırının kendi dokunma eylemi var, onu tek düğüme eritmek ekran okuyucu
    // kullanıcısından YouTube bağlantısını gizlerdi.
    if (!isSelectionMode) return card;
    return MergeSemantics(
      child: Semantics(
        selected: isSelected,
        child: card,
      ),
    );
  }
}

/// Küçük resmin çizilemediği her durumda (yol yok, dosya silinmiş, kod çözme
/// hatası) kullanılan tek yer tutucu. Tek kaynak olması, kartın hangi yoldan
/// gelinirse gelinsin aynı görünmesini garanti eder.
class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: const Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: AmoledTheme.subText,
          size: 48,
        ),
      ),
    );
  }
}
