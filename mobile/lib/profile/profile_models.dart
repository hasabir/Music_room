import 'package:flutter/material.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Formats a birthday for display (e.g. "August 26, 2006"). Shared by the
/// Edit Profile and Profile screens so the two stay in sync.
String formatBirthday(DateTime date) =>
    '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';

/// Human-readable labels for the backend's `Profile.MUSIC_GENRE_CHOICES`
/// (see `backend/profiles/models.py`). Keys are the genre codes stored/sent
/// to the API; values are what's shown in the UI.
const Map<String, String> musicGenreLabels = {
  'pop': 'Pop',
  'rock': 'Rock',
  'hip_hop': 'Hip-Hop',
  'rap': 'Rap',
  'rnb': 'R&B',
  'jazz': 'Jazz',
  'blues': 'Blues',
  'classical': 'Classical',
  'electronic': 'Electronic',
  'house': 'House',
  'techno': 'Techno',
  'metal': 'Metal',
  'punk': 'Punk',
  'reggae': 'Reggae',
  'country': 'Country',
  'folk': 'Folk',
  'soul': 'Soul',
  'funk': 'Funk',
  'indie': 'Indie',
  'alternative': 'Alternative',
  'latin': 'Latin',
  'afrobeat': 'Afrobeat',
  'kpop': 'K-Pop',
  'soundtrack': 'Soundtrack',
};

/// Matches the backend's `Profile._default_field_visibility()` — the tier
/// each configurable field falls back to when a profile's
/// `field_visibility` doesn't mention it (e.g. accounts created before
/// this feature existed).
const Map<String, String> defaultFieldVisibility = {
  'bio': 'public',
  'location': 'friends',
  'favorite_artist': 'friends',
  'phone_number': 'private',
  'birthday': 'friends',
  'activity': 'public',
  // Defaults to 'public' — preserves favorite_genres' previous
  // unconditionally-visible behavior for any profile that hasn't
  // explicitly picked a tier for it. See `UserProfileView` on the backend.
  'favorite_genres': 'public',
};

/// Allowed values for `Profile.avatar_type`
/// (`backend/profiles/models.py`: `Profile.AVATAR_TYPE_CHOICES`). Says how
/// to interpret [UserProfile.avatar] / [OtherUserProfile.avatar]:
/// [profileAvatarTypePreset] is a preset id — resolve via
/// [AvatarPreset.byId]; [profileAvatarTypeExternalUrl] and
/// [profileAvatarTypeCustom] are both plain image URLs, rendered the same
/// way (`Image.network`) regardless of which one it is.
const String profileAvatarTypePreset = 'preset';
const String profileAvatarTypeExternalUrl = 'external_url';
const String profileAvatarTypeCustom = 'custom';

/// One of the built-in avatar-grid images, as an alternative to a social
/// sign-in photo or uploading a custom [UserProfile.profileImageUrl]. IDs
/// mirror `Profile.AVATAR_PRESET_CHOICES` in `backend/profiles/models.py`
/// — the backend only knows these as opaque ids; this class owns the
/// id -> bundled-asset mapping, the same way `PlaylistCoverPreset` /
/// `EventCoverPreset` work for their own preset grids.
class AvatarPreset {
  const AvatarPreset._(this.id, this.assetPath, this.glowColor);

  final String id;
  final String assetPath;
  final Color glowColor;

  static const _basePath = 'assets/images/avatars';
  static const p1 = AvatarPreset._('1', '$_basePath/avatar1.jpg', Color(0xFFFF7A59));
  static const p2 = AvatarPreset._('2', '$_basePath/avatar2.jpg', Color(0xFF818CF8));
  static const p3 = AvatarPreset._('3', '$_basePath/avatar3.jpg', Color(0xFF2FD9F4));
  static const p4 = AvatarPreset._('4', '$_basePath/avatar4.jpg', Color(0xFFFBBF24));
  static const p5 = AvatarPreset._('5', '$_basePath/avatar5.jpg', Color(0xFF38BDF8));
  static const p6 = AvatarPreset._('6', '$_basePath/avatar6.jpg', Color(0xFF34D399));
  static const p7 = AvatarPreset._('7', '$_basePath/avatar9.jpg', Color(0xFFA78BFA));
  static const p8 = AvatarPreset._('8', '$_basePath/avatart7.jpg', Color(0xFFF472B6));
  static const p9 = AvatarPreset._('9', '$_basePath/avatart8.jpg', Color(0xFFFF7A59));
  static const p10 = AvatarPreset._('10', '$_basePath/avatart9.jpg', Color(0xFF2FD9F4));
  static const p11 = AvatarPreset._('11', '$_basePath/avatart10.jpg', Color(0xFF34D399));

  /// All 11 presets, in the order they're offered in the avatar grid.
  static const all = [p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11];

  static AvatarPreset? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}

/// The current user's own profile, as returned by
/// `GET /api/v1/profile/me/` (`ProfileSerializer`, all fields visible).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.bio,
    required this.location,
    required this.favoriteArtist,
    required this.phoneNumber,
    required this.birthday,
    required this.profileImageUrl,
    required this.avatar,
    required this.avatarType,
    required this.avatarPresetId,
    required this.favoriteGenres,
    required this.votesCount,
    required this.playlistsCount,
    required this.fieldVisibility,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as int,
    username: json['username'] as String? ?? '',
    displayName: json['display_name'] as String? ?? '',
    bio: json['bio'] as String? ?? '',
    location: json['location'] as String? ?? '',
    favoriteArtist: json['favorite_artist'] as String? ?? '',
    phoneNumber: json['phone_number'] as String? ?? '',
    birthday: json['birthday'] != null
        ? DateTime.parse(json['birthday'] as String)
        : null,
    profileImageUrl: json['profile_image'] as String?,
    avatar: json['avatar'] as String?,
    avatarType: json['avatar_type'] as String? ?? profileAvatarTypePreset,
    avatarPresetId: json['avatar_preset_id'] as String? ?? '',
    favoriteGenres:
        (json['favorite_genres'] as List<dynamic>?)
            ?.map((genre) => genre as String)
            .toList() ??
        const [],
    votesCount: json['votes_count'] as int? ?? 0,
    playlistsCount: json['playlists_count'] as int? ?? 0,
    fieldVisibility: {
      ...defaultFieldVisibility,
      ...(json['field_visibility'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(key, value as String),
          ) ??
          const {},
    },
  );

  final int id;
  final String username;
  final String displayName;
  final String bio;
  final String location;
  final String favoriteArtist;
  final String phoneNumber;
  final DateTime? birthday;
  final String? profileImageUrl;

  /// The one value to render regardless of source — a preset id when
  /// [avatarType] is [profileAvatarTypePreset] (resolve via
  /// [AvatarPreset.byId]), otherwise a plain image URL. See
  /// `ProfileAvatarView` for the shared rendering logic.
  final String? avatar;

  /// One of [profileAvatarTypePreset] / [profileAvatarTypeExternalUrl] /
  /// [profileAvatarTypeCustom].
  final String avatarType;

  /// The picked preset's id when [avatarType] is [profileAvatarTypePreset]
  /// — blank otherwise. Only meaningful for pre-selecting the current
  /// choice in the avatar grid picker; use [avatar] to render.
  final String avatarPresetId;

  final List<String> favoriteGenres;
  final int votesCount;
  final int playlistsCount;

  /// Per-field visibility tier ('public'/'friends'/'private'), keyed by
  /// 'bio', 'location', 'favorite_artist', 'phone_number', 'birthday',
  /// 'activity'. Always has an entry for every key (missing ones are
  /// backfilled from [defaultFieldVisibility]). `display_name` has no
  /// entry — it's always public.
  final Map<String, String> fieldVisibility;
}

/// One accepted friend, as returned by `GET /api/v1/profile/friends/`
/// (`FriendSerializer`).
class Friend {
  const Friend({
    required this.id,
    required this.firstName,
    required this.lastName,
  });

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
    id: json['id'] as int,
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
  );

  final int id;
  final String firstName;
  final String lastName;

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? 'Unknown' : name;
  }
}

/// A pending friend request, as returned by `GET /api/v1/profile/friends/requests/`
/// (received) or `GET /api/v1/profile/friends/requests/sent/` (sent).
/// Each endpoint only ever returns requests where the signed-in user is on
/// one fixed side, so [otherUserId]/[otherUserFirstName]/[otherUserLastName]
/// always describe the *other* party regardless of which endpoint it came
/// from.
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.otherUserId,
    required this.otherUserFirstName,
    required this.otherUserLastName,
  });

  factory FriendRequest.fromReceivedJson(Map<String, dynamic> json) =>
      FriendRequest._fromJson(json, otherUserKey: 'sender');

  factory FriendRequest.fromSentJson(Map<String, dynamic> json) =>
      FriendRequest._fromJson(json, otherUserKey: 'receiver');

  factory FriendRequest._fromJson(
    Map<String, dynamic> json, {
    required String otherUserKey,
  }) {
    final other = json[otherUserKey] as Map<String, dynamic>;
    return FriendRequest(
      id: json['id'] as int,
      otherUserId: other['id'] as int,
      otherUserFirstName: other['first_name'] as String? ?? '',
      otherUserLastName: other['last_name'] as String? ?? '',
    );
  }

  final int id;
  final int otherUserId;
  final String otherUserFirstName;
  final String otherUserLastName;

  String get otherUserFullName {
    final name = '$otherUserFirstName $otherUserLastName'.trim();
    return name.isEmpty ? 'Unknown' : name;
  }
}

/// A user's relationship to the signed-in user, as returned by
/// `GET /api/v1/profile/search/`.
enum RelationshipStatus {
  none,
  pendingSent,
  pendingReceived,
  friends;

  static RelationshipStatus fromJson(String value) => switch (value) {
    'pending_sent' => RelationshipStatus.pendingSent,
    'pending_received' => RelationshipStatus.pendingReceived,
    'friends' => RelationshipStatus.friends,
    _ => RelationshipStatus.none,
  };
}

/// One user search result, as returned by `GET /api/v1/profile/search/`.
class SearchUser {
  const SearchUser({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.relationshipStatus,
    required this.friendshipId,
  });

  factory SearchUser.fromJson(Map<String, dynamic> json) => SearchUser(
    id: json['id'] as int,
    username: json['username'] as String? ?? '',
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    relationshipStatus: RelationshipStatus.fromJson(
      json['relationship_status'] as String? ?? 'none',
    ),
    friendshipId: json['friendship_id'] as int?,
  );

  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final RelationshipStatus relationshipStatus;
  final int? friendshipId;

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty
        ? (username.isNotEmpty ? '@$username' : 'Unknown user')
        : name;
  }

  String get publicName => username.isNotEmpty ? '@$username' : fullName;

  SearchUser copyWith({
    RelationshipStatus? relationshipStatus,
    int? friendshipId,
  }) => SearchUser(
    id: id,
    username: username,
    firstName: firstName,
    lastName: lastName,
    email: email,
    relationshipStatus: relationshipStatus ?? this.relationshipStatus,
    friendshipId: friendshipId ?? this.friendshipId,
  );
}

/// Another user's profile as filtered by visibility rules, from
/// `GET /api/v1/profile/profile/<user_id>/`. `location`, `favoriteArtist`,
/// and `phoneNumber` are only present when their `field_visibility` tier
/// is 'public', or 'friends' and you're friends with them — `null`
/// otherwise (as opposed to `''`, which means "set but empty"). See
/// `UserProfileView` on the backend.
class OtherUserProfile {
  const OtherUserProfile({
    required this.displayName,
    required this.bio,
    required this.profileImageUrl,
    required this.avatar,
    required this.avatarType,
    required this.favoriteGenres,
    required this.location,
    required this.favoriteArtist,
    required this.phoneNumber,
    required this.birthday,
    required this.votesCount,
    required this.playlistsCount,
  });

  factory OtherUserProfile.fromJson(Map<String, dynamic> json) =>
      OtherUserProfile(
        displayName: json['display_name'] as String? ?? '',
        bio: json['bio'] as String? ?? '',
        profileImageUrl: json['profile_image'] as String?,
        avatar: json['avatar'] as String?,
        avatarType: json['avatar_type'] as String? ?? profileAvatarTypePreset,
        favoriteGenres:
            (json['favorite_genres'] as List<dynamic>?)
                ?.map((genre) => genre as String)
                .toList() ??
            const [],
        location: json['location'] as String?,
        favoriteArtist: json['favorite_artist'] as String?,
        phoneNumber: json['phone_number'] as String?,
        birthday: json['birthday'] != null
            ? DateTime.parse(json['birthday'] as String)
            : null,
        votesCount: json['votes_count'] as int? ?? 0,
        playlistsCount: json['playlists_count'] as int? ?? 0,
      );

  final String displayName;
  final String bio;
  final String? profileImageUrl;

  /// See [UserProfile.avatar] — always present, avatar is public
  /// information (`UserProfileView` docstring).
  final String? avatar;

  /// See [UserProfile.avatarType].
  final String avatarType;

  final List<String> favoriteGenres;
  final String? location;
  final String? favoriteArtist;
  final String? phoneNumber;
  final DateTime? birthday;
  final int votesCount;

  /// Always present regardless of visibility filtering — see
  /// `backend/profiles/views.py`'s `UserProfileView` docstring.
  final int playlistsCount;
}
