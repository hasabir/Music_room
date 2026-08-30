import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api/api_config.dart';
import 'playlist_models.dart';
import 'playlist_widgets.dart';

class PlaylistEditResult {
  const PlaylistEditResult({
    required this.title,
    required this.visibility,
    required this.editPermission,
    this.coverPath,
    this.coverPreset,
  });
  final String title;
  final String visibility;
  final String editPermission;
  final String? coverPath;
  final String? coverPreset;
}

class EditPlaylistScreen extends StatefulWidget {
  const EditPlaylistScreen({super.key, required this.playlist});
  final Playlist playlist;

  @override
  State<EditPlaylistScreen> createState() => _EditPlaylistScreenState();
}

class _EditPlaylistScreenState extends State<EditPlaylistScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.playlist.title);
  String? _coverPath;
  late String? _coverPreset = widget.playlist.coverPreset;
  late String _visibility = widget.playlist.visibility;
  late String _editPermission = widget.playlist.editPermission;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _chooseCover() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (image != null && mounted) {
      setState(() {
        _coverPath = image.path;
        _coverPreset = null;
      });
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      PlaylistEditResult(
        title: _title.text.trim(),
        visibility: _visibility,
        editPermission: _editPermission,
        coverPath: _coverPath,
        coverPreset: _coverPath == null ? _coverPreset : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _coverPath == null ? null : File(_coverPath!);
    final current = ApiConfig.resolveMediaUrl(widget.playlist.coverImageUrl);
    final selectedPreset = _coverPath == null
        ? PlaylistCoverPreset.byId(_coverPreset)
        : null;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E15),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E15),
        foregroundColor: const Color(0xFFE4E1EB),
        title: const Text(
          'Edit playlist',
          style: TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: [
              const _FormLabel('PLAYLIST NAME'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _title,
                maxLength: 100,
                style: const TextStyle(color: Color(0xFFE4E1EB)),
                decoration: _inputDecoration('Give your playlist a name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a playlist name.'
                    : null,
              ),
              const SizedBox(height: 24),
              const _FormLabel('COVER ART'),
              const SizedBox(height: 14),
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                        width: 136,
                        height: 136,
                        child: selected != null
                            ? Image.file(selected, fit: BoxFit.cover)
                            : selectedPreset != null
                            ? Image.asset(
                                selectedPreset.assetPath,
                                fit: BoxFit.cover,
                              )
                            : current != null
                            ? Image.network(current, fit: BoxFit.cover)
                            : PlaylistCoverThumb(
                                playlist: widget.playlist,
                                size: 136,
                                radius: 22,
                              ),
                      ),
                    ),
                    Material(
                      color: const Color(0xFF2FD9F4),
                      shape: const CircleBorder(),
                      child: IconButton(
                        onPressed: _chooseCover,
                        icon: const Icon(
                          Icons.edit_rounded,
                          color: Color(0xFF0E0E15),
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Use your own photo or pick a style below',
                  style: TextStyle(color: Color(0xFF908FA0), fontSize: 12),
                ),
              ),
              const SizedBox(height: 18),
              const _FormLabel('COVER STYLE'),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final preset in PlaylistCoverPreset.all)
                    _PresetButton(
                      preset: preset,
                      selected: _coverPath == null && _coverPreset == preset.id,
                      onTap: () => setState(() {
                        _coverPath = null;
                        _coverPreset = preset.id;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 30),
              const _FormLabel('VISIBILITY'),
              const SizedBox(height: 10),
              _ChoiceRow(
                options: const {
                  playlistVisibilityPublic: 'Public',
                  playlistVisibilityPrivate: 'Private',
                },
                value: _visibility,
                onChanged: (value) => setState(() {
                  _visibility = value;
                  if (value == playlistVisibilityPrivate &&
                      _editPermission == playlistEditPermissionEveryone) {
                    _editPermission = playlistEditPermissionInvitedOnly;
                  } else if (value == playlistVisibilityPublic &&
                      _editPermission == playlistEditPermissionOwnerOnly) {
                    _editPermission = playlistEditPermissionInvitedOnly;
                  }
                }),
              ),
              const SizedBox(height: 22),
              const _FormLabel('WHO CAN EDIT'),
              const SizedBox(height: 10),
              _ChoiceRow(
                options: _visibility == playlistVisibilityPrivate
                    ? const {
                        playlistEditPermissionOwnerOnly: 'Only me',
                        playlistEditPermissionInvitedOnly: 'Invited people',
                      }
                    : const {
                        playlistEditPermissionEveryone: 'Everyone',
                        playlistEditPermissionInvitedOnly: 'Invited people',
                      },
                value: _editPermission,
                onChanged: (value) => setState(() => _editPermission = value),
              ),
              const SizedBox(height: 30),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save changes'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: const Color(0xFF8083FF),
                  foregroundColor: const Color(0xFF0E0E15),
                  textStyle: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF908FA0),
      fontWeight: FontWeight.w700,
      fontSize: 11,
      letterSpacing: .9,
    ),
  );
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final PlaylistCoverPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      width: 54,
      height: 54,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? preset.glowColor : Colors.transparent,
          width: 2,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: preset.glowColor.withValues(alpha: .35),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(preset.assetPath, fit: BoxFit.cover),
      ),
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final option in options.entries) ...[
        Expanded(
          child: InkWell(
            onTap: () => onChanged(option.key),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value == option.key
                    ? const Color(0xFF8083FF)
                    : const Color(0xFF17161F),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: value == option.key
                      ? const Color(0xFF8083FF)
                      : const Color(0xFF2A2935),
                ),
              ),
              child: Text(
                option.value,
                style: TextStyle(
                  color: value == option.key
                      ? const Color(0xFF0E0E15)
                      : const Color(0xFFE4E1EB),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        if (option.key != options.keys.last) const SizedBox(width: 10),
      ],
    ],
  );
}

InputDecoration _inputDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: const TextStyle(color: Color(0xFF908FA0)),
  filled: true,
  fillColor: const Color(0xFF17161F),
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: Color(0xFF2A2935)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: Color(0xFF2FD9F4)),
  ),
);
