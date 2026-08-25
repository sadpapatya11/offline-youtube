import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/trashed_video_item.dart';
import '../../models/video_item.dart';
import '../../providers/library_provider.dart';
import '../theme/amoled_theme.dart';
import '../widgets/amoled_card.dart';
import '../widgets/amoled_fast_scroller.dart';
import '../widgets/video_tile.dart';
import 'player_screen.dart';

/// FIX(arama): Dart'in toLowerCase() metodu Türkçe'yi bilmez. "IŞIK Belgeseli"
/// başlığı 'işik' olur, kullanıcının doğal olarak yazdığı "ışık" sorgusu ise
/// 'ışık' kalır ve hiç eşleşmez: ekranda "Aramanızla eşleşen video bulunamadı"
/// çıkar, kullanıcı videonun silindiğini sanır. Aynı tuzak "Kılıç" başlığını
/// "KILIÇ" diye ararken de vurur. Nokta farkı (İ I ı i) tek harfe indirgenir,
/// ayrıca aksanlı harfler sadeleştirilir ki "ISIK" da "IŞIK"ı bulsun.
/// Katlama küçültmeden ÖNCE yapılır: 'İ'.toLowerCase() Dart'ta iki kod birimli
/// 'i̇' (i + birleşen nokta) üretir ve karşılaştırmayı sessizce bozardı.
const Map<String, String> _trFoldTable = {
  'İ': 'i', 'I': 'i', 'ı': 'i',
  'Ş': 's', 'ş': 's',
  'Ç': 'c', 'ç': 'c',
  'Ğ': 'g', 'ğ': 'g',
  'Ö': 'o', 'ö': 'o',
  'Ü': 'u', 'ü': 'u',
};

/// Türkçe duyarlı arama katlaması. Hem başlık hem sorgu bu tek fonksiyondan
/// geçer; iki taraf farklı normalleştirilirse eşleşme yine sessizce kaybolur.
String trFold(String input) {
  final buffer = StringBuffer();
  for (final ch in input.split('')) {
    buffer.write(_trFoldTable[ch] ?? ch);
  }
  return buffer.toString().toLowerCase();
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => DownloadsScreenState();
}

class DownloadsScreenState extends State<DownloadsScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSelectionMode = false;
  final Set<String> _selectedVideoIds = {};
  final Map<int, GlobalKey> _itemKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _handleRefresh(BuildContext context) async {
    final library = context.read<LibraryProvider>();
    await library.refresh();
  }

  void _enterSelectionMode([String? initialSelectedId]) {
    setState(() {
      _isSelectionMode = true;
      if (initialSelectedId != null) {
        _selectedVideoIds.add(initialSelectedId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedVideoIds.clear();
    });
  }

  void _toggleSelection(String videoId) {
    setState(() {
      if (_selectedVideoIds.contains(videoId)) {
        _selectedVideoIds.remove(videoId);
      } else {
        _selectedVideoIds.add(videoId);
      }
    });
  }

  /// Bir başlığın arama sorgusuyla eşleşip eşleşmediği. Tek eşleşme kaynağı:
  /// hem listeyi süzen build hem de seçim temizleyen onChanged buradan geçer.
  static bool matchesQuery(String title, String query) {
    if (query.isEmpty) return true;
    return trFold(title).contains(trFold(query));
  }

  /// FIX(secim): Eskiden "hepsi seçili mi" sorusu `secili.length == gorunen.length`
  /// ile ölçülüyordu. Kullanıcı A videosunu seçip aramayla listeyi tek bir B
  /// videosuna daraltınca 1 == 1 olduğu için üst bar "Seçimi Kaldır" gösteriyor,
  /// basınca B seçilmiyor A'nın seçimi kalkıyordu. Artık üyelikle ölçülür.
  static bool areAllSelected(Set<String> selected, Iterable<String> visibleIds) {
    final visible = visibleIds.toList();
    if (visible.isEmpty) return false;
    return visible.every(selected.contains);
  }

  void _toggleSelectAll(List<VideoItem> videos) {
    final visibleIds = videos.map((v) => v.id).toList();
    setState(() {
      if (areAllSelected(_selectedVideoIds, visibleIds)) {
        // Seçimi kaldırırken YALNIZ filtredekiler düşer; ekranda görünmeyen
        // ama seçili kalmış videoların seçimi burada sessizce silinmemeli.
        _selectedVideoIds.removeAll(visibleIds);
      } else {
        _selectedVideoIds.addAll(visibleIds);
      }
    });
  }

  void _handleDragSelect(Offset globalPosition, List<VideoItem> videos) {
    if (!_isSelectionMode) return;
    for (int i = 0; i < videos.length; i++) {
      final key = _itemKeys[i];
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          final pos = box.localToGlobal(Offset.zero);
          final rect = Rect.fromLTWH(
              pos.dx, pos.dy, box.size.width, box.size.height);
          if (rect.contains(globalPosition)) {
            final id = videos[i].id;
            if (!_selectedVideoIds.contains(id)) {
              setState(() {
                _selectedVideoIds.add(id);
              });
            }
          }
        }
      }
    }
  }

  Future<void> _deleteSelectedVideos(
      BuildContext context, LibraryProvider library) async {
    if (_selectedVideoIds.isEmpty) return;

    final idsToDelete = _selectedVideoIds.toList();
    _exitSelectionMode();

    final messenger = ScaffoldMessenger.of(context);
    final deletedCount = await library.bulkMoveToTrash(idsToDelete);
    final failedCount = idsToDelete.length - deletedCount;

    // FIX(sessiz-basarisizlik): Eskiden yalnız deletedCount > 0 dalı mesaj
    // gösteriyordu. İndirme klasörü SD karttayken kart çıkarılmışsa veya izin
    // düşmüşse moveToTrash hepsi için false döner: seçim modu kapanır, liste
    // aynen kalır, hiçbir uyarı çıkmazdı. Kullanıcı düğme bozuk sanıp tekrar
    // tekrar denerdi. Artık tam ve kısmi başarısızlık ayrı ayrı bildirilir.
    if (deletedCount == 0) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
              '⚠️ ${idsToDelete.length} videonun hiçbiri Geri Dönüşüm Kutusu\'na taşınamadı. Depolama erişimini kontrol edip tekrar deneyin.'),
          backgroundColor: AmoledTheme.brandRed,
          duration: const Duration(seconds: 5),
        ));
      return;
    }

    final summary = failedCount > 0
        ? '🗑️ $deletedCount video Geri Dönüşüm Kutusu\'na taşındı, $failedCount video taşınamadı.'
        : '🗑️ $deletedCount video Geri Dönüşüm Kutusu\'na taşındı (24 saat sonra silinir).';

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(summary),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Geri Al',
          textColor: const Color(0xFF00E676),
          onPressed: () async {
            // FIX(geri-al-yarisi): Eskiden N adet restoreVideo await edilmeden
            // aynı anda başlıyordu. Her biri tam kütüphane taraması yapıp
            // trash_index.json'u okuyup geri yazdığı için son yazan kazanıyor,
            // diğerlerinin çıkardığı kayıtlar çöp indeksine geri sızıyordu:
            // dosya indirme klasörüne dönmüş olmasına rağmen çöp rozeti hâlâ
            // eski sayıyı gösteriyordu. Sıraya sokup await ediyoruz.
            int restoreFailed = 0;
            for (final id in idsToDelete) {
              final match = library.trashedVideos
                  .where((t) => t.video.id == id)
                  .firstOrNull;
              if (match == null) continue;
              final ok = await library.restoreVideo(match);
              if (!ok) restoreFailed++;
            }
            if (restoreFailed > 0) {
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(
                      '⚠️ $restoreFailed video geri yüklenemedi, Geri Dönüşüm Kutusu\'nda kaldı.'),
                  backgroundColor: AmoledTheme.brandRed,
                  duration: const Duration(seconds: 4),
                ));
            }
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final allVideos = library.videos;

    final filteredVideos = _searchQuery.isEmpty
        ? allVideos
        : allVideos.where((v) => matchesQuery(v.title, _searchQuery)).toList();

    final bool isAllSelected =
        areAllSelected(_selectedVideoIds, filteredVideos.map((v) => v.id));

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: _isSelectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AmoledTheme.pureWhite),
                  tooltip: 'Vazgeç',
                  onPressed: _exitSelectionMode,
                ),
                title: Text(
                  '${_selectedVideoIds.length} Seçildi',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      isAllSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                      color: AmoledTheme.pureWhite,
                    ),
                    tooltip:
                        isAllSelected ? 'Seçimi Kaldır' : 'Tümünü Seç',
                    onPressed: () => _toggleSelectAll(filteredVideos),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded,
                        color: AmoledTheme.brandRed),
                    tooltip: 'Seçilenleri Sil',
                    onPressed: _selectedVideoIds.isNotEmpty
                        ? () => _deleteSelectedVideos(context, library)
                        : null,
                  ),
                ],
              )
            : AppBar(
                title: const Text('İNDİRİLENLER'),
                actions: [
                  IconButton(
                    icon: Icon(
                      library.sortNewestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      color: AmoledTheme.pureWhite,
                    ),
                    tooltip: library.sortNewestFirst ? 'En Yeni (Değiştir)' : 'En Eski (Değiştir)',
                    onPressed: () => library.toggleSortOrder(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.checklist_rounded,
                        color: AmoledTheme.pureWhite),
                    tooltip: 'Çoklu Seç',
                    onPressed: filteredVideos.isNotEmpty
                        ? () => _enterSelectionMode()
                        : null,
                  ),
                  IconButton(
                    icon: Badge(
                      isLabelVisible: library.trashCount > 0,
                      label: Text(
                        '${library.trashCount}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: const Color(0xFFFFCC00),
                      textColor: Colors.black,
                      child: const Icon(Icons.restore_from_trash_rounded,
                          color: AmoledTheme.pureWhite),
                    ),
                    tooltip: 'Geri Dönüşüm Kutusu',
                    onPressed: () => _showTrashModal(context, library),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: AmoledTheme.pureWhite),
                    onPressed: () => library.refresh(),
                    tooltip: 'Yenile',
                  ),
                ],
              ),
        bottomNavigationBar: _isSelectionMode && _selectedVideoIds.isNotEmpty
            ? SafeArea(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: AmoledTheme.cardDark,
                    border: Border(
                      top: BorderSide(
                          color: AmoledTheme.borderDark, width: 1),
                    ),
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AmoledTheme.brandRed,
                      foregroundColor: AmoledTheme.pureWhite,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.delete_sweep_rounded),
                    label: Text(
                      'Seçilenleri Sil (${_selectedVideoIds.length})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () =>
                        _deleteSelectedVideos(context, library),
                  ),
                ),
              )
            : null,
        body: Column(
          children: [
            // Arama & Özet Başlığı
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: AmoledTheme.pureWhite),
                    decoration: InputDecoration(
                      hintText: 'İndirilen videolarda ara...',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AmoledTheme.subText),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: AmoledTheme.subText),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) {
                      final query = val.trim();
                      // FIX(secim): Arama daraldığında ekrandan çıkan videoların
                      // seçimi de düşer. Aksi hâlde kullanıcı yalnız B'yi
                      // seçtiğini sanırken "Seçilenleri Sil (1)" ekranda hiç
                      // görünmeyen A videosunu çöpe atıyordu.
                      final stillVisible = context
                          .read<LibraryProvider>()
                          .videos
                          .where((v) => matchesQuery(v.title, query))
                          .map((v) => v.id)
                          .toSet();
                      setState(() {
                        _searchQuery = query;
                        _selectedVideoIds.retainAll(stillVisible);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${allVideos.length} video',
                            style: const TextStyle(
                              color: AmoledTheme.pureWhite,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (library.totalDurationSeconds > 0) ...[
                            const Text(
                              '  •  ',
                              style: TextStyle(
                                color: AmoledTheme.subText,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              library.formattedTotalDuration,
                              style: const TextStyle(
                                color: AmoledTheme.pureWhite,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        library.formattedTotalUsed,
                        style: const TextStyle(
                          color: AmoledTheme.pureWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: AmoledTheme.borderDark, height: 1),

            // Video Listesi
            Expanded(
              child: RefreshIndicator(
                color: AmoledTheme.pureWhite,
                backgroundColor: AmoledTheme.cardDark,
                onRefresh: () => _handleRefresh(context),
                child: (library.isLoading && library.videos.isEmpty)
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AmoledTheme.pureWhite),
                        ),
                      )
                    : filteredVideos.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) =>
                                SingleChildScrollView(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.video_library_outlined,
                                        size: 64,
                                        color: Color(0xFF444444),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _searchQuery.isEmpty
                                            ? 'Henüz indirilmiş video yok\nYenilemek için aşağı çekin'
                                            : 'Aramanızla eşleşen video bulunamadı',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: AmoledTheme.subText,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : AmoledFastScroller(
                              controller: _scrollController,
                              child: GestureDetector(
                                onPanStart: (details) {
                                  if (_isSelectionMode) {
                                    _handleDragSelect(
                                        details.globalPosition, filteredVideos);
                                  }
                                },
                                onPanUpdate: (details) {
                                  if (_isSelectionMode) {
                                    _handleDragSelect(
                                        details.globalPosition, filteredVideos);
                                  }
                                },
                                child: ListView.separated(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  controller: _scrollController,
                                  padding: const EdgeInsets.all(16),
                                  itemCount: filteredVideos.length,
                                  separatorBuilder: (context, index) =>
                                      const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final video = filteredVideos[index];
                                  final isSelected =
                                      _selectedVideoIds.contains(video.id);

                                  if (!_itemKeys.containsKey(index)) {
                                    _itemKeys[index] = GlobalKey();
                                  }

                                  final tileWidget = Container(
                                    key: _itemKeys[index],
                                    child: VideoTile(
                                      video: video,
                                      isSelectionMode: _isSelectionMode,
                                      isSelected: isSelected,
                                      onLongPress: () {
                                        if (!_isSelectionMode) {
                                          _enterSelectionMode(video.id);
                                        } else {
                                          _toggleSelection(video.id);
                                        }
                                      },
                                      onTap: () {
                                        if (_isSelectionMode) {
                                          _toggleSelection(video.id);
                                        } else {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => PlayerScreen(
                                                video: video,
                                                playlist: filteredVideos,
                                                initialIndex: index,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  );

                                  if (_isSelectionMode) {
                                    return tileWidget;
                                  }

                                  return Dismissible(
                                    key: Key('download_video_${video.id}'),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      decoration: BoxDecoration(
                                        color: AmoledTheme.brandRed,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            'Geri Dönüşüme At',
                                            style: TextStyle(
                                              color: AmoledTheme.pureWhite,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(
                                            Icons.delete_sweep_rounded,
                                            color: AmoledTheme.pureWhite,
                                            size: 26,
                                          ),
                                        ],
                                      ),
                                    ),
                                    // FIX(snackbar): confirmDismiss silme
                                    // SONUCUNU bekler — taşıma başarısızsa
                                    // satır yerinde kalır ve yanlış "taşındı"
                                    // mesajı gösterilmez (önceden her
                                    // kaydırmada başarılı mesaj çıkıyor, "Geri
                                    // Al" hayalet kayıt oluşturabiliyordu).
                                    // FIX(olu-geri-al): Başarı mesajı ve "Geri
                                    // Al" düğmesi eskiden onDismissed'daydı ama
                                    // oraya hiç ulaşılmıyordu: deleteVideo
                                    // notifyListeners çağırınca satır listeden
                                    // düşüyor, Dismissible ağaçtan kalkıyor ve
                                    // Flutter mounted kontrolünde durup
                                    // onDismissed'ı çağırmıyordu. Video çöpe
                                    // gidiyor, kullanıcı ne onay ne geri alma
                                    // görüyordu. Geri bildirim confirmDismiss'e
                                    // taşındı, onDismissed kaldırıldı.
                                    confirmDismiss: (direction) async {
                                      final lib =
                                          context.read<LibraryProvider>();
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      final title = video.title;
                                      final success =
                                          await lib.deleteVideo(video);
                                      if (!success) {
                                        messenger
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(const SnackBar(
                                            content: Text(
                                                '⚠️ Video Geri Dönüşüm Kutusu\'na taşınamadı. Tekrar deneyin.'),
                                            duration: Duration(seconds: 3),
                                          ));
                                        return false;
                                      }
                                      messenger
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(SnackBar(
                                          content: Text(
                                              '🗑️ "$title" Geri Dönüşüm Kutusu\'na taşındı (24 saat sonra silinir).'),
                                          duration:
                                              const Duration(seconds: 4),
                                          action: SnackBarAction(
                                            label: 'Geri Al',
                                            textColor:
                                                const Color(0xFF00E676),
                                            onPressed: () async {
                                              final trashed = lib
                                                  .trashedVideos
                                                  .firstWhere(
                                                (t) =>
                                                    t.video.id == video.id,
                                                orElse: () =>
                                                    TrashedVideoItem(
                                                        video: video,
                                                        deletedAt:
                                                            DateTime.now()),
                                              );
                                              final restored = await lib
                                                  .restoreVideo(trashed);
                                              if (!restored) {
                                                messenger
                                                  ..hideCurrentSnackBar()
                                                  ..showSnackBar(
                                                      const SnackBar(
                                                    content: Text(
                                                        '⚠️ Video geri yüklenemedi, Geri Dönüşüm Kutusu\'nda kaldı.'),
                                                    duration:
                                                        Duration(seconds: 3),
                                                  ));
                                              }
                                            },
                                          ),
                                        ));
                                      return true;
                                    },
                                    child: tileWidget,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTrashModal(BuildContext context, LibraryProvider library) {
    // FIX(gorunmez-mesaj): Bu modal içindeki geri bildirimler eskiden
    // ScaffoldMessenger ile gösteriliyordu. SnackBar ekranın en altında,
    // yüksekliğin %75'ini kaplayan alt sayfanın ARKASINDA çiziliyor ve 2 saniye
    // sonra kayboluyordu: kullanıcı hiçbir onay ya da hata görmüyordu. Mesaj
    // artık sayfanın kendi içinde, listenin üstünde bir bant olarak duruyor.
    final feedback = ValueNotifier<({String text, bool isError})?>(null);
    showModalBottomSheet(
      context: context,
      backgroundColor: AmoledTheme.pureBlack,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return Consumer<LibraryProvider>(
          builder: (ctx, lib, _) {
            final trashedList = lib.trashedVideos;
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sürükleme Tutamacı
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AmoledTheme.accentGray,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Başlık & Bilgi
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_delete_rounded,
                              color: Color(0xFFFFCC00), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Geri Dönüşüm Kutusu',
                            style: TextStyle(
                              color: AmoledTheme.pureWhite,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (trashedList.isNotEmpty)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF5252),
                          ),
                          icon: const Icon(Icons.delete_forever_rounded, size: 18),
                          label: const Text(
                            'Tümünü Temizle',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                backgroundColor: AmoledTheme.cardDark,
                                title: const Text('Tüm Çöpü Temizle',
                                    style: TextStyle(color: Colors.white)),
                                content: const Text(
                                  'Geri Dönüşüm Kutusundaki tüm videolar kalıcı olarak silinecektir. Bu işlem geri alınamaz.',
                                  style: TextStyle(color: AmoledTheme.subText),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, false),
                                    child: const Text('Vazgeç',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, true),
                                    child: const Text('Kalıcı Olarak Sil',
                                        style: TextStyle(color: Color(0xFFFF5252))),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              final cleared = await lib.emptyTrash();
                              feedback.value = cleared
                                  ? null
                                  : (
                                      text:
                                          '⚠️ Geri Dönüşüm Kutusu temizlenemedi. Depolama erişimini kontrol edin.',
                                      isError: true
                                    );
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Silinen videolar 24 saat boyunca burada saklanır, ardından kalıcı olarak silinir.',
                    style: TextStyle(
                      color: AmoledTheme.subText,
                      fontSize: 12,
                    ),
                  ),
                  ValueListenableBuilder<({String text, bool isError})?>(
                    valueListenable: feedback,
                    builder: (_, value, _) {
                      if (value == null) return const SizedBox.shrink();
                      final color = value.isError
                          ? const Color(0xFFFF5252)
                          : const Color(0xFF00E676);
                      return Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          value.text,
                          style: TextStyle(color: color, fontSize: 12),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: AmoledTheme.borderDark, height: 1),
                  const SizedBox(height: 12),

                  // Liste
                  Expanded(
                    child: trashedList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 48,
                                    color: AmoledTheme.subText.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                const Text(
                                  'Geri Dönüşüm Kutusu Boş',
                                  style: TextStyle(
                                    color: AmoledTheme.subText,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: trashedList.length,
                            separatorBuilder: (c, i) => const SizedBox(height: 10),
                            itemBuilder: (c, i) {
                              final item = trashedList[i];
                              final video = item.video;
                              final hasThumb = video.thumbnailPath != null &&
                                  File(video.thumbnailPath!).existsSync();

                              return AmoledCard(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Container(
                                        width: 56,
                                        height: 42,
                                        color: AmoledTheme.cardDark,
                                        // FIX(bozuk-kucukresim): existsSync
                                        // dosyanın VAR olduğunu söyler, OKUNUR
                                        // veya geçerli bir görsel olduğunu
                                        // değil. Yarım yazılmış ya da bozulmuş
                                        // bir jpg'de Image.file kırmızı hata
                                        // kutusu çiziyordu; artık video_tile
                                        // ile aynı yedek ikona düşer.
                                        child: hasThumb
                                            ? Image.file(
                                                File(video.thumbnailPath!),
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (_, _, _) => const Icon(
                                                  Icons.movie_outlined,
                                                  color: AmoledTheme.subText,
                                                  size: 20,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.movie_outlined,
                                                color: AmoledTheme.subText,
                                                size: 20,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            video.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AmoledTheme.pureWhite,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFFFCC00)
                                                      .withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '⏱️ ${item.formattedRemainingTime}',
                                                  style: const TextStyle(
                                                    color: Color(0xFFFFCC00),
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                video.formattedSize,
                                                style: const TextStyle(
                                                  color: AmoledTheme.subText,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.restore_rounded,
                                          color: Color(0xFF00E676), size: 24),
                                      tooltip: 'Geri Yükle',
                                      onPressed: () async {
                                        await lib.restoreVideo(item);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  '✅ "${video.title}" geri yüklendi.'),
                                              duration:
                                                  const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_forever_rounded,
                                          color: Color(0xFFFF5252),
                                          size: 22),
                                      tooltip: 'Kalıcı Sil',
                                      onPressed: () async {
                                        await lib.deletePermanently(item);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
