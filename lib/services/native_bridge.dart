import 'dart:async';
import 'package:flutter/services.dart';

class NativeBridge {
  static const MethodChannel _methodChannel =
      MethodChannel('com.offlineyoutube/downloader');
  static const EventChannel _eventChannel =
      EventChannel('com.offlineyoutube/download_events');

  static final NativeBridge instance = NativeBridge._internal();
  NativeBridge._internal();

  Stream<Map<dynamic, dynamic>>? _downloadEventStream;

  Stream<Map<dynamic, dynamic>> get downloadEvents {
    _downloadEventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<dynamic, dynamic>.from(event as Map));
    return _downloadEventStream!;
  }

  Future<bool> init() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('init');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateYtDlp() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('updateYtDlp');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> fetchMetadata(String url) async {
    try {
      final result = await _methodChannel.invokeMapMethod<String, dynamic>(
        'fetchMetadata',
        {'url': url},
      );
      return result ?? {};
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> startDownload({
    required String taskId,
    required String url,
    required String title,
    required String outputPath,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'startDownload',
        {
          'taskId': taskId,
          'url': url,
          'title': title,
          'outputPath': outputPath,
        },
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> pauseDownload(String taskId) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'pauseDownload',
        {'taskId': taskId},
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> resumeDownload({
    required String taskId,
    required String url,
    required String title,
    required String outputPath,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'resumeDownload',
        {
          'taskId': taskId,
          'url': url,
          'title': title,
          'outputPath': outputPath,
        },
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> cancelDownload(String taskId) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>(
        'cancelDownload',
        {'taskId': taskId},
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> hasAllFilesPermission() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('hasAllFilesPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> requestAllFilesPermission() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('requestAllFilesPermission');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<int> getFolderSize(String path) async {
    try {
      final result =
          await _methodChannel.invokeMethod<int>('getFolderSize', {'path': path});
      return result ?? 0;
    } catch (e) {
      return 0;
    }
  }
}
