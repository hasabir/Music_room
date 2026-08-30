import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api/api_client.dart';
import 'playlist_api.dart';
import 'playlist_models.dart';

class _CreatePlaylistColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// Full-screen "Create Playlist" flow, reachable from the "+" on
/// [PlaylistListScreen]. Every playlist is created with an explicit
/// visibility (`playlistVisibilityPublic`/`Private`) and collaboration
/// rule (`playlistEditPermissionEveryone`/`InvitedOnly`) — there's no way
/// to skip past them, since the backend enforces both regardless
/// (`Playlist.visibility`/`edit_permission`, defaulting to public/everyone
/// if this screen didn't send them).
class CreatePlaylistScreen extends StatefulWidget {
  const CreatePlaylistScreen({super.key});

  @override
  State<CreatePlaylistScreen> createState() => _CreatePlaylistScreenState();
}

class _CreatePlaylistScreenState extends State<CreatePlaylistScreen> {
  final _playlistApi = PlaylistApi();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  var _visibility = playlistVisibilityPublic;
  var _editPermission = playlistEditPermissionEveryone;

  /// Defaults to the first preset so the playlist always has a good-looking
  /// cover out of the box, rather than starting blank.
  String? _coverPreset = PlaylistCoverPreset.all.first.id;

  /// Set instead of [_coverPreset] once the user uploads their own photo —
  /// the two are mutually exclusive, same as on the backend.
  XFile? _customCoverImage;

  var _isSubmitting = false;
  String? _error;

  /// The edit-permission choices that make sense for the current
  /// [_visibility]. A public playlist is visible to everyone, so "everyone
  /// can edit" vs. "invite only" is a real distinction. A private playlist
  /// is already invite-only to even *see* — so that same "invite only"
  /// wording would just describe the default access rule twice. The real
  /// choice there is narrower: only the owner, or everyone already invited.
  Map<String, String> get _editPermissionOptions => _visibility == playlistVisibilityPrivate
      ? const {
          playlistEditPermissionOwnerOnly: 'Only me',
          playlistEditPermissionInvitedOnly: 'Everyone invited',
        }
      : const {
          playlistEditPermissionEveryone: 'Everyone can edit',
          playlistEditPermissionInvitedOnly: 'Invite only',
        };

  void _onVisibilityChanged(String value) {
    setState(() {
      _visibility = value;
      if (!_editPermissionOptions.containsKey(_editPermission)) {
        _editPermission = value == playlistVisibilityPrivate
            ? playlistEditPermissionInvitedOnly
            : playlistEditPermissionEveryone;
      }
    });
  }

  Future<void> _pickCustomCoverImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() {
      _customCoverImage = file;
      _coverPreset = null;
    });
  }

  void _selectCoverPreset(String presetId) {
    setState(() {
      _coverPreset = presetId;
      _customCoverImage = null;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give your playlist a title.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      var playlist = await _playlistApi.createPlaylist(
        title: title,
        description: _descriptionController.text.trim(),
        visibility: _visibility,
        editPermission: _editPermission,
        coverPreset: _customCoverImage == null ? _coverPreset : null,
      );

      final customImage = _customCoverImage;
      if (customImage != null) {
        playlist = await _playlistApi.uploadPlaylistCoverImage(playlist.id, customImage.path);
      }

      if (!mounted) return;
      Navigator.of(context).pop(playlist);
    } on ApiException catch (error) {
      setState(() {
        _isSubmitting = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CreatePlaylistColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: _CreatePlaylistColors.body),
                  ),
                  const Text(
                    'Music Room',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _CreatePlaylistColors.body,
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
                    'Create Playlist',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      color: _CreatePlaylistColors.body,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Define the vibe and set the rules for your new room.',
                    style: TextStyle(fontSize: 14, color: _CreatePlaylistColors.muted),
                  ),
                  const SizedBox(height: 28),
                  const _FieldLabel('PLAYLIST NAME'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    style: const TextStyle(color: _CreatePlaylistColors.body),
                    decoration: _fieldDecoration('e.g. Late Night Drives'),
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('DESCRIPTION'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(color: _CreatePlaylistColors.body),
                    decoration: _fieldDecoration('Describe the mood...'),
                  ),
                  const SizedBox(height: 24),
                  const _FieldLabel('COVER'),
                  const SizedBox(height: 8),
                  _CoverPicker(
                    coverPreset: _coverPreset,
                    customImage: _customCoverImage,
                    onPickCustomImage: _pickCustomCoverImage,
                    onSelectPreset: _selectCoverPreset,
                  ),
                  const SizedBox(height: 24),
                  const _FieldLabel('VISIBILITY'),
                  const SizedBox(height: 8),
                  _SegmentedChoice(
                    options: const {playlistVisibilityPublic: 'Public', playlistVisibilityPrivate: 'Private'},
                    value: _visibility,
                    onChanged: _onVisibilityChanged,
                  ),
                  const SizedBox(height: 24),
                  const _FieldLabel('WHO CAN EDIT'),
                  const SizedBox(height: 8),
                  Text(
                    _visibility == playlistVisibilityPrivate
                        ? "It's private, so only you and the people you invite can see it at all — pick who "
                              'among you can also make changes.'
                        : 'Anyone can see a public playlist. Choose whether anyone can also edit it, or just '
                              'people you invite.',
                    style: const TextStyle(fontSize: 12.5, color: _CreatePlaylistColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  _SegmentedChoice(
                    options: _editPermissionOptions,
                    value: _editPermission,
                    onChanged: (value) => setState(() => _editPermission = value),
                    vertical: true,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          colors: [_CreatePlaylistColors.gradientStart, _CreatePlaylistColors.gradientEnd],
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Create Playlist',
                                    style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700, fontSize: 15),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.add_rounded, size: 20),
                                ],
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

InputDecoration _fieldDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: _CreatePlaylistColors.muted),
  filled: true,
  fillColor: _CreatePlaylistColors.card,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: _CreatePlaylistColors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: _CreatePlaylistColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: _CreatePlaylistColors.tertiary),
  ),
);

/// Lets the owner pick a playlist cover one of two ways: tap the big
/// preview to upload their own photo, or tap one of the 5 built-in looks
/// below it. The two are mutually exclusive — picking one clears the other.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.coverPreset,
    required this.customImage,
    required this.onPickCustomImage,
    required this.onSelectPreset,
  });

  final String? coverPreset;
  final XFile? customImage;
  final VoidCallback onPickCustomImage;
  final ValueChanged<String> onSelectPreset;

  @override
  Widget build(BuildContext context) {
    final selectedPreset = customImage == null ? PlaylistCoverPreset.byId(coverPreset) : null;

    return Column(
      children: [
        GestureDetector(
          onTap: onPickCustomImage,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  width: 116,
                  height: 116,
                  child: customImage != null
                      ? Image.file(File(customImage!.path), fit: BoxFit.cover)
                      : _PresetSwatch(preset: selectedPreset, iconSize: 44),
                ),
              ),
              Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: _CreatePlaylistColors.tertiary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_photo_alternate_rounded, size: 16, color: Colors.black),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          customImage != null ? 'Tap to change your photo' : 'Tap to upload your own photo',
          style: const TextStyle(fontSize: 12, color: _CreatePlaylistColors.muted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: PlaylistCoverPreset.all.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final preset = PlaylistCoverPreset.all[index];
              final isSelected = customImage == null && coverPreset == preset.id;
              return GestureDetector(
                onTap: () => onSelectPreset(preset.id),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: isSelected ? Border.all(color: preset.glowColor, width: 2.5) : null,
                    boxShadow: isSelected
                        ? [BoxShadow(color: preset.glowColor.withValues(alpha: 0.45), blurRadius: 10)]
                        : null,
                  ),
                  padding: EdgeInsets.all(isSelected ? 0 : 2.5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isSelected ? 15 : 16),
                    child: _PresetSwatch(preset: preset, iconSize: 22),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({required this.preset, required this.iconSize});

  final PlaylistCoverPreset? preset;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (preset != null) {
      return Image.asset(preset!.assetPath, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_CreatePlaylistColors.gradientStart, _CreatePlaylistColors.gradientEnd],
        ),
      ),
      child: Center(child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: iconSize)),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Sora',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: _CreatePlaylistColors.muted,
      ),
    );
  }
}

/// A row (or stacked column, for longer labels) of mutually-exclusive
/// pill choices — used for both visibility and collaboration rules.
class _SegmentedChoice extends StatelessWidget {
  const _SegmentedChoice({
    required this.options,
    required this.value,
    required this.onChanged,
    this.vertical = false,
  });

  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final chips = [
      for (final entry in options.entries)
        _Chip(label: entry.value, isSelected: entry.key == value, onTap: () => onChanged(entry.key)),
    ];

    if (vertical) {
      return Column(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: chips[i]),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: chips[i]),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _CreatePlaylistColors.tertiary.withValues(alpha: 0.15) : _CreatePlaylistColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _CreatePlaylistColors.tertiary : _CreatePlaylistColors.border,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: isSelected ? _CreatePlaylistColors.tertiary : _CreatePlaylistColors.muted,
          ),
        ),
      ),
    );
  }
}
