import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api/api_client.dart';
import 'event_api.dart';
import 'event_detail_screen.dart';
import 'event_models.dart';

class _CreateEventColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// Full-screen "Create Event" flow, reachable from the "+" on
/// [EventsLandingScreen]. Every event is created with an explicit
/// visibility (`eventVisibilityPublic`/`Private`) and voting license
/// (`eventVotePermissionEveryone`/`InvitedOnly`/`LocationTimeRestricted`) —
/// picking the location/time license reveals the extra fields the backend
/// requires for it (`EventSerializer.validate()`): a time window plus a
/// venue center point and radius.
///
/// On success, navigates straight into the new event's detail screen
/// (`pushReplacement`) rather than popping back to the landing list —
/// [EventsLandingScreen] refreshes itself once the user backs out from
/// there instead.
class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _eventApi = EventApi();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _radiusController = TextEditingController(text: '200');

  var _visibility = eventVisibilityPublic;
  var _votePermission = eventVotePermissionEveryone;
  var _coverPreset = _EventCover.all.first.id;

  DateTime? _votingOpensAt;
  DateTime? _votingClosesAt;
  double? _venueCenterLatitude;
  double? _venueCenterLongitude;
  var _isLocating = false;

  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final now = DateTime.now();
    final initial = (isStart ? _votingOpensAt : _votingClosesAt) ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      // ignore: use_build_context_synchronously
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (isStart) {
        _votingOpensAt = combined;
      } else {
        _votingClosesAt = combined;
      }
    });
  }

  Future<void> _useCurrentLocation() async {
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
      setState(() {
        _venueCenterLatitude = position.latitude;
        _venueCenterLongitude = position.longitude;
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

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give your event a name.');
      return;
    }

    int? allowedDistanceMeters;
    if (_votePermission == eventVotePermissionLocationTimeRestricted) {
      allowedDistanceMeters = int.tryParse(_radiusController.text.trim());
      if (_votingOpensAt == null ||
          _votingClosesAt == null ||
          _venueCenterLatitude == null ||
          _venueCenterLongitude == null ||
          allowedDistanceMeters == null) {
        setState(
          () => _error = 'Set a start time, end time, location, and radius for a time & place restricted event.',
        );
        return;
      }
      if (!_votingClosesAt!.isAfter(_votingOpensAt!)) {
        setState(() => _error = 'The end time must be after the start time.');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final event = await _eventApi.createEvent(
        title: title,
        description: _descriptionController.text.trim(),
        coverPreset: _coverPreset,
        visibility: _visibility,
        votePermission: _votePermission,
        venueCenterLatitude: _venueCenterLatitude,
        venueCenterLongitude: _venueCenterLongitude,
        allowedDistanceMeters: allowedDistanceMeters,
        votingOpensAt: _votingOpensAt,
        votingClosesAt: _votingClosesAt,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: event.id)),
      );
    } on ApiException catch (error) {
      setState(() {
        _isSubmitting = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocationTimeRestricted =
        _votePermission == eventVotePermissionLocationTimeRestricted;

    return Scaffold(
      backgroundColor: _CreateEventColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: _CreateEventColors.body,
                    ),
                  ),
                  const Text(
                    'Music Room',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: _CreateEventColors.body,
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
                    'Create Event',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      color: _CreateEventColors.body,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Set the vibe and choose how your guests can vote.',
                    style: TextStyle(
                      fontSize: 14,
                      color: _CreateEventColors.muted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _FieldLabel('EVENT NAME'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    autofocus: true,
                    style: const TextStyle(color: _CreateEventColors.body),
                    decoration: _fieldDecoration(
                      'e.g. Neon Horizon Underground',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _FieldLabel('DESCRIPTION'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(color: _CreateEventColors.body),
                    decoration: _fieldDecoration(
                      'Describe the vibe, the music, and what to expect...',
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _FieldLabel('COVER'),
                  const SizedBox(height: 8),
                  _EventCoverPicker(
                    selectedPreset: _coverPreset,
                    onSelected: (preset) =>
                        setState(() => _coverPreset = preset),
                  ),
                  const SizedBox(height: 24),
                  const _FieldLabel('VISIBILITY'),
                  const SizedBox(height: 8),
                  _SegmentedChoice(
                    options: const {
                      eventVisibilityPublic: 'Public',
                      eventVisibilityPrivate: 'Private',
                    },
                    value: _visibility,
                    onChanged: (value) => setState(() => _visibility = value),
                  ),
                  const SizedBox(height: 24),
                  const _FieldLabel('VOTING LICENSE'),
                  const SizedBox(height: 8),
                  _SegmentedChoice(
                    options: const {
                      eventVotePermissionEveryone: 'Everyone can vote',
                      eventVotePermissionInvitedOnly: 'Invited only',
                      eventVotePermissionLocationTimeRestricted:
                          'Location & time restricted',
                    },
                    value: _votePermission,
                    onChanged: (value) =>
                        setState(() => _votePermission = value),
                    vertical: true,
                  ),
                  if (isLocationTimeRestricted) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _DateTimeField(
                            label: 'VOTING_OPENS_AT',
                            value: _votingOpensAt,
                            onTap: () => _pickDateTime(isStart: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DateTimeField(
                            label: 'VOTING_CLOSES_AT',
                            value: _votingClosesAt,
                            onTap: () => _pickDateTime(isStart: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _FieldLabel('ALLOWED_DISTANCE_METERS'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _radiusController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: _CreateEventColors.body),
                      decoration: _fieldDecoration('e.g. 200'),
                    ),
                    const SizedBox(height: 20),
                    const _FieldLabel(
                      'VENUE_CENTER_LATITUDE / VENUE_CENTER_LONGITUDE',
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isLocating ? null : _useCurrentLocation,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _CreateEventColors.tertiary,
                        side: const BorderSide(
                          color: _CreateEventColors.tertiary,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _isLocating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _CreateEventColors.tertiary,
                              ),
                            )
                          : const Icon(Icons.my_location_rounded, size: 18),
                      label: Text(
                        _venueCenterLatitude != null
                            ? '${_venueCenterLatitude!.toStringAsFixed(4)}, '
                                  '${_venueCenterLongitude!.toStringAsFixed(4)}'
                            : 'Use my current location',
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          colors: [
                            _CreateEventColors.gradientStart,
                            _CreateEventColors.gradientEnd,
                          ],
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Create Event',
                                    style: TextStyle(
                                      fontFamily: 'Sora',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
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
  hintStyle: const TextStyle(color: _CreateEventColors.muted),
  filled: true,
  fillColor: _CreateEventColors.card,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: _CreateEventColors.border),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: _CreateEventColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: _CreateEventColors.tertiary),
  ),
);

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
        color: _CreateEventColors.muted,
      ),
    );
  }
}

/// Event cover choices are bundled with the app so this picker is fast and
/// works without a network connection. Its preset id is saved as
/// `Event.cover_preset`, while the asset itself stays client-side.
class _EventCover {
  const _EventCover(this.id, this.assetPath, this.label, this.glowColor);

  final String id;
  final String assetPath;
  final String label;
  final Color glowColor;

  static const all = [
    _EventCover(
      'party',
      'assets/images/event_covers/party.jpg',
      'Party',
      Color(0xFFFF7A59),
    ),
    _EventCover(
      'night_vibe',
      'assets/images/event_covers/night_vibe.jpg',
      'Night vibe',
      Color(0xFF818CF8),
    ),
    _EventCover(
      'dj',
      'assets/images/event_covers/dj.jpg',
      'DJ',
      Color(0xFF2FD9F4),
    ),
    _EventCover(
      'summer_vibe',
      'assets/images/event_covers/summer_vibe.jpg',
      'Summer',
      Color(0xFFFBBF24),
    ),
    _EventCover(
      'rain',
      'assets/images/event_covers/rain.jpg',
      'Rain',
      Color(0xFF38BDF8),
    ),
    _EventCover(
      'coding_vibe',
      'assets/images/event_covers/coding_vibe.jpg',
      'Coding',
      Color(0xFF34D399),
    ),
    _EventCover(
      'after_dark',
      'assets/images/event_covers/pexels-baskincreativeco.jpg',
      'After dark',
      Color(0xFFA78BFA),
    ),
    _EventCover(
      'vibes',
      'assets/images/event_covers/image.jpg',
      'Vibes',
      Color(0xFFF472B6),
    ),
  ];
}

class _EventCoverPicker extends StatelessWidget {
  const _EventCoverPicker({
    required this.selectedPreset,
    required this.onSelected,
  });

  final String selectedPreset;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = _EventCover.all.firstWhere(
      (cover) => cover.id == selectedPreset,
    );

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            width: 116,
            height: 116,
            child: Image.asset(selected.assetPath, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          selected.label,
          style: const TextStyle(fontSize: 12, color: _CreateEventColors.muted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _EventCover.all.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final cover = _EventCover.all[index];
              final isSelected = cover.id == selectedPreset;
              return Semantics(
                button: true,
                selected: isSelected,
                label: 'Use ${cover.label} cover',
                child: GestureDetector(
                  onTap: () => onSelected(cover.id),
                  child: Container(
                    width: 64,
                    height: 64,
                    padding: EdgeInsets.all(isSelected ? 0 : 2.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: isSelected
                          ? Border.all(color: cover.glowColor, width: 2.5)
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: cover.glowColor.withValues(alpha: 0.45),
                                blurRadius: 10,
                              ),
                            ]
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isSelected ? 15 : 16),
                      child: Image.asset(cover.assetPath, fit: BoxFit.cover),
                    ),
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

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _CreateEventColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _CreateEventColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 16,
                  color: _CreateEventColors.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value == null ? 'Select' : _formatDateTime(value!),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: value == null
                          ? _CreateEventColors.muted
                          : _CreateEventColors.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.month}/${value.day}/${value.year} ${two(value.hour)}:${two(value.minute)}';
  }
}

/// A row (or stacked column, for longer labels) of mutually-exclusive
/// pill choices — used for visibility and the voting license.
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
        _Chip(
          label: entry.value,
          isSelected: entry.key == value,
          onTap: () => onChanged(entry.key),
        ),
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
  const _Chip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

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
          color: isSelected
              ? _CreateEventColors.tertiary.withValues(alpha: 0.15)
              : _CreateEventColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? _CreateEventColors.tertiary
                : _CreateEventColors.border,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: isSelected
                ? _CreateEventColors.tertiary
                : _CreateEventColors.muted,
          ),
        ),
      ),
    );
  }
}
