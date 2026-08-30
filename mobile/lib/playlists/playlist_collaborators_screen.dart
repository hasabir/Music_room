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
  State<PlaylistCollaboratorsScreen> createState() => _PlaylistCollaboratorsScreenState();
}

class _PlaylistCollaboratorsScreenState extends State<PlaylistCollaboratorsScreen> {
  final _playlistApi = PlaylistApi();
  final _tokenStorage = TokenStorage();

  var _isLoading = true;
  String? _error;
  List<PlaylistCollaborator> _collaborators = const [];

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
      final collaborators = await _playlistApi.listCollaborators(widget.playlistId);
      if (!mounted) return;
      setState(() {
        _collaborators = collaborators;
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

  Future<void> _signOutAndReturnToWelcome() async {
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomeScreen()), (route) => false);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onAddCollaborators() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddCollaboratorsScreen(
          playlistId: widget.playlistId,
          existingCollaboratorIds: _collaborators.map((c) => c.collaborator).toSet(),
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
          style: TextStyle(fontFamily: 'Sora', color: _CollaboratorsColors.body),
        ),
        content: Text(
          '${collaborator.collaboratorEmail} will lose access to edit this playlist.',
          style: const TextStyle(color: _CollaboratorsColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel', style: TextStyle(color: _CollaboratorsColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _onRemove(PlaylistCollaborator collaborator) async {
    final confirmed = await _confirmRemove(collaborator);
    if (!confirmed) return;

    setState(() => _collaborators = _collaborators.where((c) => c.id != collaborator.id).toList());

    try {
      await _playlistApi.removeCollaborator(widget.playlistId, collaborator.collaborator);
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      _showMessage(error.message);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CollaboratorsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _Header(playlistTitle: widget.playlistTitle, onAdd: _onAddCollaborators),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _CollaboratorsColors.headline));
    }

    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }

    if (_collaborators.isEmpty) {
      return _EmptyState(onAdd: _onAddCollaborators);
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: _CollaboratorsColors.headline,
      backgroundColor: _CollaboratorsColors.card,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _collaborators.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final collaborator = _collaborators[index];
          return _CollaboratorRow(
            collaborator: collaborator,
            onRemove: () => _onRemove(collaborator),
          );
        },
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
            icon: const Icon(Icons.arrow_back_rounded, color: _CollaboratorsColors.body),
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
                  style: const TextStyle(fontSize: 12, color: _CollaboratorsColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onAdd,
            style: IconButton.styleFrom(backgroundColor: _CollaboratorsColors.card, shape: const CircleBorder()),
            icon: const Icon(Icons.person_add_alt_1_rounded, color: _CollaboratorsColors.body),
          ),
        ],
      ),
    );
  }
}

class _CollaboratorRow extends StatelessWidget {
  const _CollaboratorRow({required this.collaborator, required this.onRemove});

  final PlaylistCollaborator collaborator;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _CollaboratorsColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _CollaboratorsColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _CollaboratorsColors.border,
            child: Text(
              collaborator.collaboratorEmail.isNotEmpty
                  ? collaborator.collaboratorEmail[0].toUpperCase()
                  : '?',
              style: const TextStyle(color: _CollaboratorsColors.headline, fontWeight: FontWeight.w700),
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
            onPressed: onRemove,
            icon: const Icon(Icons.person_remove_rounded, color: Colors.redAccent, size: 20),
          ),
        ],
      ),
    );
  }
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
            const Icon(Icons.group_add_rounded, size: 40, color: _CollaboratorsColors.muted),
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
            const Icon(Icons.wifi_off_rounded, color: _CollaboratorsColors.muted, size: 40),
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
