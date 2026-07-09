import '../lib/seed/market_feed.dart';
import '../lib/seed/market_models.dart';

Future<void> main() async {
  final feed = MarketFeed();

  final symbols = feed.symbols;
  final names = symbols.map((s) => s.name).toSet();
  final snapshot = feed.initialSnapshot();
  final prices = snapshot.map((e) => e.price).toList()..sort();
  print('=== 유니버스 ===');
  print('종목 수: ${symbols.length}');
  print('고유 종목명 수: ${names.length} (중복 존재 여부 확인용)');
  print('코드 범위: ${symbols.first.code} ~ ${symbols.last.code}');
  print('가격 범위: ${prices.first} ~ ${prices.last}');

  var batches = 0, ticks = 0, halted = 0, outOfOrder = 0, errors = 0;
  var minBatch = 1 << 30, maxBatch = 0;
  final lastTs = <String, int>{};
  final updateCount = <String, int>{};
  final haltedSymbols = <String>{};

  feed.ticks.listen((batch) {
    batches++;
    ticks += batch.length;
    if (batch.length < minBatch) minBatch = batch.length;
    if (batch.length > maxBatch) maxBatch = batch.length;
    for (final t in batch) {
      updateCount[t.code] = (updateCount[t.code] ?? 0) + 1;
      if (t.status == QuoteStatus.halted) {
        halted++;
        haltedSymbols.add(t.code);
      }
      final prev = lastTs[t.code];
      if (prev != null && t.timestampMs < prev) {
        outOfOrder++;
      } else {
        lastTs[t.code] = t.timestampMs;
      }
    }
  }, onError: (_) => errors++);

  feed.pump(600);

  await Future<void>.delayed(Duration.zero);

  final counts = updateCount.values.toList()..sort();
  final untouched = symbols.length - updateCount.length;
  print('\n=== 10초 분량(600배치) 실측 ===');
  print('배치 수: $batches, 총 tick: $ticks (평균 ${(ticks / batches).toStringAsFixed(1)}/batch, min $minBatch / max $maxBatch)');
  print('초당 tick: ${(ticks / 10).toStringAsFixed(0)}');
  print('역순(out-of-order) tick: $outOfOrder');
  print('halted tick: $halted (정지 관측 종목 ${haltedSymbols.length}개)');
  print('스트림 에러: $errors (기본 transientErrorProbability=0)');
  print('한 번도 갱신 안 된 종목: $untouched');
  print('종목당 갱신 횟수: 중앙값 ${counts[counts.length ~/ 2]}, min ${counts.first}, max ${counts.last}');
  print('→ 평균 갱신 간격: ${(10000 / (ticks / symbols.length)).toStringAsFixed(0)}ms/종목');

  final errFeed = MarketFeed(transientErrorProbability: 0.1);
  var errCount = 0, batchAfterErr = 0, sawErr = false;
  errFeed.ticks.listen((b) {
    if (sawErr) batchAfterErr++;
  }, onError: (_) {
    errCount++;
    sawErr = true;
  });
  errFeed.pump(100);
  await Future<void>.delayed(Duration.zero);
  print('\n=== transientErrorProbability=0.1, 100배치 ===');
  print('에러 수: $errCount, 첫 에러 이후에도 수신된 배치: $batchAfterErr (구독 생존 확인)');

  feed.dispose();
  errFeed.dispose();
}
