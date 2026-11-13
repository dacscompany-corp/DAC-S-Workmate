/// Download speed measured from what actually arrived over the last few
/// seconds. Nothing here is estimated up front: with too little to go on the
/// answer is null and the screen shows no speed.
class DownloadRate {
  final _samples = <(int ms, int bytes)>[];

  void reset() => _samples.clear();

  void add(int ms, int bytes) {
    _samples.add((ms, bytes));
    // Keep about three seconds: enough to be steady, short enough to follow the signal.
    while (_samples.length > 2 && ms - _samples[1].$1 >= 3000) {
      _samples.removeAt(0);
    }
  }

  double? get bytesPerSecond {
    if (_samples.length < 2) return null;
    final first = _samples.first, last = _samples.last;
    final ms = last.$1 - first.$1;
    if (ms < 500) return null;
    final rate = (last.$2 - first.$2) * 1000 / ms;
    return rate > 0 ? rate : null;
  }

  /// Whole seconds until [remainingBytes] arrive at the current speed.
  int? secondsLeft(int remainingBytes) {
    final rate = bytesPerSecond;
    return rate == null ? null : (remainingBytes / rate).ceil();
  }
}

const _mb = 1024 * 1024;

String formatMb(num bytes) => (bytes / _mb).toStringAsFixed(1);

String formatSpeed(double bytesPerSecond) =>
    bytesPerSecond >= _mb ? '${formatMb(bytesPerSecond)} MB/S' : '${(bytesPerSecond / 1024).round()} KB/S';

String formatTimeLeft(int seconds) => seconds < 60 ? '$seconds SEC LEFT' : '${(seconds / 60).ceil()} MIN LEFT';
