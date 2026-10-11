import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final String apkDownloadUrl;
  final int assetSize;
  final bool hasUpdate;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    required this.assetSize,
    required this.hasUpdate,
  });
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const MethodChannel _channel = MethodChannel('com.abhishekpal.abhisuno/native');
  static const String _repoOwner = 'abhipal7453';
  static const String _repoName = 'abhi_suno';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 5),
  ));

  /// Dynamically get the installed version from Android package manager
  Future<String> getInstalledVersion() async {
    try {
      final String? version = await _channel.invokeMethod<String>('getAppVersion');
      if (version != null && version.isNotEmpty) {
        return version;
      }
    } catch (_) {}
    return '4.5.1+22';
  }


  /// Check GitHub Releases asynchronously for updates
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final currentVer = await getInstalledVersion();
      final url = Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases');
      final res = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'AbhiSuno-Android-App',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final List<dynamic> releases = json.decode(res.body);
        if (releases.isEmpty) return null;

        final latestRelease = releases.first as Map<String, dynamic>;
        final tagName = (latestRelease['tag_name'] ?? '').toString();
        final releaseNotes = (latestRelease['body'] ?? 'Performance improvements and bug fixes.').toString();
        final assets = latestRelease['assets'] as List<dynamic>? ?? [];

        String apkUrl = '';
        int apkSize = 0;
        for (final asset in assets) {
          final name = (asset['name'] ?? '').toString();
          if (name.endsWith('.apk')) {
            apkUrl = (asset['browser_download_url'] ?? '').toString();
            apkSize = (asset['size'] ?? 0) as int;
            break;
          }
        }

        final rawLatest = tagName.replaceFirst(RegExp(r'^[vV]'), '').trim();
        final cleanLatest = rawLatest.trim();
        final hasUpdate = _isNewerVersion(tagName, currentVer);

        return UpdateInfo(
          currentVersion: currentVer,
          latestVersion: cleanLatest.isEmpty ? currentVer : cleanLatest,
          releaseNotes: releaseNotes,
          apkDownloadUrl: apkUrl,
          assetSize: apkSize,
          hasUpdate: hasUpdate,
        );
      }
    } catch (_) {}

    return null;
  }

  /// Download APK with byte-level progress reporting
  Future<String?> downloadUpdateApk(
    String apkUrl, {
    required Function(int receivedBytes, int totalBytes, double percent) onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/AbhiSuno_Update.apk';

      final file = File(targetPath);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }

      await _dio.download(
        apkUrl,
        targetPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final double percent = total > 0 ? (received / total) : 0.0;
          onProgress(received, total, percent);
        },
      );

      if (File(targetPath).existsSync() && File(targetPath).lengthSync() > 1024 * 1024) {
        return targetPath;
      }
    } catch (_) {}
    return null;
  }

  /// Launch Android Package Installer using FileProvider
  Future<bool> installApk(String filePath) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  bool _isNewerVersion(String latest, String current) {
    if (latest.isEmpty) return false;
    try {
      final latestStr = latest.replaceFirst(RegExp(r'^[vV]'), '').trim();
      final currentStr = current.replaceFirst(RegExp(r'^[vV]'), '').trim();

      final lParts = latestStr.split('+');
      final cParts = currentStr.split('+');

      final lVer = lParts[0].split('-').first.split('.');
      final cVer = cParts[0].split('-').first.split('.');

      final maxLen = lVer.length > cVer.length ? lVer.length : cVer.length;
      for (int i = 0; i < maxLen; i++) {
        final l = i < lVer.length ? (int.tryParse(lVer[i]) ?? 0) : 0;
        final c = i < cVer.length ? (int.tryParse(cVer[i]) ?? 0) : 0;
        if (l > c) return true;
        if (l < c) return false;
      }

      // If version names are identical, check build number
      final lBuild = lParts.length > 1 ? (int.tryParse(lParts[1]) ?? 0) : 0;
      final cBuild = cParts.length > 1 ? (int.tryParse(cParts[1]) ?? 0) : 0;
      if (lBuild > cBuild) return true;

    } catch (_) {}
    return false;
  }
}
