import 'package:flutter_test/flutter_test.dart';
import 'package:hmusic/data/services/platform_circuit_breaker.dart';

void main() {
  group('PlatformCircuitBreaker', () {
    test('连续失败达到阈值后熔断并降级排序', () {
      final breaker = PlatformCircuitBreaker(failureThreshold: 3);

      breaker.recordFailure('tx');
      breaker.recordFailure('tx');
      expect(breaker.isOpen('tx'), isFalse);

      breaker.recordFailure('tx');
      expect(breaker.isOpen('tx'), isTrue);

      final order = breaker.adjustOrder(const ['tx', 'kw', 'wy']);
      expect(order, const ['kw', 'wy', 'tx']);
    });

    test('成功后清除熔断状态', () {
      final breaker = PlatformCircuitBreaker(failureThreshold: 2);

      breaker.recordFailure('kw');
      breaker.recordFailure('kw');
      expect(breaker.isOpen('kw'), isTrue);

      breaker.recordSuccess('kw');
      expect(breaker.isOpen('kw'), isFalse);
      expect(breaker.failureCount('kw'), 0);
    });

    test('全部平台熔断时自动重置', () {
      final breaker = PlatformCircuitBreaker(failureThreshold: 1);
      breaker.recordFailure('tx');
      breaker.recordFailure('kw');
      breaker.recordFailure('wy');

      final order = breaker.adjustOrder(const ['tx', 'kw', 'wy']);
      expect(order, const ['tx', 'kw', 'wy']);
      expect(breaker.isOpen('tx'), isFalse);
      expect(breaker.isOpen('kw'), isFalse);
      expect(breaker.isOpen('wy'), isFalse);
    });
  });
}
