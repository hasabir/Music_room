/// Placeholder data for parts of the Profile screen the backend doesn't
/// model yet.
///
/// Everything in this file is local/mock and clearly isolated here so it
/// can be swapped for real API data without touching the rest of the
/// profile feature:
/// - "Suggested Artists" on the Music Preferences screen — the backend has
///   no artist catalog/search endpoint; `Profile.favorite_artist` is a
///   single free-text field, so selecting one of these just fills that
///   field in rather than backing a real multi-artist relation.
/// - "Instruments / Gear" on the Profile screen — `Profile` has no such
///   field; there's nothing per-user to show yet.
/// - Birthday and per-field privacy badges (Public/Friends/Private) shown
///   next to each detail row — `Profile` has no birthday field and no
///   per-field visibility setting (fields are grouped into fixed
///   public/friends/private tiers by convention, not user-configurable).
/// - Playlists and "Events Hosted" shown on the Profile screen — the
///   mobile app has no `Playlist`/`Event` API client yet, even though
///   the backend models exist (`backend/playlists`, `backend/events`).
/// - Votes/Playlists counts on the View Profile screen — there's no
///   aggregate endpoint for either. Deliberately NOT mocking "Listening
///   Now" or a "Recent Activity" feed there, since those would claim
///   real-time behavior about a specific person rather than read as
///   generic placeholder chrome.
library;

/// A fixed set of artist names offered as quick picks. Purely local — not
/// a search result and not tied to any backend catalog.
const mockSuggestedArtists = [
  'Daft Punk',
  'The Midnight',
  'Kavinsky',
  'Disclosure',
  'Tycho',
];

/// A fixed set of instruments/gear offered as placeholder chips on the
/// "Vibe Signature" card — purely local, not tied to any user or backend
/// field.
const mockInstruments = ['Roland Juno-106', 'Ableton Push', 'Moog Sub 37'];

/// The birthday shown on the Profile screen's Details section. Always
/// `null` today since `Profile` has no birthday field.
const String? mockBirthday = null;

class MockPlaylist {
  const MockPlaylist({
    required this.title,
    required this.subtitle,
    required this.trackCount,
  });

  final String title;
  final String subtitle;
  final int trackCount;
}

const mockPlaylists = [
  MockPlaylist(title: 'Midnight Drive Vol. 4', subtitle: 'Synthwave • Outrun • Electronic', trackCount: 12),
  MockPlaylist(title: 'Deep Focus State', subtitle: 'Dark Ambient • Drone', trackCount: 24),
];

class MockHostedEvent {
  const MockHostedEvent({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

const mockHostedEvents = [
  MockHostedEvent(title: 'Cybernetic Deep Dive', subtitle: '128 tuning in'),
  MockHostedEvent(title: 'Analog Resonance Vol. 3', subtitle: 'Starts in 2h'),
];

class MockProfileStats {
  const MockProfileStats({required this.votes, required this.playlists});

  final int votes;
  final int playlists;
}

/// Deterministic (not random) placeholder Votes/Playlists counts for the
/// View Profile screen, derived from [userId] so the same user always
/// shows the same numbers within a session.
MockProfileStats mockProfileStatsFor(int userId) => MockProfileStats(
  votes: 20 + (userId * 37) % 200,
  playlists: 5 + (userId * 13) % 100,
);
