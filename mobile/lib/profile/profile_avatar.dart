import 'package:flutter/material.dart';

import 'profile_models.dart';

/// Renders whichever avatar source is currently active — a preset from
/// the bundled grid, a social sign-in photo URL, or a custom-uploaded
/// image URL — without the caller needing to know which one it is. Pass
/// [UserProfile.avatar]/[avatarType] or [OtherUserProfile.avatar]/
/// [avatarType] straight through.
///
/// Callers keep owning the surrounding shape/decoration (circle clip,
/// gradient border, size) and their own [fallback] styling — this only
/// decides what image, if any, goes inside it.
class ProfileAvatarImage extends StatelessWidget {
  const ProfileAvatarImage({
    super.key,
    required this.avatar,
    required this.avatarType,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String? avatar;
  final String avatarType;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final avatar = this.avatar;
    if (avatar == null || avatar.isEmpty) return fallback;

    if (avatarType == profileAvatarTypePreset) {
      final preset = AvatarPreset.byId(avatar);
      if (preset == null) return fallback;
      return Image.asset(
        preset.assetPath,
        fit: fit,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return Image.network(avatar, fit: fit, errorBuilder: (_, _, _) => fallback);
  }
}
