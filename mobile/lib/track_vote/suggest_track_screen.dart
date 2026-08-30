import 'package:flutter/material.dart';

/// Navigation target for the Up Next action. The search-and-add flow is built
/// separately; keeping the route real now lets Event Detail link to it.
class SuggestTrackScreen extends StatelessWidget {
  const SuggestTrackScreen({super.key, required this.eventId});
  final int eventId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0E0E15),
    appBar: AppBar(
      backgroundColor: const Color(0xFF0E0E15),
      foregroundColor: const Color(0xFFE4E1EB),
      title: const Text('Suggest a Track'),
    ),
    body: const Center(
      child: Text(
        'Track search is coming next.',
        style: TextStyle(color: Color(0xFF908FA0)),
      ),
    ),
  );
}
