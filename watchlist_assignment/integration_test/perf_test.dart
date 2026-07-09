import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:watchlist_assignment/baseline/naive_watchlist_page.dart';
import 'package:watchlist_assignment/data/market_repository.dart';
import 'package:watchlist_assignment/domain/watchlist_store.dart';
import 'package:watchlist_assignment/seed/market_feed.dart';
import 'package:watchlist_assignment/ui/watchlist_page.dart';

const int _frames = 600;
const int _summaryEveryFrames = 6;

void _report(String label, List<FrameTiming> timings) {
  if (timings.isEmpty) {
    debugPrint('[$label] no frames captured');
    return;
  }
  final build = timings.map((t) => t.buildDuration.inMicroseconds).toList()..sort();
  final raster = timings.map((t) => t.rasterDuration.inMicroseconds).toList()..sort();
  double p(List<int> v, double q) => v[(v.length * q).clamp(0, v.length - 1).floor()] / 1000;
  int jank(List<int> v) => v.where((m) => m > 16667).length;
  debugPrint('[$label] frames=${timings.length}');
  debugPrint('[$label] build  avg=${(build.reduce((a, b) => a + b) / build.length / 1000).toStringAsFixed(2)}ms '
      'p50=${p(build, .5).toStringAsFixed(2)} p95=${p(build, .95).toStringAsFixed(2)} max=${p(build, 1).toStringAsFixed(2)} jank=${jank(build)}');
  debugPrint('[$label] raster avg=${(raster.reduce((a, b) => a + b) / raster.length / 1000).toStringAsFixed(2)}ms '
      'p50=${p(raster, .5).toStringAsFixed(2)} p95=${p(raster, .95).toStringAsFixed(2)} max=${p(raster, 1).toStringAsFixed(2)} jank=${jank(raster)}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('BASELINE device frame timings', (tester) async {
    final timings = <FrameTiming>[];
    void cb(List<FrameTiming> t) => timings.addAll(t);
    tester.binding.addTimingsCallback(cb);

    final feed = MarketFeed();
    await tester.pumpWidget(
      MaterialApp(home: NaiveWatchlistPage(feed: feed, autoStart: false)),
    );

    for (var i = 0; i < _frames; i++) {
      feed.pump(1);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    tester.binding.removeTimingsCallback(cb);
    feed.dispose();
    _report('BASELINE', timings);
  });

  testWidgets('IMPROVED device frame timings', (tester) async {
    final timings = <FrameTiming>[];
    void cb(List<FrameTiming> t) => timings.addAll(t);
    tester.binding.addTimingsCallback(cb);

    final store = WatchlistStore(MarketRepository())..init();
    await tester.pumpWidget(MaterialApp(home: WatchlistPage(store: store)));

    for (var i = 0; i < _frames; i++) {
      store.pumpForTest(1);
      if (i % _summaryEveryFrames == 0) store.flushSummaryForTest();
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));
    tester.binding.removeTimingsCallback(cb);
    store.dispose();
    _report('IMPROVED', timings);
  });
}
