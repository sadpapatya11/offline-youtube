import 'package:flutter/material.dart';
import '../../models/playlist_entry.dart';
import '../theme/amoled_theme.dart';

/// Oynatma listesi / kanal bağlantısı verildiğinde açılan seçim ekranı.
///
/// Bu ekranın varlık sebebi: bağlantı verilir verilmez listenin tamamının
/// sessizce kuyruğa dökülmesini engellemek. Kullanıcı ne indireceğine burada
/// karar verir; seçilenler kuyruğa sırayla, tek tek iner.
///
/// `Navigator.pop` ile seçilen girdiler döndürülür; iptal edilirse `null`.
class PlaylistSelectionScreen extends StatefulWidget {
  final PlaylistFetchResult result;

  const PlaylistSelectionScreen({super.key, required this.result});

  @override
  State<PlaylistSelectionScreen> createState() =>
      _PlaylistSelectionScreenState();
}

class _PlaylistSelectionScreenState extends State<PlaylistSelectionScreen> {
  /// "İlk N" hızlı seçim düğmesinin kapsamı.
  static const int _quickPickCount = 10;

  static const Color _noticeBackground = Color(0xFF2A1F00);
  static const Color _noticeBorder = Color(0xFFFFB300);
  static const Color _noticeText = Color(0xFFFFD54F);
  static const Color _accentGreen = Color(0xFF00E676);

  /// Seçili girdilerin listedeki konumları.
  final Set<int> _selected = <int>{};

  List<PlaylistEntry> get _entries => widget.result.entries;

  @override
  void initState() {
    super.initState();
    // Varsayılan: zaten kuyrukta/kütüphanede OLMAYAN videolar seçili gelir.
    // Böylece tek dokunuşla "yeni olanları indir" mümkün, ama kullanıcı
    // listeyi görmeden hiçbir şey kuyruğa girmiyor.
    for (var i = 0; i < _entries.length; i++) {
      if (!_entries[i].alreadyPresent) _selected.add(i);
    }
  }

  void _toggle(int index) {
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  void _selectAll() => setState(
      () => _selected.addAll(List.generate(_entries.length, (i) => i)));

  void _clearAll() => setState(_selected.clear);

  void _selectFirst(int count) {
    setState(() {
      _selected
        ..clear()
        ..addAll(List.generate(count.clamp(0, _entries.length), (i) => i));
    });
  }

  /// Seçili videoların bilinen sürelerinin toplamı. Süresi bilinmeyenler
  /// toplama katılmaz; sayıları ayrıca gösterilir.
  int get _selectedKnownDuration => _selected
      .map((i) => _entries[i])
      .where((e) => e.hasDuration)
      .fold(0, (sum, e) => sum + e.durationSeconds);

  int get _selectedUnknownCount =>
      _selected.map((i) => _entries[i]).where((e) => !e.hasDuration).length;

  String get _summaryText {
    if (_selected.isEmpty) return 'Hiç video seçilmedi';
    final parts = <String>['${_selected.length} video'];
    if (_selectedKnownDuration > 0) {
      parts.add(PlaylistEntry.formatDuration(_selectedKnownDuration));
    }
    if (_selectedUnknownCount > 0) {
      parts.add('$_selectedUnknownCount tanesinin süresi bilinmiyor');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _selected.length == _entries.length;

    return Scaffold(
      appBar: AppBar(title: const Text('İNDİRİLECEKLERİ SEÇ')),
      body: Column(
        children: [
          if (widget.result.isTruncated) _buildNotice(_truncationText()),
          if (widget.result.alreadyPresentCount > 0)
            _buildNotice(
              '${widget.result.alreadyPresentCount} video zaten kuyrukta veya '
              'kütüphanenizde; işaretlenmemiş olarak listelendi.',
            ),
          _buildToolbar(allSelected),
          const Divider(height: 1, color: AmoledTheme.accentGray),
          Expanded(
            child: ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) => _buildRow(index),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  String _truncationText() =>
      'Bu bağlantı ${widget.result.totalCount} video içeriyor. Tek seferde en '
      'fazla ${_entries.length} tanesi listelenebildi; kalan '
      '${widget.result.truncatedCount} video burada görünmüyor.';

  Widget _buildNotice(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _noticeBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _noticeBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _noticeBorder, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: _noticeText, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(bool allSelected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _summaryText,
              style: TextStyle(
                color: _selected.isEmpty
                    ? AmoledTheme.subText
                    : AmoledTheme.pureWhite,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _buildActionChip(
            label: allSelected ? 'Temizle' : 'Tümü',
            onTap: allSelected ? _clearAll : _selectAll,
          ),
          if (_entries.length > _quickPickCount) ...[
            const SizedBox(width: 6),
            _buildActionChip(
              label: 'İlk $_quickPickCount',
              onTap: () => _selectFirst(_quickPickCount),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionChip(
      {required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AmoledTheme.cardDark,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AmoledTheme.accentGray),
        ),
        child: Text(
          label,
          style: const TextStyle(
              color: AmoledTheme.pureWhite,
              fontSize: 11,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildRow(int index) {
    final entry = _entries[index];
    final selected = _selected.contains(index);

    return InkWell(
      onTap: () => _toggle(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: selected ? _accentGreen : AmoledTheme.subText,
              size: 22,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 26,
              child: Text(
                '${index + 1}.',
                style:
                    const TextStyle(color: AmoledTheme.subText, fontSize: 11),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? AmoledTheme.pureWhite
                          : AmoledTheme.pureWhite.withValues(alpha: 0.75),
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _metaLine(entry),
                        style: const TextStyle(
                            color: AmoledTheme.subText, fontSize: 11),
                      ),
                      if (entry.alreadyPresent) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle_outline,
                            size: 12, color: _accentGreen),
                        const SizedBox(width: 3),
                        const Text(
                          'zaten var',
                          style:
                              TextStyle(color: _accentGreen, fontSize: 10),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Alt bilgi satırı. Dosya boyutu BİLEREK gösterilmiyor: `--flat-playlist`
  /// boyut döndürmüyor ve süreden tahmin üretmek kullanıcıyı yanıltıyor.
  String _metaLine(PlaylistEntry entry) {
    final parts = <String>[
      entry.hasDuration ? entry.formattedDuration : 'süre bilinmiyor',
    ];
    final uploader = entry.uploader;
    if (uploader != null && uploader.isNotEmpty) parts.add(uploader);
    return parts.join(' · ');
  }

  Widget _buildBottomBar() {
    final hasSelection = _selected.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: const BoxDecoration(
        color: AmoledTheme.cardDark,
        border: Border(top: BorderSide(color: AmoledTheme.accentGray)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop<List<PlaylistEntry>>(context),
              child: const Text('İptal',
                  style: TextStyle(color: AmoledTheme.subText)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(hasSelection
                  ? '${_selected.length} videoyu indir'
                  : 'Video seçin'),
              onPressed: hasSelection ? _confirm : null,
            ),
          ),
        ],
      ),
    );
  }

  void _confirm() {
    // Seçim sırası değil, LİSTE sırası korunur: kuyruk oynatma listesi
    // sırasında ilerlesin (ders serisi/podcast için doğru olan budur).
    final ordered = _selected.toList()..sort();
    Navigator.pop<List<PlaylistEntry>>(
      context,
      ordered.map((i) => _entries[i]).toList(),
    );
  }
}
