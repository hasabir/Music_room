import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'event_api.dart';
import 'event_models.dart';

class _SettingsColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const danger = Color(0xFFFFB4AB);
}

/// Host-only screen to change an event's [Event.status]
/// (live/closed/canceled) — reachable only from the settings icon
/// [EventDetailScreen]'s `_TopBar` shows when the signed-in user is the
/// host. Scoped to just status for now, not a general event editor —
/// that's all this was asked to cover.
class EventSettingsScreen extends StatefulWidget {
  const EventSettingsScreen({super.key, required this.eventId});
  final int eventId;

  @override
  State<EventSettingsScreen> createState() => _EventSettingsScreenState();
}

class _EventSettingsScreenState extends State<EventSettingsScreen> {
  final _eventApi = EventApi();
  final _maxParticipantsController = TextEditingController();
  Event? _event;
  var _isLoading = true;
  var _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxParticipantsController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final event = await _eventApi.getEvent(widget.eventId);
      if (!mounted) return;
      setState(() {
        _event = event;
        _maxParticipantsController.text = event.maxParticipants.toString();
        _isLoading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.message;
      });
    }
  }

  /// There is no "unlimited" option — a blank field resets to the
  /// default of 100 (the ceiling itself); otherwise must be between 2
  /// and 100, matching the backend's `MinValueValidator(2)`/
  /// `MaxValueValidator(100)`.
  Future<void> _saveMaxParticipants() async {
    if (_isSaving) return;
    final text = _maxParticipantsController.text.trim();
    final value = text.isEmpty ? 100 : int.tryParse(text);
    if (value == null || value < 2 || value > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a whole number between 2 and 100.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = await _eventApi.updateEvent(widget.eventId, maxParticipants: value);
      if (!mounted) return;
      setState(() {
        _event = updated;
        _maxParticipantsController.text = value.toString();
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Participant limit set to $value.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Soft-deletes the event (`Event.STATUS_DELETED` on the backend — the
  /// row, and every guest/member's access to see the "deleted" message,
  /// is kept). Pops this screen back to [EventDetailScreen] on success,
  /// which already refetches on return (see
  /// `_EventDetailScreenState._openEventSettings`) and will pick up the
  /// new status from that refetch to show the banner — no separate
  /// navigation needed here.
  Future<void> _deleteEvent() async {
    final event = _event;
    if (event == null || _isSaving) return;

    final confirmed = await _confirmDelete(event.title);
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _eventApi.deleteEvent(widget.eventId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<bool?> _confirmDelete(String eventTitle) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: _SettingsColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Delete this event?',
        style: TextStyle(fontFamily: 'Sora', color: _SettingsColors.body),
      ),
      content: Text(
        '"$eventTitle" will be permanently deleted. Every guest and member '
        'will see that it\'s been deleted the next time they open it. This '
        'cannot be undone.',
        style: const TextStyle(color: _SettingsColors.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Keep event',
            style: TextStyle(color: _SettingsColors.muted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Delete event',
            style: TextStyle(color: _SettingsColors.danger),
          ),
        ),
      ],
    ),
  );

  Future<void> _onSelectStatus(String status) async {
    final event = _event;
    if (event == null || event.status == status || _isSaving) return;

    if (status == eventStatusCanceled) {
      final confirmed = await _confirmCancel(event.title);
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = await _eventApi.updateEvent(widget.eventId, status: status);
      if (!mounted) return;
      setState(() {
        _event = updated;
        _isSaving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_confirmationMessage(status))));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  String _confirmationMessage(String status) => switch (status) {
    eventStatusClosed =>
      'Event closed — no new tracks can be suggested, but voting and entry stay open.',
    eventStatusCanceled => 'Event canceled — no one but you can enter it anymore.',
    _ => 'Event reopened.',
  };

  Future<bool?> _confirmCancel(String eventTitle) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: _SettingsColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Cancel this event?',
        style: TextStyle(fontFamily: 'Sora', color: _SettingsColors.body),
      ),
      content: Text(
        'No one will be able to enter "$eventTitle" anymore — not even '
        'guests or members who already joined. You can reopen it later by '
        'setting it back to Live.',
        style: const TextStyle(color: _SettingsColors.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Keep event',
            style: TextStyle(color: _SettingsColors.muted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Cancel event',
            style: TextStyle(color: _SettingsColors.danger),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _SettingsColors.background,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: _SettingsColors.body,
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Event Settings',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _SettingsColors.body,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    ),
  );

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _SettingsColors.tertiary),
      );
    }
    final event = _event;
    if (_error != null || event == null) {
      return Center(
        child: Text(
          _error ?? 'Could not load this event.',
          style: const TextStyle(color: _SettingsColors.muted),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        const Text(
          'STATUS',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: 11,
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
            color: _SettingsColors.muted,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          "Only you, as the host, can see or change this.",
          style: TextStyle(fontSize: 12, color: _SettingsColors.muted),
        ),
        const SizedBox(height: 12),
        _StatusOptionCard(
          icon: Icons.podcasts_rounded,
          title: 'Live',
          description: 'Open as normal — anyone with access can enter, '
              'suggest tracks, and vote.',
          color: _SettingsColors.tertiary,
          isSelected: event.status == eventStatusLive,
          isBusy: _isSaving,
          onTap: () => _onSelectStatus(eventStatusLive),
        ),
        const SizedBox(height: 10),
        _StatusOptionCard(
          icon: Icons.lock_clock_rounded,
          title: 'Closed',
          description: 'Entry and voting stay open, but no one can suggest '
              'new tracks anymore.',
          color: const Color(0xFFFBBF24),
          isSelected: event.status == eventStatusClosed,
          isBusy: _isSaving,
          onTap: () => _onSelectStatus(eventStatusClosed),
        ),
        const SizedBox(height: 10),
        _StatusOptionCard(
          icon: Icons.block_rounded,
          title: 'Canceled',
          description: 'Nobody can enter anymore, even guests or members '
              'who already joined. Only you keep access.',
          color: _SettingsColors.danger,
          isSelected: event.status == eventStatusCanceled,
          isBusy: _isSaving,
          onTap: () => _onSelectStatus(eventStatusCanceled),
        ),
        const SizedBox(height: 28),
        const Text(
          'PARTICIPANT LIMIT',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: 11,
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
            color: _SettingsColors.muted,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Cap on combined invited guests + joined members, between 2 '
          'and 100. There\'s no "unlimited" option — leave blank to reset '
          'to the default of 100.',
          style: TextStyle(fontSize: 12, color: _SettingsColors.muted),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _maxParticipantsController,
                enabled: !_isSaving,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: _SettingsColors.body),
                decoration: InputDecoration(
                  hintText: '100',
                  hintStyle: const TextStyle(color: _SettingsColors.muted),
                  filled: true,
                  fillColor: _SettingsColors.card,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _SettingsColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _SettingsColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _SettingsColors.tertiary),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: _isSaving ? null : _saveMaxParticipants,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _SettingsColors.tertiary,
                  side: const BorderSide(color: _SettingsColors.tertiary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '${event.participantCount} / ${event.maxParticipants} currently joined.',
            style: const TextStyle(fontSize: 12, color: _SettingsColors.muted),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'DANGER ZONE',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: 11,
            letterSpacing: 1,
            fontWeight: FontWeight.w800,
            color: _SettingsColors.danger,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Permanently deletes this event. Every guest and member will see '
          'it\'s been deleted the next time they open it.',
          style: TextStyle(fontSize: 12, color: _SettingsColors.muted),
        ),
        const SizedBox(height: 12),
        _DangerActionCard(
          icon: Icons.delete_forever_rounded,
          title: 'Delete Event',
          description: 'This cannot be undone.',
          isBusy: _isSaving,
          onTap: _deleteEvent,
        ),
      ],
    );
  }
}

class _StatusOptionCard extends StatelessWidget {
  const _StatusOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.isSelected,
    required this.isBusy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final bool isSelected;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isBusy ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.1)
              : _SettingsColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? color : _SettingsColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _SettingsColors.body,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _SettingsColors.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: isSelected ? color : _SettingsColors.border,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-way destructive action card — unlike [_StatusOptionCard], this
/// isn't a state you can be "in", so there's no selection checkmark, just
/// the icon/title/description and a busy state while the tap is pending.
class _DangerActionCard extends StatelessWidget {
  const _DangerActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isBusy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isBusy ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _SettingsColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _SettingsColors.danger, width: 1),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _SettingsColors.danger.withValues(alpha: 0.15),
              child: Icon(icon, color: _SettingsColors.danger, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _SettingsColors.danger,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _SettingsColors.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (isBusy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _SettingsColors.danger,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
