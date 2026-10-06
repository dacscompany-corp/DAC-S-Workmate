import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../attendance/domain/attendance_failure.dart';
import '../../attendance/ui/attendance_copy.dart';
import '../../ui/theme.dart';

/// A photo of the item being requested: BACK camera, no overlay, no caption.
/// Pops the raw capture's path (the repository files it), or nothing.
class RequestCameraScreen extends StatefulWidget {
  const RequestCameraScreen({super.key});

  @override
  State<RequestCameraScreen> createState() => _RequestCameraScreenState();
}

class _RequestCameraScreenState extends State<RequestCameraScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  bool? _granted;
  bool _failed = false;
  bool _capturing = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _askAndOpen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final camera = _camera;
      _camera = null;
      camera?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _recheck();
    }
  }

  Future<void> _askAndOpen() async {
    bool granted;
    try {
      granted = (await Permission.camera.request()).isGranted;
    } catch (_) {
      granted = await Permission.camera.isGranted;
    }
    if (!mounted) return;
    setState(() => _granted = granted);
    if (granted) await _open();
  }

  Future<void> _recheck() async {
    if (_granted == null) return;
    final granted = await Permission.camera.isGranted;
    if (!mounted) return;
    setState(() => _granted = granted);
    if (granted && _camera == null) await _open();
  }

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      controller = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      if (!mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _failed = false;
      });
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

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await camera.takePicture();
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final ready = camera != null && camera.value.isInitialized;
    return Scaffold(
      backgroundColor: WmColors.previewBackdrop,
      appBar: AppBar(
        backgroundColor: WmColors.previewBackdrop,
        foregroundColor: Colors.white,
        title: const Text('Photo of the item'),
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: _granted == false
                ? _message('The camera is needed for the photo. Allow it in Settings.', settings: true)
                : ready
                    ? CameraPreview(camera)
                    : _failed
                        ? _message(failureCopy(AttendanceFailure.unexpected).english,
                            tagalog: failureCopy(AttendanceFailure.unexpected).tagalog)
                        : const CircularProgressIndicator(color: Colors.white),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Semantics(
            button: true,
            label: 'Take photo',
            child: GestureDetector(
              key: const Key('request-shutter'),
              onTap: ready && !_capturing ? _shoot : null,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: ready && !_capturing ? 1 : 0.3),
                  border: Border.all(color: Colors.white70, width: 4),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// [tagalog]: failure copy is bilingual, as on Attendance's camera.
  Widget _message(String text, {String? tagalog, bool settings = false}) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
          if (tagalog != null) Text(tagalog, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          if (settings)
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text(openSettingsLabel, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
        ]),
      );
}
