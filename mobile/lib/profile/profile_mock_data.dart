/// Placeholder data for parts of the Profile screen the backend doesn't
/// model yet.
///
/// Everything in this file is local/mock and clearly isolated here so it
/// can be swapped for real API data without touching the rest of the
/// profile feature:
/// - Friend "presence" (online status / current activity) — `Friendship`
///   and `User` have no such fields today.
/// - "Active Sessions" — the backend's `Event` model has no live/upcoming
///   distinction tied to a specific user yet.
/// - "Suggested Artists" on the Music Preferences screen — the backend has
///   no artist catalog/search endpoint; `Profile.favorite_artist` is a
///   single free-text field, so selecting one of these just fills that
///   field in rather than backing a real multi-artist relation.
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

/// A friend's presence, keyed by [Friend.id]. Cycles through a small set
/// of placeholder statuses so the UI has something to show per crew
/// member instead of looking uniform.
class MockPresence {
  const MockPresence({required this.isOnline, required this.activity});

  final bool isOnline;
  final String activity;

  static const _placeholders = [
    MockPresence(isOnline: true, activity: "In 'Midnight Lounge'"),
    MockPresence(isOnline: true, activity: 'Listening to Lofi'),
    MockPresence(isOnline: false, activity: 'Offline'),
  ];

  static MockPresence forFriendId(int id) =>
      _placeholders[id % _placeholders.length];
}

class MockSession {
  const MockSession({
    required this.title,
    required this.subtitle,
    required this.isLive,
  });

  final String title;
  final String subtitle;
  final bool isLive;
}

const mockActiveSession = MockSession(
  title: 'Cybernetic Deep Dive',
  subtitle: '128 tuning in',
  isLive: true,
);

const mockUpcomingSession = MockSession(
  title: 'Analog Resonance Vol. 3',
  subtitle: 'Starts in 2h',
  isLive: false,
);
