import 'package:flutter/material.dart';
import '../../models/download_task.dart';
import '../theme/amoled_theme.dart';
import 'amoled_card.dart';

class DownloadTile extends StatelessWidget {
  final DownloadTask task;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;
  final VoidCallback? onPrioritize;

  const DownloadTile({
    super.key,
    required this.task,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onDelete,
    this.onPrioritize,
  });

  /// Küçük resim kutusunun ölçüleri. Kod çözme genişliği de buradan türediği
  /// için kutu büyütülünce çözünürlük kendiliğinden büyür, ikinci bir sayı
  /// güncellemek gerekmez.
  static const double _thumbBoxWidth = 64;
  static const double _thumbBoxHeight = 48;

  /// BoxFit.cover, kutudan geniş oranlı bir kaynağı kutunun yüksekliğine göre
  /// ölçekleyip yanlarından kırpar: 16:9 bir küçük resim için 48 dp yükseklik
  /// yaklaşık 86 dp genişlik ister. Kutu genişliğinin iki katı, YouTube'un
  /// kullandığı tüm oranları (16:9 ve 4:3) yumuşama olmadan karşılar.
  static const double _thumbDecodeWidth = _thumbBoxWidth * 2;

  @override
  Widget build(BuildContext context) {
    final isDownloading = task.status == DownloadStatus.downloading;
    final isPaused = task.status == DownloadStatus.paused;
    final isError = task.status == DownloadStatus.error;
    final hasThumbnail = task.thumbnail != null && task.thumbnail!.isNotEmpty;

    // Küçük resmin kod çözme genişliği (cihaz pikseli). Ölçü sıfır çıkarsa
    // uydurma bir sayı koymuyoruz: cacheWidth sıfır olursa Image assert atar,
    // o yüzden sınır tamamen kalkar ve kaynak kendi boyutuyla çözülür.
    final decodeWidthPx =
        (_thumbDecodeWidth * MediaQuery.devicePixelRatioOf(context)).round();
    final thumbCacheWidth = decodeWidthPx > 0 ? decodeWidthPx : null;

    return AmoledCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail or Icon Container
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: _thumbBoxWidth,
                  height: _thumbBoxHeight,
                  decoration: BoxDecoration(
                    color: _getStatusBgColor(),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _getStatusColor().withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: hasThumbnail
                      ? Image.network(
                          task.thumbnail!,
                          fit: BoxFit.cover,
                          // FIX(bellek): Kaynak tam çözünürlükte çözülüp
                          // ImageCache'e konuyordu. YouTube'un verdiği küçük
                          // resim 1280x720 olduğunda çözülmüş kare tamponu
                          // yaklaşık 3.5 MB tutuyor; elli görevlik bir kuyrukta
                          // 64x48'lik kutular yüzlerce MB'lık önbellek
                          // dolduruyor, düşük bellekli cihazda kare atlamaları
                          // ve sistem tarafından öldürülme riski doğuyordu.
                          // Kardeş dosya video_tile.dart aynı sınırı zaten
                          // uyguluyor, burada da uygulanmazsa kuyruk ekranı
                          // kütüphane ekranından farklı davranmaya devam eder.
                          cacheWidth: thumbCacheWidth,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(
                              _getStatusIcon(),
                              color: _getStatusColor(),
                              size: 24,
                            ),
                          ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: Icon(
                                _getStatusIcon(),
                                color: _getStatusColor(),
                                size: 24,
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Icon(
                            _getStatusIcon(),
                            color: _getStatusColor(),
                            size: 24,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AmoledTheme.pureWhite,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    // FIX(tasma): Bu satır 360 dp'lik yaygın Android genişliğinde
                    // taşıyordu. Küçük resim, boşluklar ve iki aksiyon butonu
                    // düşüldükten sonra bu sütuna yaklaşık 124 dp kalıyor, durum
                    // etiketi artı süre artı boyut çipi ise 260 dp'yi geçiyor. Row
                    // hiçbir çocuğunu küçültemediği için debug'da sarı siyah taşma
                    // bandı çiziliyor, release'de boyut bilgisi aksiyon butonlarının
                    // altına giriyordu. Wrap taşma yerine alt satıra geçer; çip
                    // içindeki metin Flexible olduğu için tek başına da satırdan
                    // geniş kalamaz. Ayıraç nokta kaldırıldı: alt satıra düşen
                    // öksüz bir nokta bozuk arayüz gibi görünüyordu, aralığı artık
                    // Wrap.spacing veriyor.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor().withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getStatusLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _getStatusColor(),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (task.durationSeconds != null &&
                            task.durationSeconds! > 0)
                          Text(
                            task.formattedDuration,
                            style: const TextStyle(
                              color: AmoledTheme.subText,
                              fontSize: 11,
                            ),
                          ),
                        if (task.formattedSizeInfo.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AmoledTheme.accentGray,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.sd_storage_outlined,
                                  size: 11,
                                  color: AmoledTheme.brandRed,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    task.formattedSizeInfo,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AmoledTheme.pureWhite,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _buildActionButtons(),
            ],
          ),
          if (isDownloading || isPaused) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress > 0 ? task.progress / 100.0 : null,
                backgroundColor: AmoledTheme.accentGray,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isPaused ? const Color(0xFFFFCC00) : const Color(0xFF00E676),
                ),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // FIX(tasma): Yüzde artı boyut bloğu, hız ve kalan süre
                // etiketleriyle birlikte "45.2 MB / 120.5 MB" gibi uzun boyut
                // metinlerinde 302 dp'lik kart iç genişliğini aşıyor ve satır
                // taşıyordu. Blok ve içindeki iki metin Flexible olduğu için
                // artık kalan yere sığar: taşma yerine metin kısalır, hız ve
                // kalan süre etiketleri hiç kırpılmaz.
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          '${task.progress.toStringAsFixed(1)}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPaused
                                ? const Color(0xFFFFCC00)
                                : AmoledTheme.pureWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (task.formattedSizeInfo.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '(${task.formattedSizeInfo})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF81D4FA),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (task.speed.isNotEmpty)
                  Text(
                    task.speed,
                    style: const TextStyle(
                      color: Color(0xFF00E676),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (task.etaSeconds > 0)
                  Text(
                    'Kalan: ${task.formattedEta}',
                    style: const TextStyle(
                      color: AmoledTheme.subText,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ],
          if (isError && task.errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2A0000),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF550000)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFFF5555), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      task.errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFF8888),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // FIX(olu-ui): Burada "Mobil veri koruması" metnini arayan sarı bir
          // Wi-Fi paneli vardı ama o dize projede hiçbir yerde üretilmiyordu
          // (grep ile doğrulandı: tek geçtiği yer bu koşulun kendisiydi) ve ağ
          // kısıtı yüzünden bekleyen görev paused değil error durumuna
          // alınıyordu. Yani panel hiçbir zaman çizilmiyordu, buna karşılık
          // kullanıcı geçici ağ beklemesini kırmızı "Hata" olarak görüyordu.
          // Ölü dal kaldırıldı; kalıcı çözüm DownloadTask'a tipli bir bekleme
          // nedeni alanı eklemektir, dize eşleştirmesi değil.
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (task.status == DownloadStatus.downloading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.pause_circle_outline,
                color: Color(0xFFFFCC00), size: 26),
            onPressed: onPause,
            tooltip: 'Duraklat',
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined,
                color: Color(0xFF888888), size: 22),
            onPressed: onCancel,
            tooltip: 'İptal Et',
          ),
        ],
      );
    } else if (task.status == DownloadStatus.paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline,
                color: Color(0xFF00E676), size: 26),
            onPressed: onResume,
            tooltip: 'Devam Et',
          ),
          IconButton(
            icon: const Icon(Icons.cancel_outlined,
                color: Color(0xFF888888), size: 22),
            onPressed: onCancel,
            tooltip: 'İptal Et',
          ),
        ],
      );
    } else if (task.status == DownloadStatus.cancelled || task.status == DownloadStatus.error) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF64B5F6), size: 24),
            onPressed: onResume,
            tooltip: 'Yeniden Başlat',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Color(0xFF888888), size: 22),
            onPressed: onDelete,
            tooltip: 'Listeden Kaldır',
          ),
        ],
      );
    } else {
      final isQueued = task.status == DownloadStatus.queued;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isQueued && onPrioritize != null)
            IconButton(
              icon: const Icon(Icons.vertical_align_top_rounded,
                  color: Color(0xFF00E676), size: 24),
              onPressed: onPrioritize,
              tooltip: 'Önceliklendir (En Üste Taşı)',
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: Color(0xFF888888), size: 22),
            onPressed: onDelete,
            tooltip: 'Listeden Kaldır',
          ),
        ],
      );
    }
  }

  IconData _getStatusIcon() {
    switch (task.status) {
      case DownloadStatus.fetchingMetadata:
        return Icons.hourglass_top_rounded;
      case DownloadStatus.queued:
        return Icons.queue_rounded;
      case DownloadStatus.downloading:
        return Icons.downloading_rounded;
      case DownloadStatus.paused:
        return Icons.pause_rounded;
      case DownloadStatus.completed:
        return Icons.check_circle_rounded;
      case DownloadStatus.error:
        return Icons.error_outline_rounded;
      case DownloadStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  String _getStatusLabel() {
    switch (task.status) {
      case DownloadStatus.fetchingMetadata:
        return 'Bilgiler alınıyor...';
      case DownloadStatus.queued:
        return 'Sırada bekliyor';
      case DownloadStatus.downloading:
        return 'İndiriliyor';
      case DownloadStatus.paused:
        return 'Duraklatıldı';
      case DownloadStatus.completed:
        return 'Tamamlandı';
      case DownloadStatus.error:
        return 'Hata';
      case DownloadStatus.cancelled:
        return 'İptal edildi';
    }
  }

  Color _getStatusColor() {
    switch (task.status) {
      case DownloadStatus.downloading:
        return const Color(0xFF00E676);
      case DownloadStatus.paused:
        return const Color(0xFFFFCC00);
      case DownloadStatus.completed:
        return const Color(0xFF00E676);
      case DownloadStatus.error:
        return const Color(0xFFFF5555);
      case DownloadStatus.queued:
        return const Color(0xFF64B5F6);
      default:
        return AmoledTheme.subText;
    }
  }

  Color _getStatusBgColor() {
    return _getStatusColor().withValues(alpha: 0.1);
  }
}
