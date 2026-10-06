import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'attendance/attendance_services.dart';
import 'profile/account_services.dart';
import 'requests/requests_services.dart';
import 'ui/gate_unavailable_screen.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';
import 'ui/terms_screen.dart';
import 'ui/theme.dart';
import 'ui/update_overlay.dart';
import 'update/apk_installer.dart';
import 'update/app_update_repository.dart';
import 'widget/start_flow.dart';

class WorkMateApp extends StatefulWidget {
  const WorkMateApp({
    super.key,
    required this.controller,
    required this.updates,
    required this.installer,
    required this.versionName,
    required this.attendance,
    required this.account,
    this.onResumed,
    this.launches,
    this.requests,
  });

  final AppController controller;
  final AppUpdateRepository updates;
  final InstallGateway installer;
  final String versionName;

  /// The attendance engine and its device services, for the signed-in app.
  final AttendanceServices attendance;

  /// Password change and the Terms date, for Profile.
  final AccountServices account;

  /// Runs on every return to the app (main.dart re-registers the sync host).
  final VoidCallback? onResumed;

  /// Widget taps MainActivity received; null in tests.
  final LaunchRequests? launches;

  /// The Requests tab (Stage 1a); null in tests that do not need it.
  final RequestsServices? requests;

  @override
  State<WorkMateApp> createState() => _WorkMateAppState();
}

class _WorkMateAppState extends State<WorkMateApp> with WidgetsBindingObserver {
  final _inbox = StartFlowInbox();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_gateStartFlow);
    widget.controller.start();
    _takeLaunch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_gateStartFlow);
    _inbox.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.checkForUpdate();
      widget.onResumed?.call();
      _takeLaunch();
    }
  }

  Future<void> _takeLaunch() async {
    final request = await widget.launches?.take();
    if (request == null || !mounted) return;
    _inbox.put(request);
    _gateStartFlow();
  }

  /// The app-level half of resolveStartFlow: a tap that arrives at the login or
  /// Terms screen is dropped; one that arrives while starting up waits; Home
  /// decides the rest.
  void _gateStartFlow() {
    final request = _inbox.pending;
    if (request == null) return;
    if (resolveStartFlow(request, widget.controller.state, flowOpen: false) == StartFlowDecision.drop) _inbox.clear();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: "DAC'S WorkMate",
        debugShowCheckedModeBanner: false,
        theme: workMateTheme(),
        home: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final c = widget.controller;
            final Widget screen = switch (c.state) {
              Starting() => const Scaffold(
                  body: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Checking your account…', style: TextStyle(fontSize: 15, color: WmColors.textMuted)),
                    ]),
                  ),
                ),
              SignedOut(:final notice) => LoginScreen(key: ValueKey(notice), initialNotice: notice, onSignIn: c.signIn),
              NeedsTerms() => TermsScreen(onAccept: c.acceptTerms),
              TermsUnavailable() => GateUnavailableScreen(onRetry: c.retryStartup, onSignOut: c.signOut),
              Ready(:final worker) => HomeShell(
                  worker: worker,
                  versionName: widget.versionName,
                  onSignOut: c.signOut,
                  services: widget.attendance,
                  account: widget.account,
                  startRequests: _inbox,
                  requests: widget.requests,
                ),
            };
            final update = c.requiredUpdate;
            return Stack(children: [
              screen,
              // Never in a debug build: the .debug package id can't install a
              // release APK over itself, so the overlay would be a dead end.
              // The updater is tested with release builds.
              if (update != null && !kDebugMode)
                Positioned.fill(
                  child: UpdateOverlay(
                    key: ValueKey(update.versionCode),
                    release: update,
                    updates: widget.updates,
                    installer: widget.installer,
                  ),
                ),
            ]);
          },
        ),
      );
}
