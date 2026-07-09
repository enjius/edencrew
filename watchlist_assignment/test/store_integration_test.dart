import 'package:flutter_test/flutter_test.dart';
import 'package:watchlist_assignment/data/market_repository.dart';
import 'package:watchlist_assignment/domain/watchlist_store.dart';
import 'package:watchlist_assignment/seed/market_feed.dart';

void main() {
  test('스트림 에러가 와도 구독이 유지되고 다음 배치로 복구된다', () async {

    final store = WatchlistStore(
      MarketRepository(feed: MarketFeed(transientErrorProbability: 0.3)),
    )..init();
    addTearDown(store.dispose);

    final before = store.cellFor('000001').state.lastTimestampMs;
    store.pumpForTest(200);
    await Future<void>.delayed(Duration.zero);

    expect(store.summary.hasFeedError, isTrue);

    expect(store.cellFor('000001').state.lastTimestampMs, greaterThan(before));
  });

  test('시총 증분 집계가 전체 재합산과 일치한다', () async {
    final store = WatchlistStore(MarketRepository())..init();
    addTearDown(store.dispose);

    store.pumpForTest(300);
    await Future<void>.delayed(Duration.zero);

    final incremental = store.aggregates.totalMarketCap;

    var full = 0.0;
    for (final s in store.allStates) {
      full += s.marketCap;
    }
    expect((incremental - full).abs() / full, lessThan(1e-6));
  });

  test('Top-20은 등락률 내림차순, 동률이면 코드 오름차순', () async {
    final store = WatchlistStore(MarketRepository())..init();
    addTearDown(store.dispose);

    store.pumpForTest(300);
    await Future<void>.delayed(Duration.zero);

    final movers = store.aggregates.computeTopMovers(store.allStates);
    expect(movers.length, 20);
    for (var i = 1; i < movers.length; i++) {
      final prev = movers[i - 1];
      final cur = movers[i];
      final ordered = prev.changePercent > cur.changePercent ||
          (prev.changePercent == cur.changePercent &&
              prev.code.compareTo(cur.code) < 0);
      expect(ordered, isTrue);
    }
  });
}
