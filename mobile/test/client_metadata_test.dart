import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/api/client_metadata.dart';

void main() {
  test(
    'metadata accompanies every HTTP verb and multipart without losing auth',
    () async {
      final requests = <http.Request>[];
      final client = MetadataClient(
        MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
        headers: () async => {
          'X-Platform': 'Android',
          'X-Device': 'Samsung SM-S911B',
          'X-App-Version': '1.0.0+1',
        },
      );
      final uri = Uri.parse('https://example.com/api/');
      for (final method in ['GET', 'POST', 'PATCH', 'DELETE']) {
        final request = http.Request(method, uri);
        request.headers['Authorization'] = 'Bearer test';
        await client.send(request);
      }
      final upload = http.MultipartRequest('PATCH', uri)
        ..headers['Authorization'] = 'Bearer test'
        ..files.add(
          http.MultipartFile.fromString(
            'image',
            'image-bytes',
            filename: 'cover.png',
          ),
        );
      await client.send(upload);
      expect(requests, hasLength(5));
      for (final request in requests) {
        expect(request.headers['X-Platform'], 'Android');
        expect(request.headers['X-Device'], 'Samsung SM-S911B');
        expect(request.headers['X-App-Version'], '1.0.0+1');
        expect(request.headers['Authorization'], 'Bearer test');
      }
      expect(
        requests.last.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(requests.last.body, contains('image-bytes'));
      client.close();
    },
  );
}
