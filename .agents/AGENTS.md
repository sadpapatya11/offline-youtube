# Kalıcı Kurallar

1. Benimle her zaman Türkçe konuş.
2. Prompt yazdığımda cevap vermeden önce daha iyi sonuç verecek şekilde yeniden yaz, orijinaliyle karşılaştırmadan geliştirilmiş versiyona göre yanıt ver.
3. Her zaman en son APK'yı telefona yükledikten sonra GitHub reposunu da (`git push origin main`) güncelle.
4. Her kod değişikliği/geliştirme tamamlandığında kullanıcı tekrar talep etmeksizin:
   - Yerel Güvenlik ve Regresyon Tarayıcısını koştur (`python scripts/security_and_regression_scan.py`),
   - Eğer güvenlik tarayıcısı hata, güvenlik açığı veya regresyon bulursa otonom olarak hatayı loglardan analiz et, kendi kendine düzelt ve tarayıcıyı başarı alana kadar tekrar başlat (Sıfır Hata Döngüsü),
   - Tarayıcı tamamen başarılı olduğunda Release APK'yı derle (`flutter build apk --release`),
   - Bağlı telefona temiz yükle (`adb install -r -d build/app/outputs/flutter-apk/app-release.apk`),
   - GitHub reposunu (`git push origin main`) otomatik olarak güncelle.
5. Kullanıcıya gereksiz sorular sorma ve onay isteme; tüm yetkiler peşin olarak verilmiştir. İstekleri ve sorunları doğrudan baştan sona analiz et, en iyi çözümü tasarla, uygula, test et, derle, telefona kur ve repoyu senkronize et.
6. En kucuk islemlerde veya duzeltmelerde bile `pubspec.yaml` dosyasindaki surumu minör olarak (ornegin 1.9.0'dan 2.0.0'a) artirirken, ayni zamanda yapi (build) numarasini da ardısık olarak 1 artir (orn: +34, +35). Kullanici hatirlatmadan bunu her zaman otomatik yap.
