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
