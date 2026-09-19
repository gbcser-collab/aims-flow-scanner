import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:permission_handler/permission_handler.dart';

final InAppLocalhostServer localhostServer =
    InAppLocalhostServer(documentRoot: 'assets', port: 8080);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await localhostServer.start();
  runApp(const NailFitApp());
}

class NailFitApp extends StatelessWidget {
  const NailFitApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NAILFIT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC78F87)),
        useMaterial3: true,
      ),
      home: const NailFitHome(),
    );
  }
}

class NailFitHome extends StatefulWidget {
  const NailFitHome({super.key});
  @override
  State<NailFitHome> createState() => _NailFitHomeState();
}

class _NailFitHomeState extends State<NailFitHome> {
  @override
  void initState() {
    super.initState();
    Permission.camera.request();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F6),
      body: SafeArea(
        child: InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri('http://localhost:8080/index.html'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            transparentBackground: false,
            supportZoom: false,
          ),
          onPermissionRequest: (controller, request) async {
            final status = await Permission.camera.request();
            return PermissionResponse(
              resources: request.resources,
              action: status.isGranted
                  ? PermissionResponseAction.GRANT
                  : PermissionResponseAction.DENY,
            );
          },
        ),
      ),
    );
  }
}
