import '../seed/market_feed.dart';
import '../seed/market_models.dart';

class MarketRepository {
  MarketRepository({MarketFeed? feed}) : _feed = feed ?? MarketFeed();

  final MarketFeed _feed;

  List<SymbolInfo> get symbols => _feed.symbols;

  List<QuoteSnapshotEntry> loadSnapshot() => _feed.initialSnapshot();

  Stream<List<QuoteTick>> get ticks => _feed.ticks;

  void start() => _feed.start();

  void stop() => _feed.stop();

  void pump([int count = 1]) => _feed.pump(count);

  void dispose() => _feed.dispose();
}
