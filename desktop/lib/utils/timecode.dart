/// Formats remaining streaming time the way a camera shows it: HH:MM:SS.
///
/// Uses the same conversion as `CreditDisplay.toTime` for realtime streams
/// (1 credit = 0.5 seconds), so both always agree.
class Timecode {
  static const double _secondsPerCredit = 0.50;

  static Duration fromCredits(double credits) {
    final secs = (credits * _secondsPerCredit).floor();
    return Duration(seconds: secs < 0 ? 0 : secs);
  }

  /// `00:08:20`
  static String format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  static String fromCreditsString(double credits) =>
      format(fromCredits(credits));

  /// Compact form for tight spaces: `8:20` or `1:05:09`.
  static String compact(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  }
}
