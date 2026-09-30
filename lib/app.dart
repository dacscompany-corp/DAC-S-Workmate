import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui/gate_unavailable_screen.dart';
import 'ui/home_shell.dart';
import 'ui/login_screen.dart';
import 'ui/terms_screen.dart';
import 'ui/theme.dart';
import 'ui/update_overlay.dart';
import 'update/apk_installer.dart';
import 'update/app_update_repository.dart';

class WorkMateApp extends StatefulWidget {
  const WorkMateApp({
    super.key,
    required this.controller,
    required this.updates,
    required this.installer,
    required this.versionName,
  });

  final AppController controller;
  final AppUpdateRepository updates;
  final InstallGateway installer;
  final String versionName;

  @override
  State<WorkMateApp> createState() => _WorkMateAppState();
}

class _WorkMateAppState extends State<WorkMateApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.checkForUpdate();
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
              Ready(:final worker) => HomeShell(worker: worker, versionName: widget.versionName, onSignOut: c.signOut),
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
