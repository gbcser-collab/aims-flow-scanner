import 'package:flutter/material.dart';

typedef FlowSyncTranslate = String Function(String hu, String en, String de);

class FlowSyncRow {
  const FlowSyncRow({required this.title, required this.detail, this.pending});
  final String title;
  final String detail;
  // Null means unavailable, never a successful empty queue.
  final int? pending;
}

class FlowSyncDetailsScreen extends StatefulWidget {
  const FlowSyncDetailsScreen({super.key, required this.load,
    required this.retry, required this.translate, this.trackingSettings});
  final Future<List<FlowSyncRow>> Function() load;
  final Future<void> Function() retry;
  final FlowSyncTranslate translate;
  final VoidCallback? trackingSettings;

  @override
  State<FlowSyncDetailsScreen> createState() => _FlowSyncDetailsScreenState();
}

class _FlowSyncDetailsScreenState extends State<FlowSyncDetailsScreen> {
  List<FlowSyncRow> _rows = [];
  bool _busy = false;
  String? _error;
  DateTime? _checkedAt;
  FlowSyncTranslate get _l => widget.translate;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh({bool send = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (send) {
        try {
          await widget.retry();
        } catch (_) {
          if (mounted) setState(() => _error = _l(
            'Néhány küldés nem sikerült. Ellenőrizd az alábbi sorokat.',
            'Some uploads failed. Check the queues below.',
            'Einige Übertragungen sind fehlgeschlagen. Prüfe die Listen unten.'));
        }
      }
      final rows = await widget.load();
      if (mounted) setState(() { _rows = rows; _checkedAt = DateTime.now(); });
    } catch (_) {
      if (mounted) setState(() {
        _rows = [];
        _checkedAt = null;
        _error = _l('Az állapot most nem olvasható. Próbáld újra.',
          'Status is unavailable. Try again.', 'Status nicht verfügbar. Erneut versuchen.');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_l('Szinkronállapot', 'Sync status', 'Synchronisierung')),
      actions: [if (widget.trackingSettings != null) IconButton(
        onPressed: widget.trackingSettings, icon: const Icon(Icons.gps_fixed),
        tooltip: _l('Követés beállításai', 'Tracking settings', 'Ortungseinstellungen')), IconButton(onPressed: _busy ? null : () => _refresh(),
        tooltip: _l('Állapot frissítése', 'Refresh status', 'Status aktualisieren'),
        icon: const Icon(Icons.refresh))]),
    body: SafeArea(child: Column(children: [
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text(_l('A küldéshez kapcsolat és érvényes belépés szükséges.',
          'Sending requires a connection and a valid session.',
          'Zum Senden sind eine Verbindung und eine gültige Anmeldung erforderlich.')),
        if (_checkedAt != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text('${_l('Állapot ellenőrizve', 'Status checked', 'Status geprüft')}: '
            '${TimeOfDay.fromDateTime(_checkedAt!).format(context)}')),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 12),
        for (final row in _rows) Card(child: Padding(padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(row.title,
              style: Theme.of(context).textTheme.titleMedium)),
              Text(row.pending?.toString() ?? '—',
                style: Theme.of(context).textTheme.headlineSmall)]),
            const SizedBox(height: 8), Text(row.detail),
          ]))),
        const SizedBox(height: 12),
        Text(_l('Az azonosítatlan, másik sofőrhöz vagy járműhöz tartozó és hibás '
          'adatok megőrizve maradnak. Ezeket az iroda segítségével kell rendezni. '
          'Függő adatok mellett ne töröld az alkalmazás adatait.',
          'Unidentified, other-driver/vehicle and damaged records are retained. '
          'Contact the office to resolve them. Do not clear app data while records are pending.',
          'Nicht zugeordnete, fremde und beschädigte Datensätze bleiben erhalten. '
          'Bitte das Büro um Klärung. Bei ausstehenden Daten keine App-Daten löschen.')),
      ])),
      Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity,
        child: FilledButton.icon(onPressed: _busy ? null : () => _refresh(send: true),
          icon: const Icon(Icons.sync), label: Text(_l('Küldés újrapróbálása',
            'Retry sending', 'Erneut senden'))))),
    ])),
  );
}
