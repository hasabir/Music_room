import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile/playlists/playlist_widgets.dart';

void main() {
  testWidgets('cover previews bytes without requiring a filesystem path', (
    tester,
  ) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK1sAAAAASUVORK5CYII=',
    );
    final image = XFile.fromData(
      bytes,
      name: 'cover.png',
      mimeType: 'image/png',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 116,
          height: 116,
          child: PlaylistPickedCover(image: image),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
    expect(tester.takeException(), isNull);
  });
}
