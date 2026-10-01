import 'package:flutter/material.dart';

import '../attendance/attendance_services.dart';
import '../attendance/domain/work_date.dart';
import '../attendance/flow/time_flow_controller.dart';
import '../attendance/flow/time_flow_screen.dart';
import '../attendance/history/history_controller.dart';
import '../attendance/history/history_screen.dart';
import '../attendance/home/home_controller.dart';
import '../attendance/home/home_screen.dart';
import '../attendance/ui/attendance_copy.dart';
import '../auth/worker_profile.dart';
import 'theme.dart';
import 'worker_header.dart';

/// The signed-in app: Home, History and Profile, and the four-step Time In /
/// Time Out flow launched from Home. The flow is MODAL (no tabs while
/// recording). Requests and Work tabs arrive with Stage 1.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.worker,
    required this.versionName,
    required this.onSignOut,
    required this.services,
  });

  final WorkerProfile worker;
  final String versionName;
  final Future<void> Function() onSignOut;
  final AttendanceServices services;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  TimeFlowController? _flow;
  Bilingual? _exitNotice;
  late final HomeController _home;
  late final HistoryController _history;

  @override
  void initState() {
    super.initState();
    final s = widget.services;
    _home = HomeController(attendance: s.attendance, scheduler: s.scheduler);
    _history = HistoryController(attendance: s.attendance);
    WidgetsBinding.instance.addObserver(this);
    _home.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flow?.abandon();
    _flow?.dispose();
    _home.dispose();
    _history.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the app is when a worker can see "Not sent yet": re-read today and
    // send what waits. Not while recording — the camera's permission prompts
    // pause and resume the app too.
    if (state == AppLifecycleState.resumed && _flow == null) _home.refresh();
  }

  void _startFlow(TimeDirection direction) {
    final s = widget.services;
    setState(() {
      _exitNotice = null;
      _flow = TimeFlowController(direction: direction, attendance: s.attendance, device: s.device, trustedNow: s.trustedNow)
        ..loadProjects();
    });
  }

  void _endFlow({Bilingual? notice}) {
    final ended = _flow;
    setState(() {
      _flow = null;
      _exitNotice = notice;
    });
    // After this frame: the flow screen listens to it until it is gone.
    WidgetsBinding.instance.addPostFrameCallback((_) => ended?.dispose());
    _home.refresh();
  }

  void _cancelled(FlowExit? reason) {
    final flow = _flow;
    if (flow == null) return;
    flow.abandon();
    // Landing on an unchanged Home with no word about why is how a worker
    // concludes the app lost their Time In.
    _endFlow(notice: reason == FlowExit.cameraPermission ? flowCancelledByCamera(flow.direction) : null);
  }

  void _selectTab(int tab) {
    setState(() => _tab = tab);
    if (tab == 1) _history.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services;
    final flow = _flow;
    if (flow != null) {
      return TimeFlowScreen(
        key: ObjectKey(flow),
        controller: flow,
        cameraStep: s.cameraStep,
        onFinished: _endFlow,
        onCancelled: _cancelled,
        openSettings: s.openSettings,
      );
    }
    final body = switch (_tab) {
      0 => HomeScreen(
          worker: widget.worker,
          controller: _home,
          onStartFlow: _startFlow,
          onSeeHistory: () => _selectTab(1),
          openSettings: s.openSettings,
          exitNotice: _exitNotice,
          onDismissExit: () => setState(() => _exitNotice = null),
        ),
      1 => HistoryScreen(controller: _history, photoUrl: s.photoUrl),
      _ => _ProfileTab(worker: widget.worker, versionName: widget.versionName, onSignOut: widget.onSignOut),
    };
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

/// 0B's profile, unchanged; password change and the rest arrive in 0D.
class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.worker, required this.versionName, required this.onSignOut});
  final WorkerProfile worker;
  final String versionName;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Profile', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
        const SizedBox(height: 16),
        WorkerHeader(worker: worker),
        const SizedBox(height: 24),
        OutlinedButton.icon(onPressed: onSignOut, icon: const Icon(Icons.logout), label: const Text('Log out')),
        const SizedBox(height: 16),
        Text("DAC'S WorkMate $versionName · By Dacs Building Design Services",
            style: const TextStyle(fontSize: 12.5, color: WmColors.textMeta)),
      ]);
}
