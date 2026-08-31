import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/api/api_client.dart';
import 'event_api.dart';
import 'event_detail_screen.dart';
import 'event_models.dart';
import 'location_label.dart';

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
/// visibility (`eventVisibilityPublic`/`Private`). A **public** event also
/// gets a voting license (`eventVotePermissionEveryone`/`InvitedOnly` —
/// who's allowed to vote at all) — the "WHO CAN VOTE" section is hidden
/// entirely for a **private** event, since only the host and invited
/// guests can even see a private event at all (`can_user_see_event`), so
/// "everyone can vote" and "invited only" would describe the exact same
/// audience there; the choice only means something once strangers can
/// reach the event in the first place. Independent of that (and shown
/// either way): two restriction toggles layer on top — a time window
/// and/or a venue radius. Any combination is valid — e.g. invited-only
/// *and* time-restricted *and* location-restricted all at once — since
/// the three are orthogonal on the backend (see DECISIONS.md, "Event
/// voting restrictions: split location_time_restricted into two
/// composable booleans"). Enabling a restriction reveals the extra fields
/// the backend requires for it (`EventSerializer.validate()`): time needs
/// a start/end window, location needs a venue center point and radius —
/// each toggle's fields are validated independently of the other's.
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
  final _maxParticipantsController = TextEditingController(text: '100');

  var _visibility = eventVisibilityPublic;
  var _votePermission = eventVotePermissionEveryone;
  var _coverPreset = EventCoverPreset.all.first.id;

  var _timeRestrictionEnabled = false;
  var _locationRestrictionEnabled = false;

  DateTime? _votingOpensAt;
  DateTime? _votingClosesAt;
  double? _venueCenterLatitude;
  double? _venueCenterLongitude;

  /// Human-readable ("Neighborhood, City, Country") reverse-geocoded label
  /// for [_venueCenterLatitude]/[_venueCenterLongitude], shown on the
  /// locate button instead of raw coordinates — see [reverseGeocodeLabel].
  /// `null` while resolving, or if reverse geocoding failed/found nothing,
  /// in which case the raw coordinates are shown as a fallback.
  String? _venueLabel;
  var _isLocating = false;

  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _radiusController.dispose();
    _maxParticipantsController.dispose();
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
        _venueLabel = null;
      });
      // Best-effort — a failed/empty reverse geocode just leaves the raw
      // coordinates shown (see the label's fallback below); it never
      // blocks using the location that was already captured.
      final label = await reverseGeocodeLabel(position.latitude, position.longitude);
      if (mounted) setState(() => _venueLabel = label);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error is String ? error : 'Could not get your location.',
      );
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  /// While resolving, shows "Locating…"; once a coordinate is captured,
  /// prefers the reverse-geocoded [_venueLabel] and only falls back to raw
  /// coordinates if that lookup failed or found nothing.
  String _venueButtonLabel() {
    if (_venueCenterLatitude == null) return 'Use my current location';
    if (_venueLabel != null) return _venueLabel!;
    if (_isLocating) return 'Locating…';
    return '${_venueCenterLatitude!.toStringAsFixed(4)}, '
        '${_venueCenterLongitude!.toStringAsFixed(4)}';
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give your event a name.');
      return;
    }

    // Time and location are independent restrictions, each validated
    // (and reported) on its own — mirrors EventSerializer.validate() on
    // the backend, which never mentions one toggle's fields when only
    // the other is enabled.
    if (_timeRestrictionEnabled) {
      if (_votingOpensAt == null || _votingClosesAt == null) {
        setState(
          () => _error = 'Set a start and end time for the time-restricted vote.',
        );
        return;
      }
      if (!_votingClosesAt!.isAfter(_votingOpensAt!)) {
        setState(() => _error = 'The end time must be after the start time.');
        return;
      }
    }

    int? allowedDistanceMeters;
    if (_locationRestrictionEnabled) {
      allowedDistanceMeters = int.tryParse(_radiusController.text.trim());
      if (_venueCenterLatitude == null ||
          _venueCenterLongitude == null ||
          allowedDistanceMeters == null) {
        setState(
          () => _error = 'Set a venue location and radius for the location-restricted vote.',
        );
        return;
      }
    }

    // There's no "unlimited" option — a blank field (the host cleared the
    // pre-filled default) falls back to 100, the ceiling itself.
    final maxParticipantsText = _maxParticipantsController.text.trim();
    final maxParticipants = maxParticipantsText.isEmpty ? 100 : int.tryParse(maxParticipantsText);
    if (maxParticipants == null || maxParticipants < 2 || maxParticipants > 100) {
      setState(
        () => _error = 'Participant limit must be between 2 and 100.',
      );
      return;
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
        timeRestrictionEnabled: _timeRestrictionEnabled,
        locationRestrictionEnabled: _locationRestrictionEnabled,
        venueCenterLatitude: _locationRestrictionEnabled ? _venueCenterLatitude : null,
        venueCenterLongitude: _locationRestrictionEnabled ? _venueCenterLongitude : null,
        allowedDistanceMeters: allowedDistanceMeters,
        votingOpensAt: _timeRestrictionEnabled ? _votingOpensAt : null,
        votingClosesAt: _timeRestrictionEnabled ? _votingClosesAt : null,
        maxParticipants: maxParticipants,
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
                    onChanged: (value) => setState(() {
                      _visibility = value;
                      // Once private, only the host and invited guests can
                      // even see the event at all (can_user_see_event), so
                      // "everyone can vote" and "invited only" describe the
                      // exact same audience — the choice is meaningless
                      // and the section below is hidden entirely. Reset it
                      // back to the default so a later switch to public
                      // doesn't surface a stale "invited only" nobody
                      // actually chose while this was hidden.
                      if (value == eventVisibilityPrivate) {
                        _votePermission = eventVotePermissionEveryone;
                      }
                    }),
                  ),
                  if (_visibility == eventVisibilityPublic) ...[
                    const SizedBox(height: 24),
                    const _FieldLabel('WHO CAN VOTE'),
                    const SizedBox(height: 8),
                    _SegmentedChoice(
                      options: const {
                        eventVotePermissionEveryone: 'Everyone can vote',
                        eventVotePermissionInvitedOnly: 'Invited only',
                      },
                      value: _votePermission,
                      onChanged: (value) =>
                          setState(() => _votePermission = value),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _FieldLabel('VOTING RESTRICTIONS'),
                  const SizedBox(height: 4),
                  Text(
                    'Optional, and independent of each other and of who '
                    'can vote above — turn on either, both, or neither.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _CreateEventColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _RestrictionToggle(
                    icon: Icons.schedule_rounded,
                    title: 'Time window',
                    subtitle: 'Only allow voting between a start and end time.',
                    value: _timeRestrictionEnabled,
                    onChanged: (value) =>
                        setState(() => _timeRestrictionEnabled = value),
                  ),
                  if (_timeRestrictionEnabled) ...[
                    const SizedBox(height: 16),
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
                  ],
                  const SizedBox(height: 16),
                  _RestrictionToggle(
                    icon: Icons.location_on_rounded,
                    title: 'Venue location',
                    subtitle: 'Only allow voting within a radius of the venue.',
                    value: _locationRestrictionEnabled,
                    onChanged: (value) =>
                        setState(() => _locationRestrictionEnabled = value),
                  ),
                  if (_locationRestrictionEnabled) ...[
                    const SizedBox(height: 16),
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
                      label: Text(_venueButtonLabel()),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _FieldLabel('PARTICIPANT LIMIT'),
                  const SizedBox(height: 4),
                  const Text(
                    'Cap on combined invited guests + joined members, '
                    'between 2 and 100. There\'s no "unlimited" option.',
                    style: TextStyle(
                      fontSize: 12,
                      color: _CreateEventColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _maxParticipantsController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: _CreateEventColors.body),
                    decoration: _fieldDecoration('100'),
                  ),
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

class _EventCoverPicker extends StatelessWidget {
  const _EventCoverPicker({
    required this.selectedPreset,
    required this.onSelected,
  });

  final String selectedPreset;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = EventCoverPreset.all.firstWhere(
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
            itemCount: EventCoverPreset.all.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final cover = EventCoverPreset.all[index];
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

/// An on/off card for one of the two independent voting restrictions
/// (time window, venue location) — unlike [_SegmentedChoice], this isn't
/// mutually exclusive with anything: both restrictions can be on
/// together, or either alone, or neither, regardless of who-can-vote.
class _RestrictionToggle extends StatelessWidget {
  const _RestrictionToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: value
              ? _CreateEventColors.tertiary.withValues(alpha: 0.1)
              : _CreateEventColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value
                ? _CreateEventColors.tertiary
                : _CreateEventColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: value
                  ? _CreateEventColors.tertiary
                  : _CreateEventColors.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _CreateEventColors.body,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _CreateEventColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: _CreateEventColors.tertiary,
            ),
          ],
        ),
      ),
    );
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
