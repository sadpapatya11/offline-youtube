import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:offlineyoutube/models/download_task.dart';
import 'package:offlineyoutube/services/download_queue_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kuyruğun diske yazılmasını "önce yükle, sonra yaz" kuralına bağlar.
///
/// Kök sorun (2026-08-25 denetimi):
/// saveTasksToStorage, bellekteki `tasks` listesini olduğu gibi SharedPreferences'a
/// yazıyordu ve liste henüz diskten YÜKLENMEMİŞ olabilirdi. İki gerçek yol vardı:
///
/// 1. DownloadProvider constructor'ı `_manager.init()` çağrısını await ETMİYOR
///    (download_provider.dart:56). init içindeki _loadTasksFromStorage bitmeden
///    çalışan bir kayıt, boş listeyi diske yazıp kullanıcının kuyruğunu siler.
/// 2. WorkManager arka plan izolatı callbackDispatcher içinde yeni bir DownloadProvider
///    örnekliyor. O izolattaki DownloadQueueManager.instance ön plandakinden FARKLI bir
///    nesnedir ve kendi boş listesini aynı anahtara yazarak ön plandaki kuyruğu ezer.
///
/// Kural: kuyruk yüklenmeden (isLoaded false) diske YAZILMAZ. Yazmamak veri kaybetmez,
/// yanlış yazmak kaybeder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tasksKey = 'offline_youtube_persisted_tasks_v3';

  DownloadTask ornekGorev(String id) => DownloadTask(
        id: id,
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        title: 'Görev $id',
        status: DownloadStatus.queued,
      );

  late DownloadQueueManager manager;

  setUp(() {
    manager = DownloadQueueManager.instance;
    manager.tasks.clear();
    manager.activeTaskId = null;
  });

  test('kuyruk YÜKLENMEDEN yapılan kayıt diskteki mevcut kuyruğu EZMEZ', () async {
    // Diskte kullanıcının 3 görevlik kuyruğu duruyor.
    final mevcut = jsonEncode([
      ornekGorev('a').toJson(),
      ornekGorev('b').toJson(),
      ornekGorev('c').toJson(),
    ]);
    SharedPreferences.setMockInitialValues({tasksKey: mevcut});

    // Yükleme tamamlanmadan (isLoaded false) bellekteki liste boşken kayıt tetikleniyor.
    manager.isLoaded = false;
    manager.tasks.clear();
    await manager.saveTasksToStorage();

    final prefs = await SharedPreferences.getInstance();
    final diskteki = jsonDecode(prefs.getString(tasksKey)!) as List;

    expect(diskteki.length, 3,
        reason: 'yüklenmemiş boş liste diske yazılırsa kullanıcının kuyruğu tamamen silinir');
    expect(
      diskteki.map((e) => (e as Map)['id']).toList(),
      ['a', 'b', 'c'],
    );
  });

  test('kuyruk yüklendikten sonra kayıt normal biçimde çalışır', () async {
    SharedPreferences.setMockInitialValues({});

    manager.isLoaded = true;
    manager.tasks
      ..clear()
      ..addAll([ornekGorev('x'), ornekGorev('y')]);
    await manager.saveTasksToStorage();

    final prefs = await SharedPreferences.getInstance();
    final diskteki = jsonDecode(prefs.getString(tasksKey)!) as List;

    expect(diskteki.length, 2);
    expect(diskteki.map((e) => (e as Map)['id']).toList(), ['x', 'y']);
  });

  test('yüklendikten sonra kuyruğu kasıtlı boşaltmak diske yansır', () async {
    SharedPreferences.setMockInitialValues({
      tasksKey: jsonEncode([ornekGorev('z').toJson()]),
    });

    manager.isLoaded = true;
    manager.tasks.clear();
    await manager.saveTasksToStorage();

    final prefs = await SharedPreferences.getInstance();
    final diskteki = jsonDecode(prefs.getString(tasksKey)!) as List;

    expect(diskteki, isEmpty,
        reason: 'kullanıcı kuyruğu gerçekten temizlediyse bu diske yazılabilmeli');
  });

  tearDown(() {
    manager.isLoaded = false;
    manager.tasks.clear();
  });
}
