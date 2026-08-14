import os
import re

file_path = "lib/ui/screens/home_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Imports
if "import 'playlist_selection_screen.dart';" not in content:
    content = content.replace("import 'package:provider/provider.dart';", "import 'package:provider/provider.dart';\nimport '../../models/playlist_entry.dart';\nimport 'playlist_selection_screen.dart';")

# Replace the part handling `addDownload` result
search_str = """    final error = await downloadProvider.addDownload(
      url: cleanUrl,
      settings: settingsProvider.settings,
      currentStorageUsedBytes: libraryProvider.totalUsedBytes,
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (error != null) {"""

replace_str = """    final error = await downloadProvider.addDownload(
      url: cleanUrl,
      settings: settingsProvider.settings,
      currentStorageUsedBytes: libraryProvider.totalUsedBytes,
    );

    if (error == 'PLAYLIST_URL') {
      final result = await downloadProvider.resolvePlaylist(
        url: cleanUrl,
        settings: settingsProvider.settings,
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        if (result.entries.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Oynatma listesinde indirilebilir video bulunamadı.'),
              backgroundColor: Color(0xFF330000),
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          final selected = await Navigator.push<List<PlaylistEntry>>(
            context,
            MaterialPageRoute(
              builder: (_) => PlaylistSelectionScreen(result: result),
            ),
          );

          if (selected != null && selected.isNotEmpty) {
            final addError = await downloadProvider.addSelectedEntries(
              entries: selected,
              settings: settingsProvider.settings,
              sourcePlaylistUrl: cleanUrl,
              truncatedCount: result.truncatedCount,
              totalCount: result.totalCount,
            );

            if (addError != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(addError),
                  backgroundColor: const Color(0xFF330000),
                  duration: const Duration(seconds: 4),
                ),
              );
            } else {
              _urlController.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('⚡ Seçilen videolar kuyruğa eklendi!'),
                  backgroundColor: const Color(0xFF003311),
                  duration: const Duration(seconds: 2),
                  action: SnackBarAction(
                    label: 'Kuyruğu Gör',
                    textColor: AmoledTheme.pureWhite,
                    onPressed: widget.onNavigateToQueue,
                  ),
                ),
              );
            }
          }
        }
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (error != null) {"""

content = content.replace(search_str, replace_str)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Patch applied to home_screen.dart")
