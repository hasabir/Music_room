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

/// The current user's own profile, as returned by
/// `GET /api/v1/profile/me/` (`ProfileSerializer`, all fields visible).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.bio,
    required this.location,
    required this.favoriteArtist,
    required this.phoneNumber,
    required this.profileImageUrl,
    required this.favoriteGenres,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as int,
    displayName: json['display_name'] as String? ?? '',
    bio: json['bio'] as String? ?? '',
    location: json['location'] as String? ?? '',
    favoriteArtist: json['favorite_artist'] as String? ?? '',
    phoneNumber: json['phone_number'] as String? ?? '',
    profileImageUrl: json['profile_image'] as String?,
    favoriteGenres:
        (json['favorite_genres'] as List<dynamic>?)
            ?.map((genre) => genre as String)
            .toList() ??
        const [],
  );

  final int id;
  final String displayName;
  final String bio;
  final String location;
  final String favoriteArtist;
  final String phoneNumber;
  final String? profileImageUrl;
  final List<String> favoriteGenres;
}

/// One accepted friend, as returned by `GET /api/v1/profile/friends/`
/// (`FriendSerializer`).
class Friend {
  const Friend({required this.id, required this.firstName, required this.lastName});

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
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.relationshipStatus,
    required this.friendshipId,
  });

  factory SearchUser.fromJson(Map<String, dynamic> json) => SearchUser(
    id: json['id'] as int,
    firstName: json['first_name'] as String? ?? '',
    lastName: json['last_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    relationshipStatus: RelationshipStatus.fromJson(
      json['relationship_status'] as String? ?? 'none',
    ),
    friendshipId: json['friendship_id'] as int?,
  );

  final int id;
  final String firstName;
  final String lastName;
  final String email;
  final RelationshipStatus relationshipStatus;
  final int? friendshipId;

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? email : name;
  }

  SearchUser copyWith({RelationshipStatus? relationshipStatus, int? friendshipId}) => SearchUser(
    id: id,
    firstName: firstName,
    lastName: lastName,
    email: email,
    relationshipStatus: relationshipStatus ?? this.relationshipStatus,
    friendshipId: friendshipId ?? this.friendshipId,
  );
}

/// Another user's profile as filtered by visibility rules, from
/// `GET /api/v1/profile/profile/<user_id>/`. `location` and
/// `favoriteArtist` are only present when you're friends with them —
/// `null` otherwise (as opposed to `''`, which means "set but empty").
class OtherUserProfile {
  const OtherUserProfile({
    required this.displayName,
    required this.bio,
    required this.profileImageUrl,
    required this.favoriteGenres,
    required this.location,
    required this.favoriteArtist,
  });

  factory OtherUserProfile.fromJson(Map<String, dynamic> json) => OtherUserProfile(
    displayName: json['display_name'] as String? ?? '',
    bio: json['bio'] as String? ?? '',
    profileImageUrl: json['profile_image'] as String?,
    favoriteGenres:
        (json['favorite_genres'] as List<dynamic>?)?.map((genre) => genre as String).toList() ??
        const [],
    location: json['location'] as String?,
    favoriteArtist: json['favorite_artist'] as String?,
  );

  final String displayName;
  final String bio;
  final String? profileImageUrl;
  final List<String> favoriteGenres;
  final String? location;
  final String? favoriteArtist;
}
