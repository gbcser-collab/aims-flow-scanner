import 'dart:async';

import 'package:flutter/material.dart';

import '../services/admin_push_service.dart';

class AdminCenterScreen extends StatefulWidget {
  const AdminCenterScreen({super.key});

  @override
  State<AdminCenterScreen> createState() => _AdminCenterScreenState();
}

class _AdminCenterScreenState extends State<AdminCenterScreen> {
  final _service = AdminPushService.instance;
  final _tokenController = TextEditingController();
  StreamSubscription<AdminPushStatus>? _statusSub;

  AdminPushStatus? _status;
  bool _busy = false;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _notifications = const [];
  List<Map<String, dynamic>> _fuel = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _statusSub = _service.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  Future<void> _bootstrap() async {
    final status = await _service.currentStatus();
    final token = await _service.storedAdminToken();
    if (!mounted) return;
    if (token != null && token.isNotEmpty) _tokenController.text = token;
    setState(() => _status = status);
    if (status.adminConfigured) await _refresh();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.enableForAdmin(_tokenController.text);
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.disableAdminPush();
      _tokenController.clear();
      if (mounted) {
        setState(() {
          _notifications = const [];
          _fuel = const [];
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _service.fetchNotifications(),
        _service.fetchFuelReceipts(),
      ]);
      if (!mounted) return;
      setState(() {
        _notifications = values[0];
        _fuel = values[1];
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await _service.markAllRead();
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _openReceipt(int id) async {
    try {
      final bytes = await _service.fetchFuelReceiptImage(id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: const Color(0xFF11151A),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: InteractiveViewer(
              minScale: .7,
              maxScale: 5,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '';
    final local = parsed.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final adminReady = status?.adminConfigured == true;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0F13),
        foregroundColor: Colors.white,
        title: const Text('AIMS Flow • Főnökség'),
        actions: [
          if (adminReady)
            IconButton(
              tooltip: 'Frissítés',
              onPressed: _loading ? null : _refresh,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _pushCard(status),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (!adminReady) _loginCard() else ...[
              _notificationSection(),
              const SizedBox(height: 18),
              _fuelSection(),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _busy ? null : _disable,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Főnökségi mód kikapcsolása ezen a telefonon'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white60,
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pushCard(AdminPushStatus? status) {
    final configured = status?.firebaseConfigured == true;
    final permission = status?.permissionGranted == true;
    final admin = status?.adminConfigured == true;
    final server = status?.serverConfigured == true;
    final active = configured && permission && admin && server;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171A1F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (active
                  ? const Color(0xFF48D597)
                  : const Color(0xFFE6B85C))
              .withValues(alpha: .35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            active
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded,
            color: active
                ? const Color(0xFF48D597)
                : const Color(0xFFE6B85C),
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active
                      ? 'Natív push aktív'
                      : 'Főnökségi push beállítása',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  !configured
                      ? 'Ehhez az APK-hoz még nincs Firebase-konfiguráció.'
                      : !admin
                          ? 'Add meg az admin tokent, majd engedélyezd az értesítéseket.'
                          : !permission
                              ? 'Az admin be van állítva, de a rendszerértesítés nincs engedélyezve.'
                              : !server
                                  ? 'A telefon kész, de a VPS Firebase-küldése még nincs konfigurálva.'
                                  : 'A rendszámaid eseményei erre a telefonra is megérkeznek.',
                  style: const TextStyle(color: Colors.white60, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15191F),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admin azonosítás',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'A token titkosított telefonos tárhelyre kerül, és nem jelenik meg az értesítésekben.',
            style: TextStyle(color: Colors.white54, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('admin-push-token'),
            controller: _tokenController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Admin token',
              labelStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF0D1115),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('enable-admin-push'),
            onPressed: _busy ? null : _enable,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_rounded),
            label: Text(_busy ? 'Beállítás…' : 'Főnökségi push bekapcsolása'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE6B85C),
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notificationSection() {
    final unread =
        _notifications.where((item) => item['readAt'] == null).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15191F),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Értesítések',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (unread > 0)
                TextButton(
                  onPressed: _markAllRead,
                  child: Text('Mind olvasott ($unread)'),
                ),
            ],
          ),
          if (_notifications.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Nincs értesítés.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          else
            ..._notifications.take(50).map((item) {
              final unreadItem = item['readAt'] == null;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.white10),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _notificationIcon(item['type']?.toString()),
                      color: unreadItem
                          ? const Color(0xFFE6B85C)
                          : Colors.white38,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title']?.toString() ?? 'AIMS Flow',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: unreadItem
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                          if ((item['body']?.toString() ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                item['body'].toString(),
                                style: const TextStyle(
                                  color: Colors.white60,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              _date(item['createdAt']),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _fuelSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF15191F),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tankolási bizonylatok',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          if (_fuel.isEmpty)
            const Text(
              'Még nincs beküldött bizonylat.',
              style: TextStyle(color: Colors.white54),
            )
          else
            ..._fuel.take(50).map((item) {
              final parts = <String>[
                if (item['liters'] != null) '${item['liters']} l',
                if (item['totalAmount'] != null)
                  '${item['totalAmount']} ${item['currency'] ?? ''}'.trim(),
                if ((item['station']?.toString() ?? '').isNotEmpty)
                  item['station'].toString(),
              ];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.local_gas_station_rounded,
                  color: Color(0xFFE6B85C),
                ),
                title: Text(
                  item['plate']?.toString() ?? 'Jármű',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  '${parts.join(' • ')}\n${_date(item['capturedAt'])}',
                  style: const TextStyle(color: Colors.white54),
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Bizonylat megnyitása',
                  onPressed: () =>
                      _openReceipt((item['id'] as num).toInt()),
                  icon: const Icon(
                    Icons.receipt_long_rounded,
                    color: Colors.white70,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  IconData _notificationIcon(String? type) {
    switch (type) {
      case 'stationary':
        return Icons.pause_circle_filled_rounded;
      case 'job_arrival':
        return Icons.location_on_rounded;
      case 'fuel_receipt':
        return Icons.local_gas_station_rounded;
      case 'job_registered':
        return Icons.assignment_turned_in_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }
}
