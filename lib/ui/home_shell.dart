import 'package:flutter/material.dart';

import '../app_controller.dart';
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
import '../profile/account_services.dart';
import '../profile/profile_screen.dart';
import '../widget/start_flow.dart';

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
    required this.account,
    this.startRequests,
  });

  final WorkerProfile worker;
  final String versionName;
  final Future<void> Function() onSignOut;
  final AttendanceServices services;
  final AccountServices account;

  /// Widget taps waiting for Home to decide them.
  final StartFlowInbox? startRequests;

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
    _home = HomeController(attendance: s.attendance, scheduler: s.scheduler, rewards: s.rewards);
    _history = HistoryController(attendance: s.attendance);
    WidgetsBinding.instance.addObserver(this);
    _home.refresh();
    s.queueSettled?.addListener(_onQueueSettled);
    widget.startRequests?.addListener(_consumeStart);
    _home.addListener(_consumeStart);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeStart());
  }

  void _consumeStart() {
    final inbox = widget.startRequests;
    final request = inbox?.pending;
    if (inbox == null || request == null || !mounted) return;
    final decision = resolveStartFlow(
      request,
      Ready(widget.worker),
      flowOpen: _flow != null,
      home: (loading: _home.loading, nextAction: _home.nextAction),
    );
    switch (decision) {
      case StartFlowDecision.wait:
        return;
      case StartFlowDecision.drop:
        inbox.clear();
      case StartFlowDecision.stayOnHome:
        inbox.clear();
        _showHome();
      case StartFlowDecision.open:
        inbox.clear();
        _showHome();
        _startFlow(request);
    }
  }

  /// Back to Home from wherever the worker left the app: a tab, the Terms
  /// reader, the password sheet.
  void _showHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (_tab != 0) setState(() => _tab = 0);
  }

  void _onQueueSettled() {
    // Not while recording: the flow owns the screen, and _endFlow refreshes anyway.
    if (_flow == null) _home.refresh(sendQueued: false);
    if (_tab == 1) _history.refresh();
  }

  @override
  void dispose() {
    widget.services.queueSettled?.removeListener(_onQueueSettled);
    WidgetsBinding.instance.removeObserver(this);
    widget.startRequests?.removeListener(_consumeStart);
    _home.removeListener(_consumeStart);
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
      _ => ProfileScreen(worker: widget.worker, versionName: widget.versionName, onSignOut: widget.onSignOut, account: widget.account),
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
