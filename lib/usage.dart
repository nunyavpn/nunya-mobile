/// How much traffic each server has carried, by day: a port of desktop Nunya's `src/usage.ts`.
///
/// The source is the tunnel's byte counters, cumulative since it came up, so what one poll adds
/// is the difference from the last. Differences are filed under the server the tunnel ran on and
/// the local day, and kept on the server itself, so the history lives exactly as long as it does.
/// Days rather than finer buckets: the questions are "how much this month" and "which server do I
/// actually use", and a day per server is a few dozen bytes however long the app runs.
library;

import 'dart:math' as math;

typedef Bytes = ({int up, int down});

/// A server's history: local day (`2026-09-21`) to what it carried that day.
typedef Usage = Map<String, Bytes>;

/// The tunnel's cumulative counters.
typedef Counters = ({int uplink, int downlink});

/// The local calendar day: "today" should be the user's today, and a day that turned over at
/// 03:30 local time would split one evening across two bars.
String dayKey(DateTime t) {
  String pad(int n) => n.toString().padLeft(2, '0');
  final d = t.toLocal();
  return '${d.year}-${pad(d.month)}-${pad(d.day)}';
}

/// What moved between two readings. The counters only grow while one engine runs; a reading lower
/// than the last means it started again, so that reading is the whole difference rather than a
/// negative number that would subtract from a day.
Bytes advance(Counters previous, Counters current) {
  int step(int before, int now) =>
      now >= before ? now - before : math.max(0, now);
  return (
    up: step(previous.uplink, current.uplink),
    down: step(previous.downlink, current.downlink),
  );
}

/// Adds traffic to a history under the day [at] falls on.
void addUsage(Usage history, DateTime at, Bytes bytes) {
  if (bytes.up <= 0 && bytes.down <= 0) return;
  final day = dayKey(at);
  final today = history[day] ?? (up: 0, down: 0);
  history[day] = (
    up: today.up + math.max(0, bytes.up),
    down: today.down + math.max(0, bytes.down),
  );
}

/// Everything in one or more histories, optionally only from [sinceDay] on.
Bytes total(Iterable<Usage> histories, [String? sinceDay]) {
  var (up, down) = (0, 0);
  for (final history in histories) {
    for (final MapEntry(key: day, value: bytes) in history.entries) {
      if (sinceDay != null && day.compareTo(sinceDay) < 0) continue;
      up += bytes.up;
      down += bytes.down;
    }
  }
  return (up: up, down: down);
}

/// The earliest day any of the histories has, or null for none.
String? firstDay(Iterable<Usage> histories) {
  String? first;
  for (final day in histories.expand((h) => h.keys)) {
    if (first == null || day.compareTo(first) < 0) first = day;
  }
  return first;
}

/// The day [back] calendar days before [now]'s, stepping the calendar rather than subtracting
/// 24-hour strides, which land on the wrong day either side of a daylight-saving change.
String daysAgo(int back, DateTime now) {
  final t = now.toLocal();
  return dayKey(DateTime(t.year, t.month, t.day - back, 12));
}

/// The last [days] days up to and including today, oldest first, summed across histories. Every
/// day is present, zero when nothing moved: a chart that skipped quiet days would put last
/// Tuesday next to today and read as a busy week.
List<({String day, int up, int down})> lastDays(
  Iterable<Usage> histories,
  int days,
  DateTime now,
) => [
  for (var back = days - 1; back >= 0; back--)
    () {
      final day = daysAgo(back, now);
      var (up, down) = (0, 0);
      for (final h in histories) {
        up += h[day]?.up ?? 0;
        down += h[day]?.down ?? 0;
      }
      return (day: day, up: up, down: down);
    }(),
];

/// A round number at or above [value] for the top of a chart: 1, 2 or 5 times a power of ten in
/// whichever 1024-based unit the value is in, so gridlines read cleanly ("500 MB", "2 GB").
/// A thousand of a unit becomes one of the next — "1 GB", not "1000 MB".
int niceCeiling(int value) {
  if (value <= 0) return 1024 * 1024;
  var unit = 1;
  while (value >= unit * 1024 && unit < math.pow(1024, 4)) {
    unit *= 1024;
  }
  final scaled = value / unit;
  final magnitude = math
      .pow(10, (math.log(scaled) / math.ln10).floor())
      .toDouble();
  final step = [1, 2, 5, 10].firstWhere((s) => s * magnitude >= scaled);
  final round = step * magnitude;
  return round >= 1000 && unit < math.pow(1024, 4)
      ? unit * 1024
      : (round * unit).round();
}

const _sizeUnits = ['B', 'KB', 'MB', 'GB', 'TB'];

/// Keeps the digit count roughly constant so a number updating in place does not jitter.
String size(num bytes) {
  var v = math.max(0, bytes).toDouble();
  var i = 0;
  while (v >= 1024 && i < _sizeUnits.length - 1) {
    v /= 1024;
    i++;
  }
  final text = i == 0 || v >= 100
      ? v.round().toString()
      : v.toStringAsFixed(v >= 10 ? 1 : 2);
  return '$text ${_sizeUnits[i]}';
}
