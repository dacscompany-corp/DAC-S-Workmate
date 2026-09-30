import 'package:flutter/material.dart';

import '../auth/worker_profile.dart';
import 'theme.dart';

/// 0B's shell: Home and Profile. Attendance, Requests and Work tabs arrive
/// with their stages; until 0C, Time In stays in DACS Attendance.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.worker, required this.versionName, required this.onSignOut});
  final WorkerProfile worker;
  final String versionName;
  final Future<void> Function() onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final w = widget.worker;
    final header = Row(children: [
      CircleAvatar(
        radius: 22,
        backgroundColor: WmColors.green,
        child: Text(w.initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(w.displayName ?? w.firstName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text(w.positionAndId, style: const TextStyle(fontSize: 13, color: WmColors.textMuted)),
        ]),
      ),
    ]);

    final home = ListView(padding: const EdgeInsets.all(20), children: [
      header,
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WmColors.brownTint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Keep using DACS Attendance for Time In and Time Out for now. '
          'It moves into WorkMate in a coming update, and the office will tell you when.',
          style: TextStyle(fontSize: 14.5, height: 1.4, color: Color(0xFF63491F)),
        ),
      ),
    ]);

    final profile = ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
      const SizedBox(height: 16),
      header,
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: widget.onSignOut,
        icon: const Icon(Icons.logout),
        label: const Text('Log out'),
      ),
      const SizedBox(height: 16),
      Text("DAC'S WorkMate ${widget.versionName} · By Dacs Building Design Services",
          style: const TextStyle(fontSize: 12.5, color: WmColors.textMeta)),
    ]);

    return Scaffold(
      body: SafeArea(child: _tab == 0 ? home : profile),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
