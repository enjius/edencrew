import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/market_repository.dart';
import '../seed/market_models.dart';
import 'aggregates.dart';
import 'quote_state.dart';
import 'search_index.dart';

class SummaryNotifier extends ChangeNotifier {
  double totalMarketCap = 0;
  List<TopMover> topMovers = const [];
  bool hasFeedError = false;

  void update({
    required double totalMarketCap,
    required List<TopMover> topMovers,
  }) {
    this.totalMarketCap = totalMarketCap;
    this.topMovers = topMovers;
    notifyListeners();
  }

  void setFeedError(bool value) {
    if (hasFeedError == value) return;
    hasFeedError = value;
    notifyListeners();
  }
}

class WatchlistStore {
  WatchlistStore(this._repo);

  final MarketRepository _repo;

  final Map<String, QuoteCell> _cells = {};
  final List<QuoteState> _allStates = [];
  late final List<String> _allCodes;

  final Aggregates _aggregates = Aggregates();
  late final SearchIndex _searchIndex;

  final SummaryNotifier summary = SummaryNotifier();

  final ValueNotifier<List<String>> visibleCodes = ValueNotifier(const []);

  StreamSubscription<List<QuoteTick>>? _sub;
  Timer? _summaryTimer;
  Timer? _errorBannerTimer;
  bool _summaryDirty = false;
  int _batchesSinceRecompute = 0;

  static const int _recomputeEveryBatches = 600;

  QuoteCell cellFor(String code) => _cells[code]!;
  Aggregates get aggregates => _aggregates;
  List<QuoteState> get allStates => _allStates;

  void init() {
    for (final entry in _repo.loadSnapshot()) {
      final state = QuoteState.fromSnapshot(entry);
      _cells[state.code] = QuoteCell(state);
      _allStates.add(state);
    }
    _allCodes = [for (final s in _allStates) s.code];
    _aggregates.seed(_allStates);
    _searchIndex = SearchIndex.build(_allStates);

    visibleCodes.value = _allCodes;
    summary.update(
      totalMarketCap: _aggregates.totalMarketCap,
      topMovers: _aggregates.computeTopMovers(_allStates),
    );

    _sub = _repo.ticks.listen(_onBatch, onError: _onError);
  }

  void start() {
    _summaryTimer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _flushSummary(),
    );
    _repo.start();
  }

  void pumpForTest(int batches) => _repo.pump(batches);

  void flushSummaryForTest() => _flushSummary();

  void _onBatch(List<QuoteTick> batch) {
    for (final tick in batch) {
      final cell = _cells[tick.code];
      if (cell == null) continue;

      final state = cell.state;
      final oldPrice = state.price;
      final changed = cell.applyTick(tick);
      if (!changed) continue;

      if (state.price != oldPrice) {
        _aggregates.onPriceChanged(oldPrice, state.price, state.listedShares);
      }
      _summaryDirty = true;
    }

    if (++_batchesSinceRecompute >= _recomputeEveryBatches) {
      _aggregates.recomputeTotal(_allStates);
      _batchesSinceRecompute = 0;
    }
  }

  void _flushSummary() {
    if (!_summaryDirty) return;
    _summaryDirty = false;
    summary.update(
      totalMarketCap: _aggregates.totalMarketCap,
      topMovers: _aggregates.computeTopMovers(_allStates),
    );
  }

  void _onError(Object error, StackTrace stackTrace) {
    summary.setFeedError(true);
    _errorBannerTimer?.cancel();
    _errorBannerTimer = Timer(
      const Duration(seconds: 3),
      () => summary.setFeedError(false),
    );
  }

  void search(String query) {
    final q = query.trim();
    visibleCodes.value = q.isEmpty ? _allCodes : _searchIndex.match(q);
  }

  void dispose() {
    _sub?.cancel();
    _summaryTimer?.cancel();
    _errorBannerTimer?.cancel();
    _repo.dispose();
    summary.dispose();
    visibleCodes.dispose();
    for (final cell in _cells.values) {
      cell.dispose();
    }
  }
}
