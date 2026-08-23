import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'profile_api.dart';
import 'profile_models.dart';

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

/// Lets the signed-in user edit their own profile, grouped by the
/// backend's visibility tiers (see `Profile` model / `UserProfileView`):
/// public (`display_name`, `bio`), friends-only (`location`,
/// `favorite_artist`), and private (`phone_number`). Email is shown for
/// context but isn't editable here — the backend has no endpoint to
/// change it outside the verified-email flow. Saves via
/// `PATCH /api/v1/profile/me/`.
///
/// Favorite genres are edited on the separate Music Preferences screen.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile, required this.email});

  final UserProfile profile;
  final String email;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _profileApi = ProfileApi();

  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late final TextEditingController _locationController;
  late final TextEditingController _favoriteArtistController;
  late final TextEditingController _phoneController;

  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _locationController = TextEditingController(text: widget.profile.location);
    _favoriteArtistController = TextEditingController(text: widget.profile.favoriteArtist);
    _phoneController = TextEditingController(text: widget.profile.phoneNumber);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _favoriteArtistController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onEditPhoto() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Photo upload coming soon.')));
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final updated = await _profileApi.updateMyProfile(
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        location: _locationController.text.trim(),
        favoriteArtist: _favoriteArtistController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
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
    return Scaffold(
      backgroundColor: _EditColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(title: 'Edit Profile'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Center(
                    child: _AvatarEditor(
                      imageUrl: widget.profile.profileImageUrl,
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
                    children: [
                      _EditField(
                        label: 'DISPLAY NAME',
                        controller: _displayNameController,
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 18),
                      _EditField(
                        label: 'TAGLINE',
                        controller: _bioController,
                        icon: Icons.format_quote_rounded,
                        maxLines: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _SectionDivider(
                    icon: Icons.people_outline_rounded,
                    label: 'FRIENDS ONLY',
                    color: _EditColors.friendsBadge,
                  ),
                  const SizedBox(height: 16),
                  _FieldsCard(
                    children: [
                      _EditField(
                        label: 'LOCATION',
                        controller: _locationController,
                        icon: Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 18),
                      _EditField(
                        label: 'FAVORITE ARTIST',
                        controller: _favoriteArtistController,
                        icon: Icons.star_border_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const _SectionDivider(
                    icon: Icons.lock_outline_rounded,
                    label: 'PRIVATE',
                    color: _EditColors.privateBadge,
                  ),
                  const SizedBox(height: 16),
                  _FieldsCard(
                    children: [
                      _ReadOnlyField(
                        label: 'EMAIL ADDRESS',
                        value: widget.email,
                        icon: Icons.mail_outline_rounded,
                      ),
                      const SizedBox(height: 18),
                      _EditField(
                        label: 'PHONE NUMBER',
                        controller: _phoneController,
                        icon: Icons.phone_iphone_rounded,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: _EditColors.error)),
                  ],
                  const SizedBox(height: 28),
                  _SaveButton(isSaving: _isSaving, onPressed: _save, label: 'Save Changes'),
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
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: _EditColors.headline),
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
  const _AvatarEditor({required this.imageUrl, required this.onEdit});

  final String? imageUrl;
  final VoidCallback onEdit;

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
              child: imageUrl != null
                  ? Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _AvatarFallback(),
                    )
                  : const _AvatarFallback(),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: onEdit,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _EditColors.card,
                  border: Border.fromBorderSide(BorderSide(color: _EditColors.border)),
                ),
                child: const Icon(Icons.edit_rounded, size: 16, color: _EditColors.headline),
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

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.icon, required this.label, required this.color});

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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
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
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboardType;

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
            filled: true,
            fillColor: _EditColors.background,
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
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

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value, required this.icon});

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
                  style: const TextStyle(color: _EditColors.muted, fontFamily: 'Sora'),
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
  const _SaveButton({required this.isSaving, required this.onPressed, required this.label});

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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
          ),
          child: isSaving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
