import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchlist_assignment/baseline/naive_watchlist_page.dart';
import 'package:watchlist_assignment/data/market_repository.dart';
import 'package:watchlist_assignment/domain/watchlist_store.dart';
import 'package:watchlist_assignment/seed/market_feed.dart';
import 'package:watchlist_assignment/ui/watchlist_page.dart';

const int _frames = 600;
const int _summaryEveryFrames = 6;

Map<String, double> _stats(List<int> micros) {
  final sorted = [...micros]..sort();
  final n = sorted.length;
  final avg = sorted.reduce((a, b) => a + b) / n / 1000;
  final p50 = sorted[(n * 0.50).floor()] / 1000;
  final p95 = sorted[(n * 0.95).floor()] / 1000;
  final max = sorted.last / 1000;
  final jank = sorted.where((m) => m > 16667).length.toDouble();
  return {'avg': avg, 'p50': p50, 'p95': p95, 'max': max, 'jank': jank};
}

void _report(String label, Map<String, double> s) {
  debugPrint('[$label] avg=${s['avg']!.toStringAsFixed(2)}ms '
      'p50=${s['p50']!.toStringAsFixed(2)}ms '
      'p95=${s['p95']!.toStringAsFixed(2)}ms '
      'max=${s['max']!.toStringAsFixed(2)}ms '
      'jank(>16.7ms)=${s['jank']!.toInt()}/$_frames');
}

void main() {
  testWidgets('BASELINE naive frame times', (tester) async {
    final feed = MarketFeed();
    addTearDown(feed.dispose);
    await tester.pumpWidget(
      MaterialApp(home: NaiveWatchlistPage(feed: feed, autoStart: false)),
    );

    final times = <int>[];
    for (var i = 0; i < _frames; i++) {
      feed.pump(1);
      final sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }
    _report('BASELINE', _stats(times));
  });

  testWidgets('IMPROVED frame times', (tester) async {
    final store = WatchlistStore(MarketRepository())..init();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: WatchlistPage(store: store)));

    final times = <int>[];
    for (var i = 0; i < _frames; i++) {
      store.pumpForTest(1);
      if (i % _summaryEveryFrames == 0) store.flushSummaryForTest();
      final sw = Stopwatch()..start();
      await tester.pump();
      sw.stop();
      times.add(sw.elapsedMicroseconds);
    }
    _report('IMPROVED', _stats(times));
  });
}
