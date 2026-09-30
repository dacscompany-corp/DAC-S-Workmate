import 'package:flutter/material.dart';

import '../update/apk_installer.dart';
import '../update/app_release.dart';
import '../update/app_update_repository.dart';
import 'failure_notice.dart';
import 'theme.dart';

/// Full-screen and not dismissible: every published release is required and
/// the server refuses older builds anyway. This is the explanation.
class UpdateOverlay extends StatefulWidget {
  const UpdateOverlay({super.key, required this.release, required this.updates, required this.installer});
  final AppRelease release;
  final AppUpdateRepository updates;
  final InstallGateway installer;

  @override
  State<UpdateOverlay> createState() => _UpdateOverlayState();
}

class _UpdateOverlayState extends State<UpdateOverlay> with WidgetsBindingObserver {
  double? _progress;
  DownloadReady? _ready;
  UpdateFailure? _failure;
  bool _needsPermission = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the "Install unknown apps" switch.
    // Continue only if the switch is now on; otherwise stay here. Settings
    // opens from the ALLOW INSTALLS button alone.
    if (state == AppLifecycleState.resumed && _needsPermission) _install(fromResume: true);
  }

  Future<void> _download() async {
    setState(() {
      _failure = null;
      _progress = 0;
    });
    try {
      final result = await widget.updates.download(widget.release, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() {
        switch (result) {
          case DownloadReady():
            _ready = result;
          case DownloadFailed(:final reason):
            _failure = reason;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _failure = UpdateFailure.downloadFailed);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  void _failDownload() {
    if (!mounted) return;
    setState(() {
      _ready = null;
      _needsPermission = false;
      _failure = UpdateFailure.downloadFailed;
    });
  }

  Future<void> _install({bool fromResume = false}) async {
    final ready = _ready;
    if (ready == null || _installing) return;
    _installing = true;
    try {
      // The cache may have been cleared since the download; installing a
      // missing file would only fail inside the OS. Download again instead.
      if (!ready.file.existsSync()) return _failDownload();
      if (!await widget.installer.canInstall()) {
        if (!mounted) return;
        setState(() => _needsPermission = true);
        if (!fromResume) await widget.installer.openInstallPermission();
        return;
      }
      if (!mounted) return;
      setState(() => _needsPermission = false);
      await widget.installer.install(ready.file);
    } catch (_) {
      _failDownload();
    } finally {
      _installing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.release;
    final String label;
    final VoidCallback? action;
    if (_progress != null) {
      label = 'DOWNLOADING… ${(_progress! * 100).round()}%';
      action = null;
    } else if (_needsPermission) {
      label = 'ALLOW INSTALLS';
      action = _install;
    } else if (_ready != null) {
      label = 'INSTALL';
      action = _install;
    } else if (_failure != null) {
      label = 'TRY AGAIN';
      action = _download;
    } else {
      label = 'UPDATE NOW!';
      action = _download;
    }

    return Material(
      color: WmColors.canvas,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Icon(Icons.system_update, size: 48, color: WmColors.green),
          const SizedBox(height: 16),
          const Text('New Update is Available', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 23)),
          const SizedBox(height: 6),
          const Text('A new version is released, please update to get new features',
              style: TextStyle(fontSize: 15, color: WmColors.textMuted)),
          const SizedBox(height: 16),
          Text('Version ${r.versionName}', style: monoLabel),
          if (r.releaseNotes != null) ...[
            const SizedBox(height: 16),
            const Text("WHAT'S NEW", style: monoLabel),
            const SizedBox(height: 6),
            Text(r.releaseNotes!, style: const TextStyle(fontSize: 14.5, height: 1.4)),
          ],
          if (_needsPermission) ...[
            const SizedBox(height: 16),
            const Text('One more step', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const Text("Allow DAC'S WorkMate to install updates. Turn on the switch, then come back here.",
                style: TextStyle(fontSize: 14, color: WmColors.textMuted)),
          ],
          if (_ready != null && !_needsPermission) ...[
            const SizedBox(height: 12),
            const Text('Tap Install on the next screen.', style: TextStyle(fontSize: 14, color: WmColors.textMuted)),
          ],
          if (_failure != null) ...[
            const SizedBox(height: 16),
            FailureNotice(english: _failure!.english, tagalog: _failure!.tagalog),
          ],
          const SizedBox(height: 24),
          FilledButton(onPressed: action, child: Text(label)),
        ]),
      ),
    );
  }
}
