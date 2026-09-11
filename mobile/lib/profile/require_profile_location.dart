import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_api.dart';
import '../core/api/api_client.dart';
import 'profile_api.dart';
import 'profile_models.dart';

bool hasProfileCoordinates(UserProfile profile) =>
    profile.locationFromGps &&
    profile.location.trim().isNotEmpty &&
    profile.locationLatitude != null &&
    profile.locationLongitude != null;

Future<UserProfile?> requireProfileLocation(
  BuildContext context, {
  required String action,
  UserProfile? profile,
}) async {
  final saved = profile ?? await ProfileApi().getMyProfile();
  if (!context.mounted) return null;
  if (hasProfileCoordinates(saved)) return saved;
  return showDialog<UserProfile>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LocationDialog(action: action, profile: saved),
  );
}

class _LocationDialog extends StatefulWidget {
  const _LocationDialog({required this.action, required this.profile});
  final String action;
  final UserProfile profile;

  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Turn on location services, then try again.';
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'Allow location access in your device settings, then try again.';
      }
      if (permission == LocationPermission.denied) {
        throw 'Location access is needed to continue. Please allow it and try again.';
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      final profile = await ProfileApi().updateMyProfile(
        location: '${position.latitude}, ${position.longitude}',
        locationLatitude: position.latitude,
        locationLongitude: position.longitude,
      );
      if (!mounted) return;
      if (!hasProfileCoordinates(profile)) {
        setState(
          () => _error = 'Could not save your GPS location. Please try again.',
        );
        return;
      }
      Navigator.of(context).pop(profile);
    } on String catch (message) {
      if (mounted) setState(() => _error = message);
    } on SessionExpiredException {
      if (mounted) {
        setState(
          () => _error =
              'Your session expired. Sign in again to save your location.',
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save your location. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      icon: Icon(
        Icons.location_on_outlined,
        color: Theme.of(context).colorScheme.primary,
        size: 32,
      ),
      title: const Text('Set your location'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To ${widget.action}, we need your device GPS location. We will save it to your profile for next time.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location_rounded),
          label: Text(_saving ? 'Locating...' : 'Use GPS location'),
        ),
      ],
    ),
  );
}
