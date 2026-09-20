import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const AimsFlowPreviewApp());
}

class AimsFlowPreviewApp extends StatelessWidget {
  const AimsFlowPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AIMS Flow R88 Preview',
      theme: ThemeData.dark(useMaterial3: true),
      home: const PreviewScreen(),
    );
  }
}

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  WebViewController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final parts = await Future.wait(
        List.generate(
          5,
          (i) => rootBundle.loadString('assets/mobile_preview/part$i.txt'),
        ),
      );
      final compressed = base64Decode(parts.join());
      final html = utf8.decode(gzip.decode(compressed));

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF01060B))
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) async {
              final uri = Uri.tryParse(request.url);
              if (uri != null &&
                  (uri.scheme == 'http' ||
                      uri.scheme == 'https' ||
                      uri.scheme == 'tel' ||
                      uri.scheme == 'mailto')) {
                if (uri.host == 'preview.logistic-aims.local') {
                  return NavigationDecision.navigate;
                }
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        );

      await controller.loadHtmlString(
        html,
        baseUrl: 'https://preview.logistic-aims.local/',
      );

      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF01060B),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'AIMS Flow preview betöltési hiba:\n$_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF01060B),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF01060B),
      body: SafeArea(
        top: true,
        bottom: false,
        child: WebViewWidget(controller: controller),
      ),
    );
  }
}
