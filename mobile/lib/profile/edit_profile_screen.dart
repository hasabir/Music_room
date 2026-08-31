import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api/api_client.dart';
import '../track_vote/location_label.dart';
import 'profile_api.dart';
import 'profile_avatar.dart';
import 'profile_models.dart';

enum _AvatarEditChoice { camera, gallery, presetGrid }

class _EditColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const label = Color(0xFF6F6D82);
  static const gradientStart = Color(0xFF6C6FF0);
  static const gradientEnd = Color(0xFF2FD9F4);
  static const publicBadge = Color(0xFFC0C1FF);
  static const friendsBadge = Color(0xFF2FD9F4);
  static const privateBadge = Color(0xFFEA7FA6);
  static const error = Color(0xFFFF8A8A);
}

/// Interposes an 18px gap between each widget in [rows] — used when
/// building a `_FieldsCard`'s children from a variable-length list.
List<Widget> _joinWithSpacing(List<Widget> rows) => [
  for (var i = 0; i < rows.length; i++) ...[
    if (i > 0) const SizedBox(height: 18),
    rows[i],
  ],
];

/// Lets the signed-in user edit their own profile. `display_name` is
/// always public and the email is always private — neither is
/// configurable. Every other field (`bio`, `location`, `favorite_artist`,
/// `phone_number`, plus the "Listening Activity" feed exposed via
/// `GET /profile/<id>/activity/`) has a per-field visibility picker
/// (public/friends-only/private) backed by `Profile.field_visibility`
/// (see `Profile` model / `UserProfileView`). Email is shown for context
/// but isn't editable here — the backend has no endpoint to change it
/// outside the verified-email flow. Saves via `PATCH /api/v1/profile/me/`.
///
/// Favorite genres are edited on the separate Music Preferences screen.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.email,
  });

  final UserProfile profile;
  final String email;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _profileApi = ProfileApi();
  final _imagePicker = ImagePicker();

  late final TextEditingController _displayNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;
  late final TextEditingController _favoriteArtistController;
  late final TextEditingController _phoneController;

  /// Tracks the profile photo separately from the rest of the form: a new
  /// photo uploads (and is reflected here) as soon as it's picked, rather
  /// than waiting for "Save Changes" — so the back button also needs to
  /// hand this back to the caller even if the user never taps Save.
  late UserProfile _latestProfile;
  late Map<String, String> _visibility;
  late DateTime? _birthday;

  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  bool _isLocating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _latestProfile = widget.profile;
    _visibility = Map.of(widget.profile.fieldVisibility);
    _birthday = widget.profile.birthday;
    _displayNameController = TextEditingController(
      text: widget.profile.displayName,
    );
    _usernameController = TextEditingController(text: widget.profile.username);
    _bioController = TextEditingController(text: widget.profile.bio);
    _locationController = TextEditingController(text: widget.profile.location);
    _favoriteArtistController = TextEditingController(
      text: widget.profile.favoriteArtist,
    );
    _phoneController = TextEditingController(text: widget.profile.phoneNumber);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _favoriteArtistController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Fills [_locationController] from the device's current GPS position,
  /// reverse-geocoded into a short "City, Country" label — mirroring
  /// `create_event_screen.dart`'s `_useCurrentLocation` (same permission
  /// flow, same `reverseGeocodeLabel` call), except there's no separate
  /// coordinate state to keep here: `Profile.location` only ever stores
  /// free text, so the resolved label (or, if reverse geocoding fails,
  /// the raw coordinates) is written straight into the text field the
  /// user could otherwise have typed into by hand.
  Future<void> _useCurrentLocationForProfile() async {
    setState(() {
      _isLocating = true;
      _error = null;
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Turn on location services to use this.';
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw 'Location permission was denied.';
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;

      final label = await reverseGeocodeLabel(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _locationController.text =
            label ??
            '${position.latitude.toStringAsFixed(4)}, '
                '${position.longitude.toStringAsFixed(4)}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is String ? error : 'Could not get your location.',
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _onEditPhoto() async {
    final choice = await showModalBottomSheet<_AvatarEditChoice>(
      context: context,
      backgroundColor: _EditColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: _EditColors.headline,
              ),
              title: const Text(
                'Take a photo',
                style: TextStyle(color: _EditColors.body),
              ),
              onTap: () =>
                  Navigator.of(context).pop(_AvatarEditChoice.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: _EditColors.headline,
              ),
              title: const Text(
                'Choose from gallery',
                style: TextStyle(color: _EditColors.body),
              ),
              onTap: () =>
                  Navigator.of(context).pop(_AvatarEditChoice.gallery),
            ),
            ListTile(
              leading: const Icon(
                Icons.grid_view_rounded,
                color: _EditColors.headline,
              ),
              title: const Text(
                'Choose a preset avatar',
                style: TextStyle(color: _EditColors.body),
              ),
              onTap: () =>
                  Navigator.of(context).pop(_AvatarEditChoice.presetGrid),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == _AvatarEditChoice.presetGrid) {
      await _onChoosePresetAvatar();
      return;
    }

    final picked = await _imagePicker.pickImage(
      source: choice == _AvatarEditChoice.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final updated = await _profileApi.uploadProfileImage(picked.path);
      if (!mounted) return;
      setState(() => _latestProfile = updated);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _onChoosePresetAvatar() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _EditColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AvatarPresetGrid(
        currentPresetId: _latestProfile.avatarType == profileAvatarTypePreset
            ? _latestProfile.avatarPresetId
            : null,
      ),
    );
    if (selected == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final updated = await _profileApi.updateMyProfile(
        avatarPresetId: selected,
      );
      if (!mounted) return;
      setState(() => _latestProfile = updated);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final updated = await _profileApi.updateMyProfile(
        username: _usernameController.text.trim(),
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        location: _locationController.text.trim(),
        favoriteArtist: _favoriteArtistController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        birthday: _birthday,
        clearBirthday: _birthday == null,
        fieldVisibility: _visibility,
      );
      if (!mounted) return;
      setState(() {
        _latestProfile = updated;
        _visibility = Map.of(updated.fieldVisibility);
        _birthday = updated.birthday;
      });
      Navigator.of(context).pop(updated);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Order the configurable rows appear in within whichever section they
  /// currently belong to.
  static const _configurableFieldOrder = [
    'bio',
    'location',
    'favorite_artist',
    'phone_number',
    'birthday',
    'favorite_genres',
    'activity',
  ];

  /// The rows currently set to [tier], in a stable order — as the user
  /// changes a field's visibility, it moves out of one section's list and
  /// into another's.
  List<Widget> _rowsForTier(String tier) => [
    for (final key in _configurableFieldOrder)
      if (_visibility[key] == tier) _rowFor(key),
  ];

  Widget _rowFor(String key) {
    void onChanged(String tier) => setState(() => _visibility[key] = tier);

    return switch (key) {
      'bio' => _EditField(
        label: 'BIO',
        controller: _bioController,
        icon: Icons.format_quote_rounded,
        maxLines: 3,
        trailing: _VisibilityDropdown(
          value: _visibility['bio']!,
          onChanged: onChanged,
        ),
      ),
      'location' => _EditField(
        label: 'LOCATION',
        controller: _locationController,
        icon: Icons.location_on_outlined,
        trailing: _VisibilityDropdown(
          value: _visibility['location']!,
          onChanged: onChanged,
        ),
        suffixIcon: IconButton(
          tooltip: 'Use my current location',
          onPressed: _isLocating ? null : _useCurrentLocationForProfile,
          icon: _isLocating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _EditColors.headline,
                  ),
                )
              : const Icon(
                  Icons.my_location_rounded,
                  size: 20,
                  color: _EditColors.headline,
                ),
        ),
      ),
      'favorite_artist' => _EditField(
        label: 'FAVORITE ARTIST',
        controller: _favoriteArtistController,
        icon: Icons.star_border_rounded,
        trailing: _VisibilityDropdown(
          value: _visibility['favorite_artist']!,
          onChanged: onChanged,
        ),
      ),
      'phone_number' => _EditField(
        label: 'PHONE NUMBER',
        controller: _phoneController,
        icon: Icons.phone_iphone_rounded,
        keyboardType: TextInputType.phone,
        trailing: _VisibilityDropdown(
          value: _visibility['phone_number']!,
          onChanged: onChanged,
        ),
      ),
      'birthday' => _BirthdayField(
        birthday: _birthday,
        onTap: _pickBirthday,
        trailing: _VisibilityDropdown(
          value: _visibility['birthday']!,
          onChanged: onChanged,
        ),
      ),
      'favorite_genres' => _SimpleVisibilityRow(
        icon: Icons.music_note_rounded,
        label: 'Favorite Genres',
        value: _visibility['favorite_genres']!,
        onChanged: onChanged,
      ),
      _ => _SimpleVisibilityRow(
        icon: Icons.graphic_eq_rounded,
        label: 'Listening Activity',
        value: _visibility['activity']!,
        onChanged: onChanged,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _EditColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: 'Edit Profile',
              onBack: () => Navigator.of(context).pop(_latestProfile),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Center(
                    child: _AvatarEditor(
                      avatar: _latestProfile.avatar,
                      avatarType: _latestProfile.avatarType,
                      isUploading: _isUploadingPhoto,
                      onEdit: _onEditPhoto,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionDivider(
                    icon: Icons.public_rounded,
                    label: 'PUBLIC',
                    color: _EditColors.publicBadge,
                  ),
                  const SizedBox(height: 16),
                  _FieldsCard(
                    children: _joinWithSpacing([
                      _EditField(
                        label: 'USERNAME',
                        controller: _usernameController,
                        icon: Icons.alternate_email_rounded,
                      ),
                      _EditField(
                        label: 'DISPLAY NAME',
                        controller: _displayNameController,
                        icon: Icons.person_outline_rounded,
                      ),
                      ..._rowsForTier('public'),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  const _SectionDivider(
                    icon: Icons.people_outline_rounded,
                    label: 'FRIENDS ONLY',
                    color: _EditColors.friendsBadge,
                  ),
                  const SizedBox(height: 16),
                  _FieldsCard(
                    children: _rowsForTier('friends').isEmpty
                        ? const [
                            Text(
                              'No fields are set to Friends Only.',
                              style: TextStyle(
                                fontFamily: 'Sora',
                                fontSize: 13,
                                color: _EditColors.muted,
                              ),
                            ),
                          ]
                        : _joinWithSpacing(_rowsForTier('friends')),
                  ),
                  const SizedBox(height: 24),
                  const _SectionDivider(
                    icon: Icons.lock_outline_rounded,
                    label: 'PRIVATE',
                    color: _EditColors.privateBadge,
                  ),
                  const SizedBox(height: 16),
                  _FieldsCard(
                    children: _joinWithSpacing([
                      _ReadOnlyField(
                        label: 'EMAIL ADDRESS',
                        value: widget.email,
                        icon: Icons.mail_outline_rounded,
                      ),
                      ..._rowsForTier('private'),
                    ]),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: _EditColors.error),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _SaveButton(
                    isSaving: _isSaving,
                    onPressed: _save,
                    label: 'Save Changes',
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

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: _EditColors.headline,
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: _EditColors.body,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.avatar,
    required this.avatarType,
    required this.onEdit,
    this.isUploading = false,
  });

  final String? avatar;
  final String avatarType;
  final VoidCallback onEdit;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      height: 128,
      child: Stack(
        children: [
          Container(
            width: 128,
            height: 128,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [_EditColors.gradientStart, _EditColors.gradientEnd],
              ),
            ),
            child: ClipOval(
              child: ProfileAvatarImage(
                avatar: avatar,
                avatarType: avatarType,
                fallback: const _AvatarFallback(),
              ),
            ),
          ),
          if (isUploading)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x99000000),
                ),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: isUploading ? null : onEdit,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _EditColors.card,
                  border: Border.fromBorderSide(
                    BorderSide(color: _EditColors.border),
                  ),
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  size: 16,
                  color: _EditColors.headline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _EditColors.card,
      child: Icon(Icons.person_rounded, color: _EditColors.muted, size: 52),
    );
  }
}

/// The avatar-grid picker, opened from [_EditProfileScreenState._onEditPhoto]
/// alongside the existing camera/gallery options. Pops the chosen preset's
/// id, or nothing if dismissed.
class _AvatarPresetGrid extends StatelessWidget {
  const _AvatarPresetGrid({required this.currentPresetId});

  final String? currentPresetId;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose an avatar',
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _EditColors.body,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            children: [
              for (final preset in AvatarPreset.all)
                _AvatarPresetTile(
                  preset: preset,
                  isSelected: preset.id == currentPresetId,
                  onTap: () => Navigator.of(context).pop(preset.id),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AvatarPresetTile extends StatelessWidget {
  const _AvatarPresetTile({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final AvatarPreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? preset.glowColor : _EditColors.border,
          width: isSelected ? 3 : 1,
        ),
      ),
      child: ClipOval(
        child: Image.asset(preset.assetPath, fit: BoxFit.cover),
      ),
    ),
  );
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: _EditColors.border)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: Divider(color: _EditColors.border)),
      ],
    );
  }
}

class _FieldsCard extends StatelessWidget {
  const _FieldsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _EditColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _EditColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _EditField extends StatelessWidget {
  const _EditField({
    required this.label,
    required this.controller,
    required this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.trailing,
    this.suffixIcon,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final Widget? trailing;

  /// Rendered as the text field's `suffixIcon` — an optional action
  /// button distinct from [trailing] (which sits in the label row, e.g.
  /// the visibility dropdown). Used by the location field's "use current
  /// location" GPS button.
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _EditColors.label,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: const TextStyle(color: _EditColors.body, fontFamily: 'Sora'),
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: Icon(icon, size: 18, color: _EditColors.muted),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: _EditColors.background,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 14,
              horizontal: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _EditColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _EditColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _EditColors.headline),
            ),
          ),
        ),
      ],
    );
  }
}

/// The 3 visibility tiers a configurable field can be set to, matching
/// `Profile.VISIBILITY_CHOICES` on the backend.
const _visibilityTiers = ['public', 'friends', 'private'];

(String, IconData, Color) _visibilityTierDisplay(String tier) => switch (tier) {
  'public' => ('Public', Icons.public_rounded, _EditColors.publicBadge),
  'private' => ('Private', Icons.lock_rounded, _EditColors.privateBadge),
  _ => ('Friends Only', Icons.people_alt_rounded, _EditColors.friendsBadge),
};

/// A pill button showing a field's current visibility tier; tapping it
/// opens a menu to pick a different one. Purely local state — the change
/// isn't sent to the backend until "Save Changes" is tapped.
class _VisibilityDropdown extends StatelessWidget {
  const _VisibilityDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = _visibilityTierDisplay(value);

    return PopupMenuButton<String>(
      color: _EditColors.card,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final tier in _visibilityTiers) _visibilityMenuItem(tier),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _visibilityMenuItem(String tier) {
    final (label, icon, color) = _visibilityTierDisplay(tier);
    final isSelected = tier == value;
    return PopupMenuItem(
      value: tier,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(color: _EditColors.body)),
          ),
          if (isSelected)
            const Icon(
              Icons.check_rounded,
              size: 16,
              color: _EditColors.headline,
            ),
        ],
      ),
    );
  }
}

/// Row for the "Listening Activity" feed (`GET /profile/<id>/activity/`):
/// its visibility tier, matching the other configurable fields. Unlike a
/// text field it has no value of its own to edit — it's just an access
/// gate on an existing endpoint.
/// A visibility-configurable row with no field of its own to edit inline
/// — the value lives (and is edited) elsewhere, this row only carries the
/// label and its [_VisibilityDropdown]. Used for "Listening Activity"
/// (derived from the user's own actions) and "Favorite Genres" (edited on
/// the separate Music Preferences screen, reachable from the "Vibe
/// Signature" card on the profile itself).
class _SimpleVisibilityRow extends StatelessWidget {
  const _SimpleVisibilityRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _EditColors.muted),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: _EditColors.body,
            ),
          ),
        ),
        _VisibilityDropdown(value: value, onChanged: onChanged),
      ],
    );
  }
}

/// Tapping opens a date picker rather than a text field — otherwise laid
/// out like [_EditField] so it sits consistently alongside the other
/// configurable rows.
class _BirthdayField extends StatelessWidget {
  const _BirthdayField({
    required this.birthday,
    required this.onTap,
    required this.trailing,
  });

  final DateTime? birthday;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'BIRTHDAY',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _EditColors.label,
                ),
              ),
            ),
            trailing,
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: _EditColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _EditColors.border),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, right: 12),
                  child: Icon(
                    Icons.cake_outlined,
                    size: 18,
                    color: _EditColors.muted,
                  ),
                ),
                Text(
                  birthday != null ? formatBirthday(birthday!) : 'Not set',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    color: birthday != null
                        ? _EditColors.body
                        : _EditColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: _EditColors.label,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _EditColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: _EditColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: _EditColors.muted,
                    fontFamily: 'Sora',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.isSaving,
    required this.onPressed,
    required this.label,
  });

  final bool isSaving;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          gradient: const LinearGradient(
            colors: [_EditColors.gradientStart, _EditColors.gradientEnd],
          ),
        ),
        child: ElevatedButton(
          onPressed: isSaving ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(27),
            ),
          ),
          child: isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
