import 'dart:async';

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
import '../profile/password_prompt.dart';
import '../profile/profile_screen.dart';
import '../profile/set_own_password_screen.dart';
import '../requests/home/request_updates_card.dart';
import '../requests/list/requests_controller.dart';
import '../requests/list/requests_screen.dart';
import '../requests/requests_services.dart';
import '../tools/data/tool_submitter.dart';
import '../tools/tools_services.dart';
import '../tools/ui/tools_card.dart';
import '../tools/ui/tools_controller.dart';
import '../tools/ui/tools_screen.dart';
import '../widget/start_flow.dart';
import '../workplan/ui/my_work_card.dart';
import '../workplan/ui/my_work_controller.dart';
import '../workplan/ui/my_work_screen.dart';
import '../workplan/workplan_services.dart';

enum _Tab { home, work, requests, history, profile }

/// The signed-in app: Home, My Work (Stage 1c), Requests (Stage 1a), History
/// and Profile, and the
/// four-step Time In / Time Out flow launched from Home. The flow is MODAL (no
/// tabs while recording). Tools (Stage 3b) open from a card on Home; the
/// temporary-password prompt opens over Home, never over the flow.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.worker,
    required this.versionName,
    required this.onSignOut,
    required this.services,
    required this.account,
    this.startRequests,
    this.requests,
    this.workPlan,
    this.tools,
  });

  final WorkerProfile worker;
  final String versionName;
  final Future<void> Function() onSignOut;
  final AttendanceServices services;
  final AccountServices account;

  /// Widget taps waiting for Home to decide them.
  final StartFlowInbox? startRequests;

  /// The Requests tab's services; null shows no Requests tab.
  final RequestsServices? requests;

  /// The My Work tab's services; null shows no My Work tab.
  final WorkPlanServices? workPlan;

  /// Tools on the phone (Stage 3b); null shows no My tools card.
  final ToolsServices? tools;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  _Tab _tab = _Tab.home;
  TimeFlowController? _flow;
  Bilingual? _exitNotice;
  late final HomeController _home;
  late final HistoryController _history;
  RequestsController? _requests;
  MyWorkController? _work;
  ToolsController? _tools;
  ToolSubmitter? _toolSubmitter;
  PasswordPrompt? _prompt;
  Route<void>? _promptRoute;
  NavigatorState? _promptNavigator;

  List<_Tab> get _tabs => [
        _Tab.home,
        if (widget.workPlan != null) _Tab.work,
        if (widget.requests != null) _Tab.requests,
        _Tab.history,
        _Tab.profile,
      ];

  @override
  void initState() {
    super.initState();
    final s = widget.services;
    _home = HomeController(attendance: s.attendance, scheduler: s.scheduler, rewards: s.rewards);
    _history = HistoryController(attendance: s.attendance);
    final r = widget.requests;
    if (r != null) _requests = RequestsController(api: r.api)..refresh();
    final w = widget.workPlan;
    if (w != null) _work = MyWorkController(api: w.api)..refresh();
    final t = widget.tools;
    if (t != null) {
      _tools = ToolsController(remote: t.remote, saved: t.saved, userId: widget.worker.id, isLeader: widget.worker.role == 'teamLeader')
        ..refresh();
      final submitter = _toolSubmitter = ToolSubmitter(remote: t.remote, store: t.store);
      unawaited(submitter.load(widget.worker.id).then((_) => submitter.checkAll()));
    }
    final p = widget.account.passwordPrompt;
    if (p != null) {
      // Bound to this worker: the prompt changes no other account's password.
      _prompt = PasswordPrompt(services: p, userId: widget.worker.id)
        ..addListener(_maybePrompt)
        ..check();
    }
    WidgetsBinding.instance.addObserver(this);
    _home.refresh();
    // main.dart passes the same QueueSettled to all of them: listen once each.
    for (final l in _changeSources) {
      l.addListener(_onQueueSettled);
    }
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
    if (_tab != _Tab.home) setState(() => _tab = _Tab.home);
  }

  /// Every "the background drain settled something" source, each once.
  Set<Listenable> get _changeSources => {
        ?widget.services.queueSettled,
        ?widget.requests?.changed,
        ?widget.workPlan?.changed,
      };

  void _onQueueSettled() {
    // Not while recording: the flow owns the screen, and _endFlow refreshes anyway.
    if (_flow == null) _home.refresh(sendQueued: false);
    if (_tab == _Tab.history) _history.refresh();
    _requests?.refresh();
    _work?.refresh();
    _tools?.refresh();
    // Something just reached the server: signal is back, so ask again.
    _prompt?.check();
  }

  /// The temporary-password prompt (P1 = A), when the server wants it — over
  /// Home only. A Time In or Time Out in progress is never interrupted: the
  /// prompt waits for the flow to end (_endFlow asks again).
  void _maybePrompt() {
    final p = _prompt;
    if (p == null || !mounted || _promptRoute != null || _flow != null || !p.wanted) return;
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => SetOwnPasswordScreen(prompt: p, onSignOut: widget.onSignOut),
    );
    final navigator = Navigator.of(context);
    _promptRoute = route;
    _promptNavigator = navigator;
    navigator.push(route).whenComplete(() {
      if (_promptRoute == route) {
        _promptRoute = null;
        _promptNavigator = null;
      }
    });
  }

  @override
  void dispose() {
    for (final l in _changeSources) {
      l.removeListener(_onQueueSettled);
    }
    WidgetsBinding.instance.removeObserver(this);
    widget.startRequests?.removeListener(_consumeStart);
    _home.removeListener(_consumeStart);
    _flow?.abandon();
    _flow?.dispose();
    _home.dispose();
    _history.dispose();
    _requests?.dispose();
    _work?.dispose();
    _tools?.dispose();
    _toolSubmitter?.dispose();
    _prompt?.removeListener(_maybePrompt);
    _prompt?.dispose();
    // Signed out (or another account let in) while the prompt was open: it
    // must not stay over the next screen.
    final route = _promptRoute;
    final navigator = _promptNavigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) navigator.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the app is when a worker can see "Not sent yet": re-read today and
    // send what waits. Not while recording — the camera's permission prompts
    // pause and resume the app too.
    if (state == AppLifecycleState.resumed && _flow == null) {
      _home.refresh();
      _requests?.refresh();
      _work?.refresh();
      _tools?.refresh();
      final s = _toolSubmitter;
      if (s != null && s.blocked) unawaited(s.checkAll());
      _prompt?.check();
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ended?.dispose();
      // A prompt that waited for the flow may open now.
      _maybePrompt();
    });
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

  void _selectTab(_Tab tab) {
    setState(() => _tab = tab);
    if (tab == _Tab.history) _history.refresh();
    if (tab == _Tab.requests) _requests?.refresh();
    if (tab == _Tab.work) _work?.refresh();
  }

  /// A materials problem's "Make a request": back to the tabs, on Requests.
  void _openRequests() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _selectTab(_Tab.requests);
  }

  void _openTools() {
    final c = _tools;
    final s = _toolSubmitter;
    if (c == null || s == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ToolsScreen(controller: c, submitter: s)));
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
    final requests = _requests;
    final work = _work;
    final tools = _tools;
    final cards = [
      if (work != null)
        ListenableBuilder(
          listenable: work,
          builder: (context, _) => MyWorkCard(updates: work.updates, onOpen: () => _selectTab(_Tab.work)),
        ),
      if (requests != null)
        ListenableBuilder(
          listenable: requests,
          builder: (context, _) => RequestUpdatesCard(updates: requests.updates, onOpen: () => _selectTab(_Tab.requests)),
        ),
      if (tools != null)
        ListenableBuilder(
          listenable: tools,
          builder: (context, _) => ToolsCard(controller: tools, onOpen: _openTools),
        ),
    ];
    final body = switch (_tab) {
      _Tab.home => HomeScreen(
          worker: widget.worker,
          controller: _home,
          onStartFlow: _startFlow,
          onSeeHistory: () => _selectTab(_Tab.history),
          openSettings: s.openSettings,
          exitNotice: _exitNotice,
          onDismissExit: () => setState(() => _exitNotice = null),
          requestUpdates: cards.isEmpty ? null : Column(children: cards),
        ),
      _Tab.work => MyWorkScreen(
          controller: work!,
          services: widget.workPlan!,
          isLeader: widget.worker.role == 'teamLeader',
          onMakeRequest: requests == null ? null : _openRequests,
        ),
      _Tab.requests => RequestsScreen(controller: requests!, services: widget.requests!),
      _Tab.history => HistoryScreen(controller: _history, photoUrl: s.photoUrl),
      _Tab.profile => ProfileScreen(worker: widget.worker, versionName: widget.versionName, onSignOut: widget.onSignOut, account: widget.account),
    };
    final tabs = _tabs;
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabs.indexOf(_tab),
        onDestinationSelected: (i) => _selectTab(tabs[i]),
        destinations: [
          for (final t in tabs)
            switch (t) {
              _Tab.home => const NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
              _Tab.work => NavigationDestination(icon: _WorkIcon(controller: work!), label: 'My Work'),
              _Tab.requests => const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Requests'),
              _Tab.history => const NavigationDestination(icon: Icon(Icons.history), label: 'History'),
              _Tab.profile => const NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
            },
        ],
      ),
    );
  }
}

/// The My Work tab's icon, with a red number for what needs the worker
/// (tasks to read or check, actions not accepted).
class _WorkIcon extends StatelessWidget {
  const _WorkIcon({required this.controller});
  final MyWorkController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final n = controller.updates.badge;
          return Badge(
            key: const Key('my-work-badge'),
            isLabelVisible: n > 0,
            label: Text('$n'),
            child: const Icon(Icons.assignment_outlined),
          );
        },
      );
}
