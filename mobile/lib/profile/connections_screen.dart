import 'package:flutter/material.dart';

import 'profile_api.dart';
import 'profile_models.dart';

class _ConnectionsColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const border = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
}

/// Lists the signed-in user's accepted friends ("Crew"), backed by
/// `GET /api/v1/profile/friends/`.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _profileApi = ProfileApi();

  late Future<List<Friend>> _friendsFuture;

  @override
  void initState() {
    super.initState();
    _friendsFuture = _profileApi.getFriends();
  }

  Future<void> _refresh() async {
    final future = _profileApi.getFriends();
    setState(() {
      _friendsFuture = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ConnectionsColors.background,
      appBar: AppBar(
        backgroundColor: _ConnectionsColors.background,
        elevation: 0,
        title: const Text(
          'Connections',
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            color: _ConnectionsColors.body,
          ),
        ),
      ),
      body: FutureBuilder<List<Friend>>(
        future: _friendsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _ConnectionsColors.headline),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not load your connections.',
                      style: TextStyle(color: _ConnectionsColors.body),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final friends = snapshot.data ?? const [];
          if (friends.isEmpty) {
            return const Center(
              child: Text(
                'No connections yet.',
                style: TextStyle(color: _ConnectionsColors.muted),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: _ConnectionsColors.headline,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: friends.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final friend = friends[index];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _ConnectionsColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _ConnectionsColors.border),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: _ConnectionsColors.border,
                        child: Text(
                          friend.firstName.isNotEmpty
                              ? friend.firstName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: _ConnectionsColors.headline,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        friend.fullName,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _ConnectionsColors.body,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
