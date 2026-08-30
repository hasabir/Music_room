import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import 'add_collaborators_screen.dart';
import 'playlist_api.dart';
import 'playlist_models.dart';

class _CollaboratorsColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
}

/// A playlist's collaborator list, reachable only by the playlist's owner
/// from the detail screen (`POST/GET/DELETE .../collaborators/` are all
/// owner-only on the backend, aside from listing — see
/// `backend/playlists/views_collaborators.py`).
///
/// Follows the same list-screen-plus-search-screen split as Friends:
/// this screen lists and removes; [AddCollaboratorsScreen] (mirroring
/// `add_friends_screen.dart`'s search pattern) handles inviting.
class PlaylistCollaboratorsScreen extends StatefulWidget {
  const PlaylistCollaboratorsScreen({
    super.key,
    required this.playlistId,
    required this.playlistTitle,
  });

  final int playlistId;
  final String playlistTitle;

  @override
  State<PlaylistCollaboratorsScreen> createState() =>
      _PlaylistCollaboratorsScreenState();
}

class _PlaylistCollaboratorsScreenState
    extends State<PlaylistCollaboratorsScreen> {
  final _playlistApi = PlaylistApi();
  final _tokenStorage = TokenStorage();

  var _isLoading = true;
  String? _error;
  List<PlaylistCollaborator> _collaborators = const [];
  List<PlaylistAccessRequest> _pendingRequests = const [];
  final _decidingRequestIds = <int>{};
  final _savingCollaboratorIds = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _playlistApi.listCollaborators(widget.playlistId),
        _playlistApi.listAccessRequests(widget.playlistId),
      ]);
      if (!mounted) return;
      setState(() {
        _collaborators = results[0] as List<PlaylistCollaborator>;
        _pendingRequests = (results[1] as List<PlaylistAccessRequest>)
            .where((r) => r.status == playlistAccessRequestPending)
            .toList();
        _isLoading = false;
      });
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _onDecideRequest(
    PlaylistAccessRequest request, {
    required bool approve,
  }) async {
    setState(() => _decidingRequestIds.add(request.id));
    try {
      await _playlistApi.decideAccessRequest(
        widget.playlistId,
        request.id,
        approve: approve,
      );
      if (!mounted) return;
      setState(() {
        _pendingRequests = _pendingRequests
            .where((r) => r.id != request.id)
            .toList();
        _decidingRequestIds.remove(request.id);
      });
      if (approve) _load();
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _decidingRequestIds.remove(request.id));
      _showMessage(error.message);
    }
  }

  Future<void> _signOutAndReturnToWelcome() async {
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onAddCollaborators() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddCollaboratorsScreen(
          playlistId: widget.playlistId,
          existingCollaboratorIds: _collaborators
              .map((c) => c.collaborator)
              .toSet(),
        ),
      ),
    );
    _load();
  }

  Future<bool> _confirmRemove(PlaylistCollaborator collaborator) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _CollaboratorsColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Remove Collaborator?',
          style: TextStyle(
            fontFamily: 'Sora',
            color: _CollaboratorsColors.body,
          ),
        ),
        content: Text(
          '${collaborator.collaboratorEmail} will lose access to edit this playlist.',
          style: const TextStyle(color: _CollaboratorsColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _CollaboratorsColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _onRemove(PlaylistCollaborator collaborator) async {
    final confirmed = await _confirmRemove(collaborator);
    if (!confirmed) return;

    setState(
      () => _collaborators = _collaborators
          .where((c) => c.id != collaborator.id)
          .toList(),
    );

    try {
      await _playlistApi.removeCollaborator(
        widget.playlistId,
        collaborator.collaborator,
      );
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      _showMessage(error.message);
      _load();
    }
  }

  Future<void> _updatePermissions(
    PlaylistCollaborator collaborator, {
    bool? canAddSongs,
    bool? canReorderSongs,
    bool? canManageCollaborators,
  }) async {
    setState(() => _savingCollaboratorIds.add(collaborator.id));
    try {
      final updated = await _playlistApi.updateCollaboratorPermissions(
        widget.playlistId,
        collaborator.collaborator,
        canAddSongs: canAddSongs ?? collaborator.canAddSongs,
        canReorderSongs: canReorderSongs ?? collaborator.canReorderSongs,
        canManageCollaborators:
            canManageCollaborators ?? collaborator.canManageCollaborators,
      );
      if (!mounted) return;
      setState(() {
        _collaborators = _collaborators
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
        _savingCollaboratorIds.remove(collaborator.id);
      });
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _savingCollaboratorIds.remove(collaborator.id));
      _showMessage(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CollaboratorsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              playlistTitle: widget.playlistTitle,
              onAdd: _onAddCollaborators,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _CollaboratorsColors.headline),
      );
    }

    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }

    if (_collaborators.isEmpty && _pendingRequests.isEmpty) {
      return _EmptyState(onAdd: _onAddCollaborators);
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: _CollaboratorsColors.headline,
      backgroundColor: _CollaboratorsColors.card,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          if (_pendingRequests.isNotEmpty) ...[
            const _SectionLabel('ACCESS REQUESTS'),
            const SizedBox(height: 10),
            for (final request in _pendingRequests) ...[
              _AccessRequestRow(
                request: request,
                isDeciding: _decidingRequestIds.contains(request.id),
                onApprove: () => _onDecideRequest(request, approve: true),
                onDeny: () => _onDecideRequest(request, approve: false),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            const _SectionLabel('COLLABORATORS'),
            const SizedBox(height: 10),
          ],
          if (_collaborators.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No collaborators yet.',
                style: TextStyle(color: _CollaboratorsColors.muted),
              ),
            )
          else
            for (final collaborator in _collaborators) ...[
              _CollaboratorRow(
                collaborator: collaborator,
                isSaving: _savingCollaboratorIds.contains(collaborator.id),
                onRemove: () => _onRemove(collaborator),
                onAddSongsChanged: (value) =>
                    _updatePermissions(collaborator, canAddSongs: value),
                onReorderChanged: (value) =>
                    _updatePermissions(collaborator, canReorderSongs: value),
                onManageChanged: (value) => _updatePermissions(
                  collaborator,
                  canManageCollaborators: value,
                ),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.playlistTitle, required this.onAdd});

  final String playlistTitle;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: _CollaboratorsColors.body,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Collaborators',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: _CollaboratorsColors.body,
                  ),
                ),
                Text(
                  playlistTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _CollaboratorsColors.muted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAdd,
            style: IconButton.styleFrom(
              backgroundColor: _CollaboratorsColors.card,
              shape: const CircleBorder(),
            ),
            icon: const Icon(
              Icons.person_add_alt_1_rounded,
              color: _CollaboratorsColors.body,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

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
        color: _CollaboratorsColors.muted,
      ),
    );
  }
}

class _AccessRequestRow extends StatelessWidget {
  const _AccessRequestRow({
    required this.request,
    required this.isDeciding,
    required this.onApprove,
    required this.onDeny,
  });

  final PlaylistAccessRequest request;
  final bool isDeciding;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _CollaboratorsColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _CollaboratorsColors.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _CollaboratorsColors.border,
            child: Text(
              request.requesterEmail.isNotEmpty
                  ? request.requesterEmail[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: _CollaboratorsColors.headline,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              request.requesterEmail,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _CollaboratorsColors.body,
              ),
            ),
          ),
          if (isDeciding)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _CollaboratorsColors.headline,
              ),
            )
          else ...[
            IconButton(
              onPressed: onDeny,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
            ),
            IconButton(
              onPressed: onApprove,
              icon: const Icon(
                Icons.check_rounded,
                color: _CollaboratorsColors.tertiary,
                size: 20,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CollaboratorRow extends StatelessWidget {
  const _CollaboratorRow({
    required this.collaborator,
    required this.isSaving,
    required this.onRemove,
    required this.onAddSongsChanged,
    required this.onReorderChanged,
    required this.onManageChanged,
  });

  final PlaylistCollaborator collaborator;
  final bool isSaving;
  final VoidCallback onRemove;
  final ValueChanged<bool> onAddSongsChanged;
  final ValueChanged<bool> onReorderChanged;
  final ValueChanged<bool> onManageChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _CollaboratorsColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _CollaboratorsColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _CollaboratorsColors.border,
                child: Text(
                  collaborator.collaboratorEmail.isNotEmpty
                      ? collaborator.collaboratorEmail[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: _CollaboratorsColors.headline,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  collaborator.collaboratorEmail,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _CollaboratorsColors.body,
                  ),
                ),
              ),
              IconButton(
                onPressed: isSaving ? null : onRemove,
                icon: const Icon(
                  Icons.person_remove_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
              ),
            ],
          ),
          const Divider(color: _CollaboratorsColors.border),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                'PERMISSIONS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _CollaboratorsColors.muted,
                ),
              ),
            ),
          ),
          _PermissionSwitch(
            icon: Icons.library_add_rounded,
            label: 'Can add or remove songs',
            description: 'Build and curate the playlist',
            value: collaborator.canAddSongs,
            enabled: !isSaving,
            onChanged: onAddSongsChanged,
          ),
          _PermissionSwitch(
            icon: Icons.reorder_rounded,
            label: 'Can reorder songs',
            description: 'Change the playlist order',
            value: collaborator.canReorderSongs,
            enabled: !isSaving,
            onChanged: onReorderChanged,
          ),
          _PermissionSwitch(
            icon: Icons.group_add_rounded,
            label: 'Can invite and remove people',
            description: 'Manage the collaborator list',
            value: collaborator.canManageCollaborators,
            enabled: !isSaving,
            onChanged: onManageChanged,
          ),
          if (isSaving)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                color: _CollaboratorsColors.tertiary,
              ),
            ),
        ],
      ),
    );
  }
}

class _PermissionSwitch extends StatelessWidget {
  const _PermissionSwitch({
    required this.icon,
    required this.label,
    required this.description,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: const EdgeInsets.symmetric(vertical: 1),
    secondary: Icon(
      icon,
      color: value ? _CollaboratorsColors.tertiary : _CollaboratorsColors.muted,
    ),
    title: Text(
      label,
      style: const TextStyle(color: _CollaboratorsColors.body, fontSize: 13),
    ),
    subtitle: Text(
      description,
      style: const TextStyle(color: _CollaboratorsColors.muted, fontSize: 11),
    ),
    value: value,
    onChanged: enabled ? onChanged : null,
    activeThumbColor: _CollaboratorsColors.tertiary,
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.group_add_rounded,
              size: 40,
              color: _CollaboratorsColors.muted,
            ),
            const SizedBox(height: 12),
            const Text(
              'No collaborators yet.',
              style: TextStyle(color: _CollaboratorsColors.body),
            ),
            const SizedBox(height: 4),
            const Text(
              'Invite someone to help edit this playlist.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _CollaboratorsColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onAdd,
              style: OutlinedButton.styleFrom(
                foregroundColor: _CollaboratorsColors.tertiary,
                side: const BorderSide(color: _CollaboratorsColors.tertiary),
              ),
              child: const Text('Invite a Collaborator'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: _CollaboratorsColors.muted,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _CollaboratorsColors.body),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => onRetry(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _CollaboratorsColors.tertiary,
                side: const BorderSide(color: _CollaboratorsColors.tertiary),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
