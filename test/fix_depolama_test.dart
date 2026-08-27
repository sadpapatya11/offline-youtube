import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/services/storage_manager.dart';

/// Çöp indeksinde tek bir geçerli kaydın ham JSON karşılığı.
Map<String, dynamic> _gecerliKayit(String id) => {
      'video': {
        'id': id,
        'title': 'Video $id',
        'filePath': '/depo/.movies/.trash/Video $id [$id].mp4',
        'fileSizeBytes': 1024,
        'downloadedAt': DateTime(2026, 8, 1).toIso8601String(),
      },
      'deletedAt': DateTime(2026, 8, 2).toIso8601String(),
    };

void main() {
  group('Göç: kaynak ile hedef aynı klasör olduğunda kütüphane silinmemeli', () {
    test('hedef klasörün kendisi göç listesinden düşürülür', () {
      // getExternalStorageDirectory() null dönerse indirme yolu defaultHiddenPath
      // olarak kalıyor ve göç döngüsü aynı klasörü "eski klasör" sanıyordu. Döngü
      // sonunda klasör siliniyor, yani kullanıcının bütün videoları, .meta.json
      // dosyaları, kapakları ve çöp indeksi yok oluyordu.
      final aday = [
        StorageManager.defaultHiddenPath,
        '/depo/Android/data/uygulama/files/offlineyoutube',
      ];

      final sonuc = StorageManager.migratableOldPaths(
        aday,
        StorageManager.defaultHiddenPath,
      );

      expect(sonuc, isNot(contains(StorageManager.defaultHiddenPath)));
      expect(sonuc, ['/depo/Android/data/uygulama/files/offlineyoutube']);
    });

    test('yazımı farklı ama aynı klasörü gösteren yol da düşürülür', () {
      // Sondaki eğik çizgi veya "." parçası yüzünden düz string karşılaştırması
      // kaçırıyor ve kendi üzerine göç yeniden mümkün oluyordu.
      final sonuc = StorageManager.migratableOldPaths(
        ['/depo/.movies/', '/depo/./.movies', '/depo/eski/../.movies'],
        '/depo/.movies',
      );

      expect(sonuc, isEmpty);
    });

    test('gerçekten farklı eski klasör göç listesinde kalır', () {
      // Aşırı temkinli bir filtre göçü tamamen durdurup eski indirmeleri
      // kütüphanede görünmez bırakırdı.
      final sonuc = StorageManager.migratableOldPaths(
        ['/depo/eski_klasor'],
        '/depo/.movies',
      );

      expect(sonuc, ['/depo/eski_klasor']);
    });
  });

  group('Yol karşılaştırma ve çöp kaydını yeni klasöre taşıma', () {
    test('isSameDirectory kanonik biçimde karşılaştırır', () {
      expect(StorageManager.isSameDirectory('/a/b', '/a/b/'), isTrue);
      expect(StorageManager.isSameDirectory('/a/b', '/a/c/../b'), isTrue);
      expect(StorageManager.isSameDirectory('/a/b', '/a/bc'), isFalse);
      // Boş yol "aynı klasör" sayılırsa göç tamamen durur.
      expect(StorageManager.isSameDirectory('', ''), isFalse);
    });

    test('rebaseToDirectory dosya adını güncel çöp klasörüne taşır', () {
      // İndirme klasörü göç edince indeksteki MUTLAK yollar geçersizleşiyor.
      // Kaydı hemen düşürmek dosyayı .trash içinde kayıtsız bırakıyordu:
      // arayüzde görünmez, geri alınamaz, silinemez ama kotaya sayılır.
      expect(
        StorageManager.rebaseToDirectory(
          '/storage/emulated/0/Download/.offlineyoutube/.trash/Video [abc].mp4',
          '/depo/.movies/.trash',
        ).replaceAll('\\', '/'),
        '/depo/.movies/.trash/Video [abc].mp4',
      );
    });
  });

  group('Depolama kotası kapısı: ölçülemeyen alan 0 sayılmamalı', () {
    test('ölçüm yapılamadıysa indirmeye izin verilmez', () {
      // Depolama izni geri alınır veya kart çıkarılırsa ölçüm 0 dönüyordu.
      // 0 < 20 GB olduğu için kota kapısı hiç kapanmıyor, uygulama disk dolana
      // kadar indirmeye devam ediyordu.
      const olculemedi = UsedStorageMeasurement.unknown();

      expect(olculemedi.measured, isFalse);
      expect(olculemedi.bytes, 0);
      expect(StorageManager.isWithinStorageQuota(olculemedi, 20 * 1024 * 1024 * 1024), isFalse);
    });

    test('ölçülen alan kotanın altındaysa izin verilir', () {
      expect(
        StorageManager.isWithinStorageQuota(
          const UsedStorageMeasurement.of(5 * 1024 * 1024 * 1024),
          20 * 1024 * 1024 * 1024,
        ),
        isTrue,
      );
    });

    test('ölçülen alan kotaya eşit veya üstündeyse izin verilmez', () {
      const kota = 20 * 1024 * 1024 * 1024;
      expect(
        StorageManager.isWithinStorageQuota(const UsedStorageMeasurement.of(kota), kota),
        isFalse,
      );
      expect(
        StorageManager.isWithinStorageQuota(const UsedStorageMeasurement.of(kota + 1), kota),
        isFalse,
      );
    });
  });

  group('Çöp indeksi çözümleme: tek bozuk kayıt indeksi öldürmemeli', () {
    test('bozuk kayıt atlanır, sağlam kayıtlar korunur', () {
      // Eski kod `.map(...).toList()` kullanıyordu: tek bozuk kayıt istisna
      // fırlatıp TÜM indeksi boşaltıyor, boşalan indeks ilk yazmada diske
      // geçince çöpteki bütün videolar kayıtsız yetim dosyaya dönüşüyordu.
      final ham = jsonEncode([
        _gecerliKayit('aaa'),
        {
          'video': {'id': 'bozuk'}, // title, filePath ve downloadedAt yok
          'deletedAt': DateTime(2026, 8, 2).toIso8601String(),
        },
        _gecerliKayit('ccc'),
      ]);

      final sonuc = StorageManager.parseTrashIndex(ham);

      expect(sonuc.length, 2);
      expect(sonuc.map((t) => t.video.id), ['aaa', 'ccc']);
    });

    test('boş içerik boş liste döner', () {
      expect(StorageManager.parseTrashIndex(''), isEmpty);
      expect(StorageManager.parseTrashIndex('   \n'), isEmpty);
    });

    test('yarım yazılmış dosya istisna fırlatır, sessizce boşalmaz', () {
      // Sessizce boş liste dönmek, bozuk dosyanın üzerine yazılmasına ve
      // kaydın geri dönülmez biçimde kaybolmasına yol açıyordu. İstisna,
      // çağıranın dosyayı karantinaya almasını sağlar.
      final yarim = jsonEncode([_gecerliKayit('aaa')]).substring(0, 30);

      expect(() => StorageManager.parseTrashIndex(yarim), throwsFormatException);
    });

    test('liste olmayan JSON istisna fırlatır', () {
      expect(
        () => StorageManager.parseTrashIndex('{"video": 1}'),
        throwsFormatException,
      );
    });
  });
}
