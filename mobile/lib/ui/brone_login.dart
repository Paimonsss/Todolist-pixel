import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/ical.dart';
import 'pixel.dart';

const _exportPage = 'https://brone.ub.ac.id/calendar/export.php';

// Hanya dijalankan di halaman ekspor BRONE, tidak pernah di halaman login SSO.
const _captureScript = r'''
(function () {
  var html = document.documentElement.innerHTML.replace(/&amp;/g, '&');
  var m = html.match(/https:\/\/brone\.ub\.ac\.id\/calendar\/export_execute\.php\?[^"'<\s]+/);
  if (m) return m[0];
  var all = document.querySelector('input[type=radio][name="events[exportevents]"][value="all"]');
  var time = document.querySelector('input[type=radio][name="period[timeperiod]"][value="recentupcoming"]');
  var button = document.querySelector('[name="generateurl"]');
  if (all && time && button) { all.checked = true; time.checked = true; button.click(); return 'submitted'; }
  return 'missing';
})()
''';

/// Login SSO terjadi di halaman resmi. Aplikasi hanya mengambil link kalender.
class BroneLoginPage extends StatefulWidget {
  const BroneLoginPage({super.key});

  @override
  State<BroneLoginPage> createState() => _BroneLoginPageState();
}

class _BroneLoginPageState extends State<BroneLoginPage> {
  late final WebViewController _web;
  int _attempts = 0;
  bool _loading = true;
  bool _finished = false;
  bool _showManual = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _guard,
          onPageStarted: (_) =>
              mounted ? setState(() => _loading = true) : null,
          onPageFinished: _onPage,
        ),
      )
      ..loadRequest(Uri.parse(_exportPage));
  }

  NavigationDecision _guard(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final trusted =
        uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'ub.ac.id' || uri.host.endsWith('.ub.ac.id'));
    return trusted ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  Future<void> _onPage(String page) async {
    if (!mounted || _finished) return;
    setState(() => _loading = false);
    final uri = Uri.tryParse(page);
    if (uri?.scheme != 'https' ||
        uri?.host != 'brone.ub.ac.id' ||
        uri?.path != '/calendar/export.php')
      return;

    try {
      var result = (await _web.runJavaScriptReturningResult(
        _captureScript,
      )).toString();
      if (result.startsWith('"')) result = jsonDecode(result) as String;
      if (result.startsWith('https://')) {
        _finish(normalizeBroneUrl(result));
      } else if (result == 'submitted' && ++_attempts <= 2) {
        setState(() => _loading = true);
      } else if (mounted) {
        setState(() => _showManual = true);
      }
    } on Exception {
      if (mounted) setState(() => _showManual = true);
    }
  }

  Future<void> _finish(String url) async {
    _finished = true;
    // Sesi SSO dipertahankan untuk mengecek status pengumpulan tugas.
    if (mounted) Navigator.of(context).pop(url);
  }

  Future<void> _manual() async {
    final field = TextEditingController();
    String? error;
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Px.paper,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Px.ink, width: 3),
          ),
          title: const Text('Tempel link', style: Px.display),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih All events dan Recent and next 60 days, tekan Get calendar URL, lalu salin link-nya.',
                style: Px.note,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: field,
                autocorrect: false,
                keyboardType: TextInputType.url,
                style: Px.body,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: Px.note.copyWith(color: Px.darkRed),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal', style: Px.body),
            ),
            TextButton(
              onPressed: () {
                try {
                  Navigator.pop(ctx, normalizeBroneUrl(field.text));
                } on BroneException catch (e) {
                  setLocal(() => error = e.message);
                }
              },
              child: const Text('Pakai', style: Px.body),
            ),
          ],
        ),
      ),
    );
    field.dispose();
    if (url != null) _finish(url);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Px.bg,
    appBar: AppBar(
      backgroundColor: Px.ink,
      foregroundColor: Px.paper,
      title: Text('Login BRONE', style: Px.display.copyWith(color: Px.paper)),
      actions: [
        TextButton(
          onPressed: _manual,
          child: Text('Tempel link', style: Px.body.copyWith(color: Px.yellow)),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_loading)
          const LinearProgressIndicator(
            minHeight: 4,
            color: Px.yellow,
            backgroundColor: Px.ink,
          ),
        if (_showManual)
          MaterialBanner(
            backgroundColor: Px.yellow,
            content: const Text(
              'Link belum terbaca otomatis. Salin dari halaman ini.',
              style: Px.body,
            ),
            actions: [
              TextButton(
                onPressed: _manual,
                child: const Text('Tempel', style: Px.body),
              ),
            ],
          ),
        Expanded(child: WebViewWidget(controller: _web)),
      ],
    ),
  );
}
