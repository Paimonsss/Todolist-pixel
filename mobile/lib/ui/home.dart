import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/ical.dart';
import '../core/notifications.dart';
import '../core/store.dart';
import '../core/submission_checker.dart';
import '../core/sync.dart';
import '../core/task.dart';
import 'brone_login.dart';
import 'pixel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _store = Store();
  List<Task> _tasks = [];
  bool _connected = false, _notif = false, _syncing = false, _showDone = false;
  int? _lastSync;
  String? _lastError;
  Timer? _ticker;
  SubmissionChecker? _checker;
  bool _needsRelogin = false, _checkFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => mounted ? setState(() {}) : null,
    );
    _load().then((_) => _sync(silent: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      _load().then((_) => _checkSubmissions());
  }

  Future<void> _checkSubmissions({bool report = false}) async {
    if (_checker != null || !_connected) return;
    final ids = pendingEventIds(_tasks);
    if (ids.isEmpty) {
      if (report) _toast('Tidak ada tugas BRONE yang perlu dicek.');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final dueById = {
      for (final t in _tasks)
        if (t.isBrone && eventIdOf(t.uid) != null) eventIdOf(t.uid)!: t.dueAt,
    };
    final checker = SubmissionChecker([
      for (final id in ids) (id: id, future: (dueById[id] ?? 0) > now),
    ]);
    if (report) _toast('Mengecek status tugas di BRONE...');
    setState(() => _checker = checker);
    final result = await checker.run();
    if (!mounted) return;
    setState(() {
      _checker = null;
      _needsRelogin = result.status == CheckStatus.needsLogin;
      _checkFailed = result.status == CheckStatus.failed;
    });

    var changed = 0;
    if (result.status == CheckStatus.ok) {
      final tasks = await _store.loadTasks();
      changed = applySubmitted(tasks, result.submitted);
      if (changed > 0) {
        await _store.saveTasks(tasks);
        await SyncService.refreshReminders(_store);
        await _load();
      }
    }
    if (!mounted) return;
    if (report && result.status == CheckStatus.ok) {
      await _showCheckReport(result, changed);
    } else if (changed > 0) {
      _toast('$changed tugas sudah dikumpulkan dan ditandai selesai.');
    } else if (report) {
      _toast(switch (result.status) {
        CheckStatus.ok => 'Belum ada tugas baru yang terkumpul.',
        CheckStatus.needsLogin => 'Login BRONE lagi untuk mengecek tugas.',
        CheckStatus.failed => 'Gagal mengecek status tugas. Coba lagi.',
      });
    }
  }

  static String _verdictLabel(EventCheck? check) => switch (check?.verdict) {
    'submitted' => 'Sudah dikumpulkan',
    'timeline' => 'Sudah tidak ada di Timeline BRONE',
    'draft' => 'Masih draf, belum dikirim untuk dinilai',
    'open' => 'Belum dikumpulkan',
    'other' =>
      'Jenis ${check!.module.isEmpty ? 'lain' : check.module}, centang manual',
    'missing' => 'Tidak ditemukan di BRONE',
    _ => 'Belum terbaca',
  };

  Future<void> _showCheckReport(CheckResult result, int changed) {
    final checked =
        _tasks
            .where(
              (t) => t.isBrone && result.events.containsKey(eventIdOf(t.uid)),
            )
            .toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Px.paper,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Px.ink, width: 3),
        ),
        title: const Text('Hasil cek', style: Px.display),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                changed > 0
                    ? '$changed tugas ditandai selesai.'
                    : 'Tidak ada tugas baru yang ditandai selesai.',
                style: Px.body,
              ),
              if (!result.timelineOk)
                const Text(
                  'Timeline BRONE tidak terbaca, jadi hanya halaman tugas yang dicek.',
                  style: Px.note,
                ),
              const SizedBox(height: 8),
              for (final t in checked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${t.title}\n> ${_verdictLabel(result.events[eventIdOf(t.uid)])}',
                    style: Px.note.copyWith(color: t.done ? Px.green : Px.ink),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Oke', style: Px.body),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    final tasks = await _store.loadTasks();
    final url = await _store.calendarUrl();
    final last = await _store.lastSync();
    final err = await _store.lastError();
    final notif = await Notifications.enabled();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _connected = url != null;
      _lastSync = last;
      _lastError = err;
      _notif = notif;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Px.ink,
          shape: const RoundedRectangleBorder(),
          content: Text(message, style: Px.body.copyWith(color: Px.paper)),
        ),
      );
  }

  Future<void> _sync({bool silent = false}) async {
    if (_syncing || !_connected) return;
    setState(() => _syncing = true);
    await SyncService.run();
    await _load();
    if (!mounted) return;
    setState(() => _syncing = false);
    if (!silent) _toast(_lastError ?? 'Sinkron selesai.');
    await _checkSubmissions();
  }

  Future<void> _persist() async {
    await _store.saveTasks(_tasks);
    await SyncService.refreshReminders(_store);
    await _load();
  }

  Future<void> _connect() async {
    final url = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const BroneLoginPage()));
    if (url == null || !mounted) return;
    setState(() => _syncing = true);
    try {
      await fetchCalendar(url);
      await _store.setCalendarUrl(url);
      await Notifications.requestPermission();
      await SyncService.run();
      await _load();
      if (mounted) _toast('BRONE terhubung!');
    } on BroneException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    if (mounted) await _checkSubmissions(report: true);
  }

  Future<void> _disconnect() async {
    final ok = await _confirm(
      'Putuskan BRONE?',
      'Tugas yang sudah masuk tetap tersimpan.',
    );
    if (!ok) return;
    await _store.clearCalendarUrl();
    await WebViewCookieManager().clearCookies();
    _needsRelogin = false;
    await _load();
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Px.paper,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Px.ink, width: 3),
          ),
          title: Text(title, style: Px.display),
          content: Text(body, style: Px.body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal', style: Px.body),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ya', style: Px.body),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _addTask() async {
    final created = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Px.paper,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Px.ink, width: 3),
      ),
      builder: (_) => const _AddTaskSheet(),
    );
    if (created == null) return;
    _tasks = [..._tasks, created];
    await _persist();
  }

  Future<void> _toggle(Task t) async {
    t.done = !t.done;
    t.keepOpen = t.isBrone && !t.done;
    setState(() {});
    await _persist();
  }

  Future<void> _delete(Task t) async {
    if (!await _confirm('Hapus tugas?', t.title)) return;
    _tasks = _tasks.where((x) => x.id != t.id).toList();
    await _persist();
  }

  Future<void> _enableNotif() async {
    final ok = await Notifications.requestPermission();
    await _load();
    if (!mounted) return;
    if (ok) {
      await Notifications.show(
        'Notif aktif!',
        'Pengingat tugas akan muncul seperti ini.',
      );
      await SyncService.refreshReminders(_store);
    } else {
      _toast('Izinkan notifikasi lewat Pengaturan HP.');
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Px.paper,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Px.ink, width: 3),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              const Text('Pengaturan', style: Px.display),
              Text(
                !_connected
                    ? 'BRONE belum terhubung. Password UB tidak disimpan di aplikasi ini.'
                    : _lastError ??
                          'BRONE terhubung. Sinkron otomatis sekitar tiap 30 menit.',
                style: Px.note,
              ),
              if (_connected)
                PixelButton(
                  label: 'Cek pengumpulan',
                  sfx: 'CEK!',
                  expand: true,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _checkSubmissions(report: true);
                  },
                ),
              if (!_connected || _lastError != null || _needsRelogin)
                PixelButton(
                  label: 'Login BRONE',
                  sfx: 'LINK!',
                  color: Px.yellow,
                  expand: true,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _connect();
                  },
                ),
              if (_connected)
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: PixelButton(
                        label: 'Sinkron',
                        sfx: 'SYNC!',
                        expand: true,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _sync();
                        },
                      ),
                    ),
                    Expanded(
                      child: PixelButton(
                        label: 'Putuskan',
                        color: const Color(0xFFFFD9E2),
                        shadow: Px.red,
                        expand: true,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _disconnect();
                        },
                      ),
                    ),
                  ],
                ),
              Text(
                _notif
                    ? 'Notifikasi aktif di HP ini.'
                    : 'Notifikasi belum aktif.',
                style: Px.note,
              ),
              PixelButton(
                label: _notif ? 'Tes notif' : 'Aktifkan notif',
                sfx: 'DING!',
                expand: true,
                color: _notif ? Px.paper : Px.yellow,
                onPressed: () {
                  Navigator.pop(ctx);
                  _enableNotif();
                },
              ),
              const Text(
                'Pengingat muncul saat tugas baru masuk, lalu H-3, H-1, 6 jam, dan 1 jam sebelum tenggat.',
                style: Px.note,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final doneCount = _tasks.where((t) => t.done).length;
    final urgent = _tasks
        .where((t) => !t.done && t.dueAt > now && t.dueAt - now < 86400000)
        .length;
    final shown = _tasks.where((t) => t.done == _showDone).toList()
      ..sort(
        (a, b) =>
            _showDone ? b.dueAt.compareTo(a.dueAt) : a.dueAt.compareTo(b.dueAt),
      );

    final syncText = _syncing
        ? 'Menyinkronkan...'
        : _lastError != null
        ? 'Sinkron BRONE bermasalah'
        : _checker != null
        ? 'Mengecek pengumpulan...'
        : _checkFailed && _connected
        ? 'Cek pengumpulan gagal'
        : _lastSync != null && _connected
        ? 'Sinkron ${formatClock(_lastSync!)}'
        : 'BRONE belum terhubung';
    final banner = !_connected
        ? 'Login BRONE supaya tugas masuk otomatis >'
        : _lastError != null
        ? '$_lastError Ketuk untuk memperbaiki >'
        : _needsRelogin
        ? 'Login BRONE lagi untuk mengecek tugas yang sudah dikumpulkan >'
        : !_notif
        ? 'Aktifkan notifikasi supaya tidak ketinggalan >'
        : null;

    return Scaffold(
      backgroundColor: Px.bg,
      floatingActionButton: PixelButton(
        label: '+ Tugas',
        sfx: 'NEW!',
        color: Px.yellow,
        onPressed: _addTask,
      ),
      body: GridBackground(
        child: Stack(
          children: [
            // WebView harus ada di layar agar Android menjalankan pengecekan.
            if (_checker != null)
              Positioned(
                left: 0,
                top: 0,
                width: 1,
                height: 1,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Opacity(
                      opacity: .01,
                      child: WebViewWidget(controller: _checker!.controller),
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: RefreshIndicator(
                color: Px.ink,
                backgroundColor: Px.yellow,
                onRefresh: () => _connected ? _sync() : _load(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 104),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tugas Quest',
                                style: Px.display.copyWith(fontSize: 19),
                              ),
                              const SizedBox(height: 3),
                              Text(syncText, style: Px.note),
                            ],
                          ),
                        ),
                        PixelButton(
                          label: '',
                          icon: Icons.settings,
                          semanticLabel: 'Pengaturan',
                          onPressed: _openSettings,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    PixelPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 8,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$doneCount / ${_tasks.length} selesai',
                                style: Px.body,
                              ),
                              if (urgent > 0)
                                Text(
                                  '$urgent tugas < 24 jam',
                                  style: Px.body.copyWith(color: Px.darkRed),
                                ),
                            ],
                          ),
                          _XpBar(
                            value: _tasks.isEmpty
                                ? 0
                                : doneCount / _tasks.length,
                          ),
                        ],
                      ),
                    ),
                    if (banner != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        button: true,
                        child: InkWell(
                          onTap:
                              !_connected || _lastError != null || _needsRelogin
                              ? _connect
                              : _enableNotif,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3C9),
                              border: Border.all(color: Px.ink, width: 3),
                            ),
                            child: Text(banner, style: Px.body),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: _Tab(
                            label: 'Aktif',
                            active: !_showDone,
                            onTap: () => setState(() => _showDone = false),
                          ),
                        ),
                        Expanded(
                          child: _Tab(
                            label: 'Selesai',
                            active: _showDone,
                            onTap: () => setState(() => _showDone = true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (shown.isEmpty)
                      PixelPanel(
                        shadow: Px.grid,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            _showDone
                                ? 'Belum ada quest yang selesai.'
                                : 'Tidak ada tugas aktif. Aman!',
                            textAlign: TextAlign.center,
                            style: Px.note,
                          ),
                        ),
                      ),
                    for (final t in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TaskCard(
                          task: t,
                          now: now,
                          onToggle: () => _toggle(t),
                          onDelete: () => _delete(t),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _XpBar extends StatelessWidget {
  const _XpBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Container(
    height: 18,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Px.grid,
      border: Border.all(color: Px.ink, width: 3),
    ),
    child: Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0, 1),
        child: const ColoredBox(color: Px.green, child: SizedBox.expand()),
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Px.ink : Px.paper,
          border: Border.all(color: Px.ink, width: 3),
        ),
        child: Text(
          label,
          style: Px.display.copyWith(color: active ? Px.paper : Px.ink),
        ),
      ),
    ),
  );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.now,
    required this.onToggle,
    required this.onDelete,
  });
  final Task task;
  final int now;
  final VoidCallback onToggle, onDelete;

  (String, Color, Color) _due() {
    if (task.done) return ('Selesai', Px.grid, Px.ink);
    final left = task.dueAt - now;
    if (left <= 0) return ('Lewat tenggat', Px.darkRed, Colors.white);
    if (left < 3600000)
      return ('${(left / 60000).ceil()} menit lagi', Px.darkRed, Colors.white);
    final hours = left ~/ 3600000;
    if (hours < 24) return ('$hours jam lagi', Px.darkRed, Colors.white);
    final days = hours ~/ 24;
    return ('$days hari lagi', days < 3 ? Px.yellow : Px.grid, Px.ink);
  }

  @override
  Widget build(BuildContext context) {
    final (text, bg, fg) = _due();
    final late = !task.done && task.dueAt <= now;
    return PixelPanel(
      border: late ? Px.red : Px.ink,
      shadow: late ? const Color(0xFFFFC2D0) : Px.lav,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          _CheckBox(checked: task.done, title: task.title, onTap: onToggle),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 5,
              children: [
                Text(
                  task.title,
                  style: Px.body.copyWith(
                    fontSize: 25,
                    height: 1.05,
                    color: task.done ? Px.muted : Px.ink,
                    decoration: task.done ? TextDecoration.lineThrough : null,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Badge(text, bg, fg),
                    if (task.isBrone)
                      _Badge(
                        task.course.isEmpty ? 'BRONE' : task.course,
                        Px.ink,
                        Px.paper,
                      ),
                  ],
                ),
                Text(
                  formatDue(task.dueAt),
                  style: Px.note.copyWith(fontSize: 20),
                ),
                if (task.isBrone)
                  InkWell(
                    onTap: () => launchUrl(
                      Uri.https('brone.ub.ac.id', '/calendar/view.php', {
                        'view': 'day',
                        'time': '${task.dueAt ~/ 1000}',
                      }),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'Buka di BRONE >',
                        style: Px.body.copyWith(
                          fontSize: 20,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!task.isBrone)
            IconButton(
              onPressed: onDelete,
              tooltip: 'Hapus',
              icon: const Icon(Icons.close, color: Px.muted),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.bg, this.fg);
  final String text;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    color: bg,
    child: Text(text, style: Px.body.copyWith(fontSize: 20, color: fg)),
  );
}

class _CheckBox extends StatefulWidget {
  const _CheckBox({
    required this.checked,
    required this.title,
    required this.onTap,
  });
  final bool checked;
  final String title;
  final VoidCallback onTap;

  @override
  State<_CheckBox> createState() => _CheckBoxState();
}

class _CheckBoxState extends State<_CheckBox> {
  void _tap() {
    final box = context.findRenderObject() as RenderBox?;
    if (!widget.checked && box != null) {
      PixelBurst.show(
        context,
        box.localToGlobal(box.size.center(Offset.zero)),
        'CLEAR!',
      );
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    checked: widget.checked,
    label:
        'Tandai ${widget.title} ${widget.checked ? 'belum selesai' : 'selesai'}',
    excludeSemantics: true,
    onTap: _tap,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: widget.checked ? Px.green : Colors.white,
            border: Border.all(color: Px.ink, width: 3),
            boxShadow: const [BoxShadow(color: Px.lav, offset: Offset(3, 3))],
          ),
          child: widget.checked
              ? const Icon(Icons.check, color: Px.ink, size: 26)
              : null,
        ),
      ),
    ),
  );
}

class _AddTaskSheet extends StatefulWidget {
  const _AddTaskSheet();

  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  final _title = TextEditingController();
  DateTime? _due;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
      initialDate: _due ?? now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 59),
    );
    if (time == null || !mounted) return;
    setState(
      () => _due = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void _save() {
    final title = _title.text.trim();
    final due = _due;
    if (title.isEmpty)
      return setState(() => _error = 'Nama tugas wajib diisi.');
    if (due == null || !due.isAfter(DateTime.now()))
      return setState(() => _error = 'Pilih tenggat di masa depan.');
    Navigator.pop(
      context,
      Task(
        id: 'm:${DateTime.now().microsecondsSinceEpoch}',
        source: 'manual',
        title: title,
        dueAt: due.millisecondsSinceEpoch,
        announced: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            const Text('Tugas baru', style: Px.display),
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: 200,
              style: Px.body,
              decoration: const InputDecoration(
                labelText: 'Nama tugas',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(width: 3),
                ),
              ),
            ),
            PixelButton(
              label: _due == null
                  ? 'Pilih tenggat'
                  : formatDue(_due!.millisecondsSinceEpoch),
              expand: true,
              onPressed: _pickDue,
            ),
            if (_error != null)
              Text(_error!, style: Px.body.copyWith(color: Px.darkRed)),
            PixelButton(
              label: 'Simpan',
              sfx: 'OK!',
              color: Px.yellow,
              expand: true,
              onPressed: _save,
            ),
          ],
        ),
      ),
    ),
  );
}
