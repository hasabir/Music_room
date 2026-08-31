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
  Event? _event;
  var _isLoading = true;
  var _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final event = await _eventApi.getEvent(widget.eventId);
      if (!mounted) return;
      setState(() {
        _event = event;
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
