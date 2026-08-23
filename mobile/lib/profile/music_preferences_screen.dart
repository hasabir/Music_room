import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'profile_api.dart';
// import 'profile_mock_data.dart';
import 'profile_models.dart';

class _PrefsColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const genresLabel = Color(0xFFEA7FA6);
  // static const artistsLabel = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF6C6FF0);
  static const gradientEnd = Color(0xFFD44FA8);
  static const error = Color(0xFFFF8A8A);
}

/// Edits `Profile.favorite_genres` (a real multi-select array field) and
/// `Profile.favorite_artist` (a single free-text field on the backend, so
/// this screen treats "Suggested Artists" as a single-select shortcut for
/// filling that one field rather than a real multi-artist relation — see
/// `profile_mock_data.dart` for why the suggestion list itself is local).
/// Saves via `PATCH /api/v1/profile/me/`.
class MusicPreferencesScreen extends StatefulWidget {
  const MusicPreferencesScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<MusicPreferencesScreen> createState() => _MusicPreferencesScreenState();
}

class _MusicPreferencesScreenState extends State<MusicPreferencesScreen> {
  final _profileApi = ProfileApi();
  final _searchController = TextEditingController();

  late final Set<String> _selectedGenres;
  late String? _selectedArtist;
  late final List<String> _artistOptions;

  String _query = '';
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedGenres = widget.profile.favoriteGenres.toSet();
    _selectedArtist = widget.profile.favoriteArtist.isEmpty ? null : widget.profile.favoriteArtist;

    // Keep an existing custom favorite artist selectable even if it isn't
    // one of the curated suggestions, so saving doesn't silently drop it.
    // _artistOptions = [
    //   ...mockSuggestedArtists,
    //   if (_selectedArtist != null && !mockSuggestedArtists.contains(_selectedArtist))
    //     _selectedArtist!,
    // ];

    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final updated = await _profileApi.updateMyProfile(
        favoriteGenres: _selectedGenres.toList(),
        favoriteArtist: _selectedArtist ?? '',
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final genreEntries = musicGenreLabels.entries
        .where((entry) => entry.value.toLowerCase().contains(_query))
        .toList();
    // final artists = _artistOptions
    //     .where((artist) => artist.toLowerCase().contains(_query))
    //     .toList();

    return Scaffold(
      backgroundColor: _PrefsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: _PrefsColors.headline),
                  ),
                  const Text(
                    'Music Preferences',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: _PrefsColors.headline,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  const Text(
                    'SEARCH GENRES',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: _PrefsColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: _PrefsColors.body, fontFamily: 'Sora'),
                    decoration: InputDecoration(
                      hintText: 'Type here...',
                      hintStyle: const TextStyle(color: _PrefsColors.muted),
                      prefixIcon: const Icon(Icons.search_rounded, color: _PrefsColors.muted),
                      filled: true,
                      fillColor: _PrefsColors.card,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: const BorderSide(color: _PrefsColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: const BorderSide(color: _PrefsColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: const BorderSide(color: _PrefsColors.headline),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'TOP GENRES',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: _PrefsColors.genresLabel,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: genreEntries.map((entry) {
                      final isSelected = _selectedGenres.contains(entry.key);
                      return _SelectableChip(
                        label: entry.value,
                        isSelected: isSelected,
                        onTap: () => setState(() {
                          if (isSelected) {
                            _selectedGenres.remove(entry.key);
                          } else {
                            _selectedGenres.add(entry.key);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),
                  // const Text(
                  //   'SUGGESTED ARTISTS',
                  //   style: TextStyle(
                  //     fontFamily: 'Sora',
                  //     fontSize: 12,
                  //     fontWeight: FontWeight.w800,
                  //     letterSpacing: 0.8,
                  //     color: _PrefsColors.artistsLabel,
                  //   ),
                  // ),
                  // const SizedBox(height: 12),
                  // Wrap(
                  //   spacing: 10,
                  //   runSpacing: 10,
                  //   children: artists.map((artist) {
                  //     final isSelected = artist == _selectedArtist;
                  //     return _SelectableChip(
                  //       label: artist,
                  //       isSelected: isSelected,
                  //       onTap: () => setState(() {
                  //         _selectedArtist = isSelected ? null : artist;
                  //       }),
                  //     );
                  //   }).toList(),
                  // ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: _PrefsColors.error)),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [_PrefsColors.gradientStart, _PrefsColors.gradientEnd],
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Preferences',
                                style: TextStyle(
                                  fontFamily: 'Sora',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: isSelected ? null : _PrefsColors.card,
          gradient: isSelected
              ? const LinearGradient(
                  colors: [_PrefsColors.gradientStart, _PrefsColors.gradientEnd],
                )
              : null,
          border: isSelected ? null : Border.all(color: _PrefsColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: isSelected ? Colors.white : _PrefsColors.body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
