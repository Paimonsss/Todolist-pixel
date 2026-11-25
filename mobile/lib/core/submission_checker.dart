import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

enum CheckStatus { ok, needsLogin, failed }

/// Hasil pengecekan satu acara BRONE.
class EventCheck {
  const EventCheck(this.verdict, this.module);
  final String
  verdict; // submitted, timeline, draft, open, other, missing, error
  final String module;

  bool get isDone => verdict == 'submitted' || verdict == 'timeline';
}

class CheckResult {
  const CheckResult(
    this.status, [
    this.events = const {},
    this.timelineOk = false,
  ]);
  final CheckStatus status;
  final Map<int, EventCheck> events;
  final bool timelineOk;

  Set<int> get submitted => {
    for (final e in events.entries)
      if (e.value.isDone) e.key,
  };
}

// Dua sumber bukti, keduanya dari BRONE sendiri:
// 1. Halaman tugas menampilkan status "Submitted" (atau syarat penyelesaian pengumpulan sudah hijau).
// 2. Timeline Moodle menghapus tugas yang sudah dikumpulkan. Hanya dipakai untuk tugas
//    assign/kuis yang tenggatnya belum lewat, karena tugas lewat cutoff juga hilang dari Timeline.
const _script = r'''
(async function () {
  var input = __INPUT__, out = {};
  var sesskey = window.M && M.cfg && M.cfg.sesskey;
  if (!sesskey) { TugasQuest.postMessage('{"ok":false}'); return; }

  async function call(method, args) {
    var res = await fetch('/lib/ajax/service.php?sesskey=' + encodeURIComponent(sesskey) + '&info=' + method, {
      method: 'POST', credentials: 'same-origin', headers: { 'content-type': 'application/json' },
      body: JSON.stringify([{ index: 0, methodname: method, args: args }])
    });
    var body = await res.json();
    if (!body || !body[0] || body[0].error) throw new Error(method);
    return body[0].data;
  }

  var timeline = {}, timelineOk = false;
  try {
    var after = 0, from = Math.floor(Date.now() / 1000) - 60;
    for (var page = 0; page < 10; page++) {
      var args = { timesortfrom: from, limitnum: 50 };
      if (after) args.aftereventid = after;
      var data = await call('core_calendar_get_action_events_by_timesort', args);
      var events = data.events || [];
      events.forEach(function (e) { timeline[e.id] = true; });
      if (events.length < 50) { timelineOk = true; break; }
      after = events[events.length - 1].id;
    }
  } catch (e) { timelineOk = false; }

  function pageSaysSubmitted(doc) {
    if (doc.querySelector('.submissionstatussubmitted')) return 'submitted';
    var done = doc.querySelectorAll('[data-region="activity-information"] .alert-success, [data-region="completionrequirements"] .alert-success');
    for (var i = 0; i < done.length; i++) {
      if (/submi|kirim|kumpul/i.test(done[i].textContent)) return 'submitted';
    }
    var rows = doc.querySelectorAll('tr');
    for (var j = 0; j < rows.length; j++) {
      var head = rows[j].querySelector('th, td');
      var value = rows[j].querySelector('td:last-child');
      if (head && value && /submission status|status pengumpulan|status pengiriman/i.test(head.textContent) &&
          /submitted for grading|dikirim untuk dinilai|sudah dikirim|telah dikirim/i.test(value.textContent)) return 'submitted';
    }
    if (doc.querySelector('.submissionstatusdraft')) return 'draft';
    return 'open';
  }

  for (var i = 0; i < input.length; i++) {
    var item = input[i];
    try {
      var event = (await call('core_calendar_get_calendar_event_by_id', { eventid: item.id })).event;
      var mod = event.modulename || '';
      var verdict = 'other';
      if (mod === 'assign' && event.url) {
        var url = new URL(event.url, location.origin);
        if (url.origin === location.origin && url.pathname === '/mod/assign/view.php') {
          var res = await fetch(url.href, { credentials: 'same-origin' });
          if (res.ok) verdict = pageSaysSubmitted(new DOMParser().parseFromString(await res.text(), 'text/html'));
        }
      }
      if (verdict !== 'submitted' && verdict !== 'draft' && item.future && timelineOk &&
          (mod === 'assign' || mod === 'quiz') && !timeline[item.id]) verdict = 'timeline';
      out[item.id] = { verdict: verdict, module: mod };
    } catch (e) {
      out[item.id] = { verdict: 'missing', module: '' };
    }
  }
  TugasQuest.postMessage(JSON.stringify({ ok: true, timelineOk: timelineOk, events: out }));
})().catch(function () { TugasQuest.postMessage('{"ok":false}'); });
''';

/// Memakai WebView tersembunyi dan sesi SSO yang sudah ada, tanpa menyimpan password.
class SubmissionChecker {
  SubmissionChecker(this.items) {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('TugasQuest', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) {
            final uri = Uri.tryParse(r.url);
            final trusted =
                uri != null &&
                uri.scheme == 'https' &&
                (uri.host == 'ub.ac.id' || uri.host.endsWith('.ub.ac.id'));
            return !r.isMainFrame || trusted
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageStarted: (_) => _loginTimer?.cancel(),
          onPageFinished: _onPage,
          onWebResourceError: (e) {
            if (e.isForMainFrame ?? false)
              _complete(const CheckResult(CheckStatus.failed));
          },
        ),
      );
  }

  /// Acara yang dicek, beserta apakah tenggatnya masih di masa depan.
  final List<({int id, bool future})> items;
  late final WebViewController controller;
  final _done = Completer<CheckResult>();
  Timer? _timeout, _loginTimer;
  bool _injected = false;

  Future<CheckResult> run() {
    _timeout = Timer(
      const Duration(seconds: 90),
      () => _complete(const CheckResult(CheckStatus.failed)),
    );
    controller.loadRequest(
      Uri.parse('https://brone.ub.ac.id/calendar/export.php'),
    );
    return _done.future;
  }

  void _complete(CheckResult result) {
    _timeout?.cancel();
    _loginTimer?.cancel();
    if (!_done.isCompleted) _done.complete(result);
  }

  Future<void> _onPage(String page) async {
    final uri = Uri.tryParse(page);
    if (uri?.scheme == 'https' &&
        uri?.host == 'brone.ub.ac.id' &&
        uri?.path == '/calendar/export.php') {
      if (_injected) return;
      _injected = true;
      final input = jsonEncode([
        for (final i in items) {'id': i.id, 'future': i.future},
      ]);
      try {
        await controller.runJavaScript(
          _script.replaceFirst('__INPUT__', input),
        );
      } on Exception {
        _complete(const CheckResult(CheckStatus.failed));
      }
      return;
    }
    // SSO bisa mengalihkan otomatis. Jika berhenti di halaman lain, berarti perlu login.
    _loginTimer?.cancel();
    _loginTimer = Timer(
      const Duration(seconds: 6),
      () => _complete(const CheckResult(CheckStatus.needsLogin)),
    );
  }

  void _onMessage(JavaScriptMessage message) =>
      _complete(parseCheckMessage(message.message, items.map((i) => i.id)));
}

/// Membaca balasan skrip, dan hanya menerima acara yang memang diminta.
CheckResult parseCheckMessage(String message, Iterable<int> requested) {
  try {
    final data = jsonDecode(message) as Map<String, dynamic>;
    if (data['ok'] != true) return const CheckResult(CheckStatus.failed);
    final allowed = requested.toSet();
    final events = <int, EventCheck>{};
    (data['events'] as Map<String, dynamic>).forEach((key, value) {
      final id = int.tryParse(key);
      if (id == null || !allowed.contains(id) || value is! Map) return;
      events[id] = EventCheck('${value['verdict']}', '${value['module']}');
    });
    return CheckResult(CheckStatus.ok, events, data['timelineOk'] == true);
  } on Object {
    return const CheckResult(CheckStatus.failed);
  }
}
