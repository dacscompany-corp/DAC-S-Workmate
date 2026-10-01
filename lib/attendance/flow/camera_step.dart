import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../ui/theme.dart';
import '../domain/attendance_failure.dart';
import '../domain/photo_overlay.dart';
import '../ui/attendance_copy.dart';
import 'time_flow_screen.dart';

/// Step 2: the photo that proves attendance. In-app capture only — a photo
/// that must be taken now, at the site, is the cheapest anti-spoofing there is.
///
/// FRONT camera by default, BACK one tap away; a front photo is filed
/// mirrored, as previewed (see PhotoPreparer).
///
/// CAMERA AND LOCATION are asked for together, here: location is used at
/// SUBMIT, and asking there — photo taken, note typed — is where a denial
/// costs most. Only the CAMERA answer gates this screen; a refused location
/// is explained at SUBMIT in words the worker can act on.
class CameraStep extends StatefulWidget {
  const CameraStep({super.key, required this.args});
  final CameraStepArgs args;

  @override
  State<CameraStep> createState() => _CameraStepState();
}

class _CameraStepState extends State<CameraStep> with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  CameraLensDirection _lens = CameraLensDirection.front;

  /// Null while the first permission prompt is still on screen.
  bool? _granted;
  bool _opening = false;
  bool _failed = false;
  bool _capturing = false;
  DateTime _now = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The preview caption must move, or it is wrong by the time the shutter fires.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _askAndOpen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Release the camera while away; it is re-opened on return.
      final camera = _camera;
      _camera = null;
      camera?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      // Back from Settings: re-check, or a granted camera stays dead.
      _recheckAndOpen();
    }
  }

  Future<void> _askAndOpen() async {
    bool granted;
    try {
      final statuses = await [Permission.camera, Permission.locationWhenInUse].request();
      granted = statuses[Permission.camera]?.isGranted ?? false;
    } catch (_) {
      // A failed prompt must not leave _granted null (an endless spinner).
      granted = await Permission.camera.isGranted;
    }
    if (!mounted) return;
    setState(() => _granted = granted);
    if (granted) await _open();
  }

  Future<void> _recheckAndOpen() async {
    if (_granted == null) return; // the first prompt is still being answered
    final granted = await Permission.camera.isGranted;
    if (!mounted) return;
    setState(() => _granted = granted);
    if (granted && _camera == null) await _open();
  }

  bool get _canSwitch =>
      _cameras.any((c) => c.lensDirection == CameraLensDirection.front) &&
      _cameras.any((c) => c.lensDirection == CameraLensDirection.back);

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    CameraController? controller;
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      // Front unless the phone has none: a hard-coded front lens left such a phone staring at black.
      if (!_cameras.any((c) => c.lensDirection == CameraLensDirection.front)) _lens = CameraLensDirection.back;
      final description = _cameras.firstWhere((c) => c.lensDirection == _lens, orElse: () => _cameras.first);
      controller = CameraController(
        description,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      // Opened across a pause (or a pop): release it, or the camera stays on in the background.
      if (!mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await controller.dispose();
        return;
      }
      final old = _camera;
      setState(() {
        _camera = controller;
        _lens = description.lensDirection;
        _failed = false;
      });
      await old?.dispose();
    } catch (e) {
      debugPrint('Camera failed to open: $e');
      try {
        await controller?.dispose();
      } catch (_) {}
      if (mounted) setState(() => _failed = true);
    } finally {
      _opening = false;
    }
  }

  Future<void> _switch() async {
    _lens = _lens == CameraLensDirection.front ? CameraLensDirection.back : CameraLensDirection.front;
    final old = _camera;
    setState(() => _camera = null);
    await old?.dispose();
    await _open();
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    final at = DateTime.now(); // the shutter, frozen here
    final mirrored = _lens == CameraLensDirection.front;
    XFile file;
    try {
      file = await camera.takePicture();
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
      return;
    }
    if (!mounted) return;
    widget.args.onTaken(file.path, at, mirrored);
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final ready = camera != null && camera.value.isInitialized;
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: ColoredBox(
              color: const Color(0xFF1E211E),
              child: _granted == false
                  ? _denied()
                  : ready
                      ? _preview(camera)
                      : _waiting(),
            ),
          ),
        ),
      ),
      _ShutterRow(
        enabled: ready && !_capturing,
        capturing: _capturing,
        onShoot: _shoot,
        onSwitch: ready && !_capturing && _canSwitch ? _switch : null,
      ),
    ]);
  }

  Widget _waiting() {
    if (!_failed) return const Center(child: CircularProgressIndicator(color: Colors.white));
    final copy = failureCopy(AttendanceFailure.unexpected);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(copy.english, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          Text(copy.tagalog, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          TextButton(
            onPressed: _open,
            child: const Text(retryLabel, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }

  Widget _denied() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'The camera is needed for the photo. Allow it in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 14),
            // After a permanent denial the app cannot ask again; Settings is the
            // only way forward, and the resume re-check makes coming back work.
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text(openSettingsLabel, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: widget.args.onGiveUp,
              child: const Text(notNowLabel, style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );

  Widget _preview(CameraController camera) {
    final size = camera.value.previewSize;
    // The SAME text that gets burned into the file, shown before the shutter,
    // so a wrong project or a wrong phone clock is caught while it costs one tap.
    final (name, stamp) = photoOverlayCaptionLines(widget.args.projectName, _now);
    return Stack(fit: StackFit.expand, children: [
      if (size != null)
        FittedBox(
          fit: BoxFit.cover,
          // previewSize is landscape; the phone is held upright.
          child: SizedBox(width: size.height, height: size.width, child: CameraPreview(camera)),
        )
      else
        CameraPreview(camera),
      const IgnorePointer(
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.62,
            heightFactor: 0.58,
            child: DecoratedBox(
              decoration: ShapeDecoration(shape: OvalBorder(side: BorderSide(color: Colors.white70, width: 3))),
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.all(14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(stamp, style: const TextStyle(color: Colors.white, fontFamily: 'IBM Plex Mono', fontSize: 12)),
          ]),
        ),
      ),
      const Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Put your face inside the circle',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ),
    ]);
  }
}

/// The shutter, with the camera switch beside it. No flash: on the front
/// camera of the phones this app targets it does nothing.
class _ShutterRow extends StatelessWidget {
  const _ShutterRow({required this.enabled, required this.capturing, required this.onShoot, required this.onSwitch});
  final bool enabled;
  final bool capturing;
  final VoidCallback onShoot;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 72),
          Semantics(
            button: true,
            label: 'Take photo',
            child: GestureDetector(
              key: const Key('shutter'),
              onTap: enabled ? onShoot : null,
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: enabled ? 0.85 : 0.3), width: 4),
                ),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: enabled ? 1 : 0.3)),
                  child: capturing
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(strokeWidth: 3, color: WmColors.previewBackdrop),
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 48,
            child: onSwitch == null
                ? null
                : IconButton(
                    tooltip: 'Switch camera',
                    onPressed: onSwitch,
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                  ),
          ),
        ]),
      );
}
