import 'package:mobile/core/playback/mini_player.dart';
import 'package:mobile/core/splash/splash_screen.dart';
import 'package:mobile/profile/profile_preview_sheet.dart';
import 'package:mobile/core/api/client_metadata.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile/auth/auth_models.dart';
import 'package:mobile/profile/profile_models.dart';
import 'package:mobile/playlists/playlist_models.dart';
import 'package:mobile/auth/email_verification_pending_screen.dart';
import 'package:mobile/auth/email_verified_screen.dart';
import 'package:mobile/auth/verification_expired_screen.dart';
import 'package:mobile/auth/change_password_screen.dart';
import 'package:mobile/auth/password_reset_code_screen.dart';
import 'package:mobile/auth/register_screen.dart';
import 'package:mobile/auth/reset_password_screen.dart';
import 'package:mobile/auth/login_screen.dart';
import 'package:mobile/auth/welcome_screen.dart';
import 'package:mobile/home/home_screen.dart';
import 'package:mobile/profile/add_friends_screen.dart';
import 'package:mobile/profile/connections_screen.dart';
import 'package:mobile/profile/music_preferences_screen.dart';
import 'package:mobile/profile/view_profile_screen.dart';
import 'package:mobile/profile/edit_profile_screen.dart';
import 'package:mobile/profile/personal_profile.dart';
import 'package:mobile/track_vote/create_event_screen.dart';
import 'package:mobile/track_vote/event_guests_screen.dart';
import 'package:mobile/track_vote/event_settings_screen.dart';
import 'package:mobile/track_vote/event_detail_screen.dart';
import 'package:mobile/track_vote/events_landing_screen.dart';
import 'package:mobile/track_vote/suggest_track_screen.dart';
import 'package:mobile/playlists/add_collaborators_screen.dart';
import 'package:mobile/playlists/add_song_search_screen.dart';
import 'package:mobile/playlists/edit_playlist_screen.dart';
import 'package:mobile/playlists/playlist_collaborators_screen.dart';
import 'package:mobile/playlists/create_playlist_screen.dart';
import 'package:mobile/playlists/playlist_detail_screen.dart';
import 'package:mobile/playlists/playlist_list_screen.dart';
import 'package:mobile/settings/update_password_screen.dart';
import 'package:mobile/settings/connected_accounts_screen.dart';
import 'package:mobile/settings/settings_screen.dart';
import 'package:mobile/settings/subscription_screen.dart';
import 'package:mobile/settings/premium_checkout_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Music Room',
      packageName: 'music_room',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/device_info'),
          (_) async => <String, dynamic>{},
        );
    for (final channel in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
      'xyz.luan/audioplayers',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => 1);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/audioplayers'),
          (call) async {
            if (call.method == 'create') {
              final id = (call.arguments as Map)['playerId'];
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                  .setMockMethodCallHandler(
                    MethodChannel('xyz.luan/audioplayers/events/$id'),
                    (_) async => null,
                  );
            }
            return 1;
          },
        );
    await ClientMetadata.headers();
  });
  dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8000');
  final authUser = AuthUser.fromJson({
    'id': 1,
    'email': 'listener@example.com',
  });
  final profile = UserProfile.fromJson({
    'id': 1,
    'display_name': 'Music listener',
  });
  final playlist = Playlist.fromJson({
    'id': 1,
    'owner': 'listener',
    'title': 'My playlist',
    'created_at': '2026-01-01',
    'updated_at': '2026-01-01',
  });
  final pages = <String, Widget Function()>{
    'SplashScreen': () => SplashScreen(),
    'NowPlayingScreen': () => const NowPlayingScreen(),
    'ProfilePreviewSheet': () => const Scaffold(
      body: ProfilePreviewSheet(userId: 1, initialName: 'Music listener'),
    ),
    'EmailVerificationPendingScreen': () =>
        EmailVerificationPendingScreen(email: 'listener@example.com'),
    'EmailVerifiedScreen': () => EmailVerifiedScreen(),
    'VerificationExpiredScreen': () =>
        VerificationExpiredScreen(email: 'listener@example.com'),
    'ChangePasswordScreen': () => ChangePasswordScreen(resetToken: 'test'),
    'PasswordResetCodeScreen': () =>
        PasswordResetCodeScreen(email: 'listener@example.com'),
    'RegisterScreen': () => RegisterScreen(),
    'ResetPasswordScreen': () => ResetPasswordScreen(),
    'LoginScreen': () => LoginScreen(),
    'WelcomeScreen': () => WelcomeScreen(),
    'HomeScreen': () => HomeScreen(),
    'AddFriendsScreen': () => AddFriendsScreen(),
    'ConnectionsScreen': () => ConnectionsScreen(),
    'MusicPreferencesScreen': () => MusicPreferencesScreen(profile: profile),
    'ViewProfileScreen': () => ViewProfileScreen(
      userId: 1,
      initialFullName: 'Music listener',
      relationshipStatus: RelationshipStatus.none,
    ),
    'EditProfileScreen': () =>
        EditProfileScreen(profile: profile, email: 'listener@example.com'),
    'PersonalProfileScreen': () => PersonalProfileScreen(),
    'CreateEventScreen': () => CreateEventScreen(),
    'EventGuestsScreen': () => EventGuestsScreen(eventId: 1),
    'EventSettingsScreen': () => EventSettingsScreen(eventId: 1),
    'EventDetailScreen': () => EventDetailScreen(eventId: 1),
    'PrivateEventAccessDeniedScreen': () => PrivateEventAccessDeniedScreen(),
    'EventsLandingScreen': () => EventsLandingScreen(),
    'SuggestTrackScreen': () => SuggestTrackScreen(eventId: 1),
    'AddCollaboratorsScreen': () =>
        AddCollaboratorsScreen(playlistId: 1, existingCollaboratorIds: {}),
    'AddSongSearchScreen': () => AddSongSearchScreen(playlistId: 1),
    'EditPlaylistScreen': () => EditPlaylistScreen(playlist: playlist),
    'PlaylistCollaboratorsScreen': () => PlaylistCollaboratorsScreen(
      playlistId: 1,
      playlistTitle: 'My playlist',
      isOwner: true,
    ),
    'CreatePlaylistScreen': () => CreatePlaylistScreen(),
    'PlaylistDetailScreen': () => PlaylistDetailScreen(playlistId: 1),
    'PlaylistListScreen': () => PlaylistListScreen(),
    'UpdatePasswordScreen': () => UpdatePasswordScreen(),
    'ConnectedAccountsScreen': () =>
        ConnectedAccountsScreen(authUser: authUser),
    'SettingsScreen': () =>
        SettingsScreen(profile: profile, authUser: authUser),
    'SubscriptionScreen': () => SubscriptionScreen(authUser: authUser),
    'PremiumCheckoutScreen': () =>
        PremiumCheckoutScreen(onActivate: () async => authUser),
  };
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1024, 360),
    const Size(1440, 900),
  ]) {
    for (final page in pages.entries) {
      testWidgets(
        '${page.key} at $size',
        (tester) => http.runWithClient(() async {
          FlutterSecureStorage.setMockInitialValues({
            'auth_access_token': 'test',
          });
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final previousError = FlutterError.onError;
          FlutterError.onError = (details) {
            FlutterError.dumpErrorToConsole(details, forceReport: true);
            previousError!(details);
          };
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark(useMaterial3: true),
              home: page.value(),
            ),
          );
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          });
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          });
          await tester.pump();
          expect(tester.takeException(), isNull);
          // Exercise the lower portions of forms and lists as well as the header.
          for (final scrollable
              in find.byType(Scrollable).evaluate().toList()) {
            final state =
                (scrollable as StatefulElement).state as ScrollableState;
            if (state.position.hasContentDimensions &&
                state.position.maxScrollExtent.isFinite) {
              state.position.jumpTo(state.position.maxScrollExtent);
            }
          }
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 300));
        }, () => MockClient(respond)),
      );
    }
  }
}

Future<http.Response> respond(http.Request request) async {
  final path = request.url.path;
  final user = {
    'id': 1,
    'email': 'listener@example.com',
    'display_name': 'Music listener',
    'username': 'listener',
  };
  final collection = {
    'id': 1,
    'owner': 'listener',
    'host': 'listener@example.com',
    'title': 'Weekend listening together',
    'description': 'Our favorite music for a relaxing weekend.',
    'created_at': '2026-01-01',
    'updated_at': '2026-01-01',
    'is_member': true,
  };
  if (path.contains('access-requests') && path.endsWith('/mine/')) {
    return http.Response('{}', 404);
  }
  final song = {
    'id': 1,
    'external_id': 'test-track',
    'title': 'A long song title for the weekend listening session',
    'artist': 'An artist with a long display name',
    'duration_seconds': 180,
  };
  Object data = [];
  if (path.endsWith('/songs/')) {
    return http.Response(
      jsonEncode([
        {
          'id': 1,
          'playlist': 1,
          'song': 1,
          'song_title': song['title'],
          'song_artist': song['artist'],
          'position': 1,
          'added_at': '2026-01-01',
        },
      ]),
      200,
    );
  }
  if (path.endsWith('/queue/')) {
    return http.Response(
      jsonEncode([
        {'id': 1, 'event': 1, 'song': song, 'added_at': '2026-01-01'},
      ]),
      200,
    );
  }
  if (path.contains('/tracks/')) return http.Response(jsonEncode([song]), 200);
  if (path.endsWith('/user/me/') ||
      RegExp(r'/profile/(me|1)/$').hasMatch(path)) {
    data = user;
  } else if (RegExp(r'/(playlists|events)/1/$').hasMatch(path)) {
    data = collection;
  } else if (RegExp(r'/(playlists|events)/$').hasMatch(path)) {
    data = [collection];
  }
  return http.Response(
    jsonEncode(data),
    200,
    headers: {'content-type': 'application/json'},
  );
}
