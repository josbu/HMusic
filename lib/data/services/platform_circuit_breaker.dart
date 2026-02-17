import '../../core/utils/platform_id.dart';

class PlatformCircuitBreaker {
  PlatformCircuitBreaker({this.failureThreshold = 3});

  final int failureThreshold;
  final Map<String, int> _failCounts = <String, int>{};
  final Set<String> _openPlatforms = <String>{};

  List<String> adjustOrder(List<String> original) {
    final normalized = original.map(PlatformId.normalize).toList();
    final available = normalized.where((p) => !_openPlatforms.contains(p)).toList();
    final opened = normalized.where(_openPlatforms.contains).toList();

    if (available.isEmpty) {
      reset();
      return normalized;
    }

    return <String>[...available, ...opened];
  }

  void recordFailure(String platform) {
    final key = PlatformId.normalize(platform);
    final next = (_failCounts[key] ?? 0) + 1;
    _failCounts[key] = next;
    if (next >= failureThreshold) {
      _openPlatforms.add(key);
    }
  }

  void recordSuccess(String platform) {
    final key = PlatformId.normalize(platform);
    _failCounts.remove(key);
    _openPlatforms.remove(key);
  }

  bool isOpen(String platform) =>
      _openPlatforms.contains(PlatformId.normalize(platform));

  int failureCount(String platform) =>
      _failCounts[PlatformId.normalize(platform)] ?? 0;

  void reset() {
    _failCounts.clear();
    _openPlatforms.clear();
  }
}
