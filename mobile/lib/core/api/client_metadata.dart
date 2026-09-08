import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class ClientMetadata {
  static Future<Map<String, String>>? _cached;

  static Future<Map<String, String>> headers() => _cached ??= _load();

  static Future<Map<String, String>> _load() async {
    final platform = kIsWeb
        ? 'Web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'Android',
            TargetPlatform.iOS => 'iOS',
            TargetPlatform.macOS => 'macOS',
            TargetPlatform.windows => 'Windows',
            TargetPlatform.linux => 'Linux',
            TargetPlatform.fuchsia => 'Fuchsia',
          };
    var device = 'Unknown';
    var version = 'Unknown';
    try {
      final info = await DeviceInfoPlugin().deviceInfo.timeout(
        const Duration(seconds: 3),
      );
      device = switch (info) {
        AndroidDeviceInfo d => '${d.manufacturer} ${d.model}',
        IosDeviceInfo d => d.utsname.machine,
        WebBrowserInfo d =>
          '${d.browserName.name} (${d.platform ?? 'unknown OS'})',
        MacOsDeviceInfo d => d.model,
        LinuxDeviceInfo d => d.prettyName,
        WindowsDeviceInfo _ => 'Windows PC',
        _ => 'Unknown',
      };
    } catch (_) {
      // Metadata failure must not prevent login or other API requests.
    }
    try {
      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 3),
      );
      version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Do not invent a version if the platform cannot report it.
    }
    return {
      'X-Platform': _headerValue(platform, 20),
      'X-Device': _headerValue(device, 100),
      'X-App-Version': _headerValue(version, 20),
    };
  }

  static String _headerValue(String value, int maxLength) {
    final safe = value.replaceAll(RegExp(r'[^\x20-\x7E]'), '?').trim();
    if (safe.isEmpty) return 'Unknown';
    return safe.length > maxLength ? safe.substring(0, maxLength) : safe;
  }
}

/// All verbs, paginated requests and multipart uploads share this transport.
class MetadataClient extends http.BaseClient {
  MetadataClient(this._inner, {Future<Map<String, String>> Function()? headers})
    : _headers = headers ?? ClientMetadata.headers;

  final http.Client _inner;
  final Future<Map<String, String>> Function() _headers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(await _headers());
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
