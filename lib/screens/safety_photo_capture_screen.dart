import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class SafetyPhotoCaptureScreen extends StatefulWidget {
  const SafetyPhotoCaptureScreen({
    super.key,
    required this.title,
    required this.fileLabel,
  });

  final String title;
  final String fileLabel;

  @override
  State<SafetyPhotoCaptureScreen> createState() =>
      _SafetyPhotoCaptureScreenState();
}

class _SafetyPhotoCaptureScreenState extends State<SafetyPhotoCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('Nincs elérhető kamera.');
      final rear = cameras.where((c) => c.lensDirection == CameraLensDirection.back);
      final camera = rear.isNotEmpty ? rear.first : cameras.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'A kamera nem indítható: $e';
        });
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await controller.takePicture();
      final root = await getApplicationSupportDirectory();
      final directory = Directory('${root.path}/aims_flow_safety_photos');
      if (!await directory.exists()) await directory.create(recursive: true);
      final safe = widget.fileLabel.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final target = File(
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$safe.jpg',
      );
      await File(shot.path).copy(target.path);
      if (!mounted) return;
      Navigator.of(context).pop(target.path);
    } catch (e) {
      if (mounted) setState(() => _error = 'A fotó nem menthető: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _controller == null) {
      _initialize();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : _controller == null || !_controller!.value.isInitialized
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 24,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _capture,
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: Text(_busy ? 'MENTÉS…' : 'FOTÓ KÉSZÍTÉSE'),
                        ),
                      ),
                    ],
                  ),
      );
}
