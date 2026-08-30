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
/// - "Events Hosted" on the Profile screen — the mobile app has no Event
///   API client yet, even though the backend model exists
///   (`backend/events`).
///
/// Playlists (both the Profile screen's "Playlists" tab and the View
/// Profile screen's Playlists count) are wired to the real
/// `lib/playlists/playlist_api.dart` client / `playlists_count` backend
/// field and no longer live here.
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

class MockHostedEvent {
  const MockHostedEvent({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

const mockHostedEvents = [
  MockHostedEvent(title: 'Cybernetic Deep Dive', subtitle: '128 tuning in'),
  MockHostedEvent(title: 'Analog Resonance Vol. 3', subtitle: 'Starts in 2h'),
];
