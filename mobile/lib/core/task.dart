class Task {
  Task({
    required this.id,
    required this.source,
    required this.title,
    required this.dueAt,
    this.uid = '',
    this.course = '',
    this.done = false,
    this.announced = false,
    this.dueChanged = false,
    this.keepOpen = false,
  });

  final String id;
  final String source; // 'brone' atau 'manual'
  final String uid;
  String title;
  String course;
  int dueAt;
  bool done;
  bool announced;
  bool dueChanged;

  /// Pengguna membuka lagi tugas ini, jadi pengecekan otomatis tidak menandainya selesai.
  bool keepOpen;

  bool get isBrone => source == 'brone';

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'uid': uid,
    'title': title,
    'course': course,
    'dueAt': dueAt,
    'done': done,
    'announced': announced,
    'dueChanged': dueChanged,
    'keepOpen': keepOpen,
  };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
    id: j['id'] as String,
    source: j['source'] as String,
    uid: j['uid'] as String? ?? '',
    title: j['title'] as String,
    course: j['course'] as String? ?? '',
    dueAt: j['dueAt'] as int,
    done: j['done'] as bool? ?? false,
    announced: j['announced'] as bool? ?? false,
    dueChanged: j['dueChanged'] as bool? ?? false,
    keepOpen: j['keepOpen'] as bool? ?? false,
  );
}

class CalendarEvent {
  CalendarEvent({
    required this.uid,
    required this.title,
    required this.dueAt,
    this.course = '',
  });
  final String uid;
  final String title;
  final int dueAt;
  final String course;
}

/// Menggabungkan kalender BRONE ke daftar tugas tanpa mengubah status selesai.
List<Task> mergeFeed(List<Task> tasks, List<CalendarEvent> events, int now) {
  final existing = {for (final t in tasks.where((t) => t.isBrone)) t.uid: t};
  final seen = <String>{};
  final added = <Task>[];

  for (final e in events) {
    seen.add(e.uid);
    final task = existing[e.uid];
    if (task != null) {
      task.title = e.title;
      task.course = e.course;
      if (task.dueAt != e.dueAt) {
        task.dueAt = e.dueAt;
        if (!task.done) {
          task.announced = false;
          task.dueChanged = true;
        }
      }
    } else if (e.dueAt > now) {
      added.add(
        Task(
          id: 'b:${e.uid}',
          source: 'brone',
          uid: e.uid,
          title: e.title,
          course: e.course,
          dueAt: e.dueAt,
        ),
      );
    }
  }

  // Tugas mendatang yang hilang dari BRONE berarti dihapus dosen.
  final kept = tasks.where(
    (t) => !t.isBrone || seen.contains(t.uid) || t.done || t.dueAt <= now,
  );
  return [...kept, ...added];
}

/// UID kalender Moodle berbentuk `<idAcara>@<host>`.
int? eventIdOf(String uid) {
  final m = RegExp(r'^(\d+)@').firstMatch(uid);
  return m == null ? null : int.tryParse(m[1]!);
}

/// Acara BRONE yang masih aktif dan perlu dicek status pengumpulannya.
List<int> pendingEventIds(List<Task> tasks, {int limit = 30}) {
  final pending =
      tasks
          .where(
            (t) =>
                t.isBrone && !t.done && !t.keepOpen && eventIdOf(t.uid) != null,
          )
          .toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return pending.take(limit).map((t) => eventIdOf(t.uid)!).toList();
}

/// Menandai selesai tugas yang sudah dikumpulkan, dan mengembalikan jumlahnya.
int applySubmitted(List<Task> tasks, Set<int> submitted) {
  var changed = 0;
  for (final t in tasks) {
    if (t.isBrone &&
        !t.done &&
        !t.keepOpen &&
        submitted.contains(eventIdOf(t.uid))) {
      t.done = true;
      changed++;
    }
  }
  return changed;
}

const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

DateTime _wib(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms + 7 * 3600000, isUtc: true);
String _two(int n) => n.toString().padLeft(2, '0');

String formatDue(int ms) {
  final d = _wib(ms);
  return '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}, ${_two(d.hour)}:${_two(d.minute)} WIB';
}

String formatClock(int ms) {
  final d = _wib(ms);
  return '${_two(d.hour)}:${_two(d.minute)} WIB';
}
