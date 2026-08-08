# Offline YouTube 🎬⚡

[English](#english) | [Türkçe](#türkçe)

---

## Türkçe

**Offline YouTube**, YouTube videolarını ve oynatma listelerini en yüksek kalitede, arka planda güvenle indirip internet bağlantısına ihtiyaç duymadan AMOLED siyah temalı yerleşik video oynatıcı ile izlemenizi sağlayan gelişmiş bir mobil uygulamadır.

### ✨ Öne Çıkan Özellikler

- 🖤 **Saf AMOLED Siyah UI:** Pil tasarrufu sağlayan, göz yormayan modern neon ve siyah tasarım.
- ⚡ **Otomatik İndirme Motoru:** Bağlantıyı panoya kopyalayıp uygulamaya girdiğinizde tek dokunuşla indirme başlatma.
- 📋 **Oynatma Listesi & Kanal Desteği:** Tekil videoların yanı sıra tüm oynatma listelerini veya kanal yüklemelerini sıraya ekleme, ters sıralama (en yeniler önce) seçeneği.
- 💬 **Türkçe & Çoklu Altyazı Desteği:** Videolarla birlikte otomatik indirilen `.vtt` / `.srt` altyazıları senkronize gösterim.
- ⏩ **2X Dokun & Hızlandır:** Video oynatıcıda ekrana basılı tutarak anında 2X hızlandırma, çift dokunarak 10s ileri/geri sarma.
- 🗑️ **24 Saat Korumalı Geri Dönüşüm Kutusu:** Yanlışlıkla silinen videolar 24 saat boyunca `.trash` dizininde saklanır, istenildiğinde "Geri Al" ile anında kurtarılabilir.
- 🛡️ **Akıllı Ağ & Depolama Yönetimi:** Sadece Wi-Fi ile indirme kısıtlaması, ayarlanabilir maksimum depolama ve süre kotaları.
- 🔄 **Dahili yt-dlp Güncelleme:** YouTube değişikliklerine karşı tek dokunuşla indirme motorunu doğrudan uygulama içinden güncelleme.

### 🛠️ Teknoloji Mimarisi

- **Frontend:** Flutter & Dart (Provider state management)
- **Native Android:** Kotlin (Platform Channels, Foreground Service, Wakelock)
- **İndirme Motoru:** `yt-dlp` + `aria2c` + `ffmpeg-kit` (Native C/C++ binaries)

---

## English

**Offline YouTube** is a high-performance Android application built with Flutter that allows downloading and watching YouTube videos and playlists completely offline with a premium AMOLED dark video player.

### ✨ Key Features

- 🖤 **Pure AMOLED Dark UI:** Battery-saving, sleek, distraction-free true black interface.
- ⚡ **Instant Auto-Download:** Paste any YouTube link to start high-speed sequential background downloading immediately.
- 📋 **Playlists & Channels:** Full support for single videos, playlists, and channel uploads with reverse chronological ordering.
- 💬 **Embedded & Auto Subtitles:** Automatic Turkish/multi-language subtitle downloading and playback sync.
- ⏩ **2X Hold-to-Speed & Gestures:** Hold anywhere on the screen for 2X playback speed, double-tap to skip ±10 seconds.
- 🗑️ **24-Hour Protected Trash Bin:** Deleted videos stay safely in the recycling bin for 24 hours with instant one-tap undo.
- 🛡️ **Storage & Network Controls:** Configurable storage quotas, maximum video duration filters, and Wi-Fi-only restriction modes.
- 🔄 **Self-Updating Engine:** Seamlessly update the embedded `yt-dlp` binary straight from app settings.

### 🛠️ Technical Stack

- **Flutter / Dart:** Cross-platform reactive UI with Provider
- **Android Native:** Kotlin foreground service, wakelock, and battery optimization handling
- **Core Binaries:** `yt-dlp`, `aria2c`, and `ffmpeg-kit`
