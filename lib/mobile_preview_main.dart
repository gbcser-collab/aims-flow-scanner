import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

const mobilePatch = r'''
<style>
#updatePush,.updatePush,.testpanel,details.testpanel,.hiddenList,.hiddenItem{display:none!important}
.aimsCleanTools{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin:12px 0 0}
.aimsCleanBtn{display:flex;align-items:center;gap:10px;text-align:left;background:#06131d;border:1px solid #173a4d;color:#ddecf4;border-radius:14px;padding:11px 12px;min-width:0}
.aimsCleanBtn .ico{font-size:21px;line-height:1;flex:0 0 auto}
.aimsCleanBtn b{display:block;font-size:10px;letter-spacing:.5px}
.aimsCleanBtn small{display:block;margin-top:3px;color:#7895a8;font-size:8px;line-height:1.25}
#aimsSystemPanel{display:none;margin-top:10px;padding:12px;border:1px solid #173a4d;border-radius:14px;background:#041019}
#aimsSystemPanel.show{display:block}
.aimsSysGrid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.aimsSysItem{padding:10px;border:1px solid #153548;border-radius:12px;background:#071721;font-size:9px;color:#91aabd}
.aimsSysItem b{display:block;color:#e4f6ff;font-size:10px;margin-bottom:3px}
.aimsSysActions{display:flex;gap:8px;margin-top:8px}
.aimsSysActions button{flex:1;border:1px solid #28566f;background:#092034;color:#dff6ff;border-radius:11px;padding:9px 7px;font-size:9px;font-weight:900}
</style>
<script>
(function(){
  function cleanDriverUi(){
    document.querySelectorAll('#updatePush,.updatePush,.testpanel,details.testpanel').forEach(function(el){el.remove();});

    try {
      if (typeof S !== 'undefined') {
        S.updateInstalled = true;
        if (S.appVersion) S.latestVersion = S.appVersion;
      }
      window.updateAvailable = function(){ return false; };
      window.installUpdate = function(){};
      window.updateDetails = function(){};
      window.simulateNewUpdate = function(){};
    } catch(e) {}

    var home = document.getElementById('home');
    if (!home || document.getElementById('aimsCleanTools')) return;

    var ownerButton = null;
    home.querySelectorAll('button').forEach(function(btn){
      var t = (btn.innerText || '').toUpperCase();
      if (t.indexOf('TULAJDONOS') >= 0 || t.indexOf('LOGISTIC') >= 0) ownerButton = btn;
    });
    if (ownerButton) ownerButton.remove();

    var firstMiniRow = home.querySelector('.minirow');
    if (firstMiniRow && firstMiniRow.children.length === 0) firstMiniRow.remove();

    var tools = document.createElement('div');
    tools.id = 'aimsCleanTools';
    tools.className = 'aimsCleanTools';
    tools.innerHTML =
      '<button class="aimsCleanBtn" type="button" onclick="document.getElementById(\'aimsSystemPanel\').classList.toggle(\'show\'); if(window.aimsSyncSystemState) window.aimsSyncSystemState();">' +
        '<span class="ico">⚙</span><span><b>RENDSZER</b><small>GPS · NET · app</small></span>' +
      '</button>' +
      '<button class="aimsCleanBtn" type="button" onclick="if(typeof openCompany===\'function\') openCompany();">' +
        '<span class="ico">🏢</span><span><b>CÉG</b><small>Logistic-AIMS</small></span>' +
      '</button>';

    var panel = document.createElement('div');
    panel.id = 'aimsSystemPanel';
    panel.innerHTML =
      '<div class="aimsSysGrid">' +
        '<div class="aimsSysItem"><b>GPS</b><span id="aimsGpsState">ON</span></div>' +
        '<div class="aimsSysItem"><b>NET</b><span id="aimsNetState">ON</span></div>' +
      '</div>' +
      '<div class="aimsSysActions">' +
        '<button type="button" onclick="if(typeof toggleNet===\'function\'){toggleNet();setTimeout(window.aimsSyncSystemState,50);}">NET KI / BE</button>' +
        '<button type="button" onclick="if(typeof restartDemo===\'function\') restartDemo(); else location.reload();">APP ÚJRAINDÍTÁSA</button>' +
      '</div>';

    var quickPanel = Array.from(home.querySelectorAll('.panel')).find(function(el){
      return (el.innerText || '').toUpperCase().indexOf('GYORS JELZÉS') >= 0;
    });
    if (quickPanel) {
      home.insertBefore(tools, quickPanel);
      home.insertBefore(panel, quickPanel);
    } else {
      home.appendChild(tools);
      home.appendChild(panel);
    }

    var heroSub = home.querySelector('.hero .sub');
    if (heroSub) heroSub.textContent = 'Mindig a következő szükséges lépést mutatjuk. Az utolsó lerakás után automatikusan a dokumentumok scannelése következik.';

    window.aimsSyncSystemState = function(){
      var net = document.getElementById('aimsNetState');
      var gps = document.getElementById('aimsGpsState');
      if (gps) gps.textContent = 'ON';
      if (net) {
        try { net.textContent = (typeof S !== 'undefined' && S.online === false) ? 'OFF' : 'ON'; }
        catch(e) { net.textContent = 'ON'; }
      }
    };
    window.aimsSyncSystemState();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', cleanDriverUi, {once:true});
  } else {
    cleanDriverUi();
  }
  setTimeout(cleanDriverUi, 250);
})();
</script>
''';

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
      title: 'AIMS Flow Driver',
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
      final patchedHtml = html.contains('</body>')
          ? html.replaceFirst('</body>', '$mobilePatch</body>')
          : '$html$mobilePatch';

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
        patchedHtml,
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
              'AIMS Flow betöltési hiba:\n$_error',
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
