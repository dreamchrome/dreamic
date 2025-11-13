import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../utils/logger.dart';

/// Utility for downloading and caching images for rich notifications.
///
/// This loader handles:
/// - Async image download with timeout
/// - Local caching to avoid repeated downloads
/// - Graceful failure handling
/// - Automatic cache cleanup
class NotificationImageLoader {
  /// Default timeout for image downloads.
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// Maximum cache age before images are re-downloaded.
  static const Duration maxCacheAge = Duration(days: 7);

  /// Downloads an image from [url] and returns the local file path.
  ///
  /// Images are cached locally to avoid repeated downloads.
  /// If download fails or times out, returns null.
  ///
  /// Parameters:
  /// - [url]: The URL of the image to download
  /// - [timeout]: Maximum time to wait for download (default: 10 seconds)
  ///
  /// Example:
  /// ```dart
  /// final imagePath = await NotificationImageLoader.downloadImage(
  ///   'https://example.com/image.jpg',
  /// );
  /// if (imagePath != null) {
  ///   print('Image cached at: $imagePath');
  /// }
  /// ```
  static Future<String?> downloadImage(
    String url, {
    Duration timeout = defaultTimeout,
  }) async {
    if (kIsWeb) {
      // Web doesn't support local file storage for notifications
      logi('Image download not supported on web');
      return null;
    }

    try {
      // Check if image is already cached
      final cachedPath = await _getCachedImagePath(url);
      if (cachedPath != null) {
        logi('Using cached image: $cachedPath');
        return cachedPath;
      }

      logi('Downloading notification image: $url');

      // Download the image with timeout
      final response = await http.get(Uri.parse(url)).timeout(timeout);

      if (response.statusCode != 200) {
        loge('Failed to download image: HTTP ${response.statusCode}', url);
        return null;
      }

      // Determine file extension from URL or content type
      final extension = _getImageExtension(url, response.headers['content-type']);

      // Save to cache directory
      final filePath = await _saveToCache(url, response.bodyBytes, extension);

      logi('Image downloaded and cached: $filePath');
      return filePath;
    } catch (e, stackTrace) {
      loge(e, 'Error downloading notification image', stackTrace);
      return null;
    }
  }

  /// Checks if an image is already cached and returns its path.
  ///
  /// Returns null if image is not cached or cache is too old.
  static Future<String?> _getCachedImagePath(String url) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final fileName = _generateFileName(url);

      // Try common extensions
      for (final ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']) {
        final file = File('${cacheDir.path}/$fileName$ext');
        if (await file.exists()) {
          // Check if cache is still valid
          final stat = await file.stat();
          final age = DateTime.now().difference(stat.modified);

          if (age < maxCacheAge) {
            return file.path;
          } else {
            // Cache is too old, delete it
            await file.delete();
          }
        }
      }

      return null;
    } catch (e, stackTrace) {
      loge(e, 'Error checking cached image', stackTrace);
      return null;
    }
  }

  /// Saves image bytes to the cache directory.
  static Future<String> _saveToCache(
    String url,
    List<int> bytes,
    String extension,
  ) async {
    final cacheDir = await _getCacheDirectory();
    final fileName = _generateFileName(url);
    final file = File('${cacheDir.path}/$fileName$extension');

    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Gets the cache directory for notification images.
  static Future<Directory> _getCacheDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/notification_images');

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir;
  }

  /// Generates a unique filename based on the URL.
  static String _generateFileName(String url) {
    // Use URL hash as filename to avoid special characters
    return url.hashCode.abs().toString();
  }

  /// Extracts the file extension from URL or content type.
  static String _getImageExtension(String url, String? contentType) {
    // Try to get extension from URL
    final urlExtension = path.extension(url).toLowerCase();
    if (urlExtension.isNotEmpty &&
        ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(urlExtension)) {
      return urlExtension;
    }

    // Fall back to content type
    if (contentType != null) {
      if (contentType.contains('jpeg')) return '.jpg';
      if (contentType.contains('png')) return '.png';
      if (contentType.contains('gif')) return '.gif';
      if (contentType.contains('webp')) return '.webp';
    }

    // Default to jpg
    return '.jpg';
  }

  /// Clears all cached notification images.
  ///
  /// Useful for:
  /// - Freeing up disk space
  /// - Clearing old/stale images
  /// - Testing/debugging
  ///
  /// Example:
  /// ```dart
  /// await NotificationImageLoader.clearCache();
  /// ```
  static Future<void> clearCache() async {
    if (kIsWeb) return;

    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        logi('Notification image cache cleared');
      }
    } catch (e, stackTrace) {
      loge(e, 'Error clearing notification image cache', stackTrace);
    }
  }

  /// Removes old cached images that exceed [maxAge].
  ///
  /// This is useful for periodic cleanup without deleting all cached images.
  ///
  /// Example:
  /// ```dart
  /// // Remove images older than 7 days
  /// await NotificationImageLoader.cleanupOldCache(Duration(days: 7));
  /// ```
  static Future<void> cleanupOldCache([Duration maxAge = maxCacheAge]) async {
    if (kIsWeb) return;

    try {
      final cacheDir = await _getCacheDirectory();
      if (!await cacheDir.exists()) return;

      final files = await cacheDir.list().toList();
      final now = DateTime.now();
      int deletedCount = 0;

      for (final entity in files) {
        if (entity is File) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);

          if (age > maxAge) {
            await entity.delete();
            deletedCount++;
          }
        }
      }

      if (deletedCount > 0) {
        logi('Cleaned up $deletedCount old notification images');
      }
    } catch (e, stackTrace) {
      loge(e, 'Error cleaning up old notification images', stackTrace);
    }
  }
}
