import 'package:flutter_test/flutter_test.dart';
import 'package:watchlist_assignment/domain/quote_state.dart';
import 'package:watchlist_assignment/seed/market_models.dart';

QuoteState _state() => QuoteState(
      code: '000001',
      name: '가온전자',
      market: MarketType.kospi,
      listedShares: 1000,
      previousClose: 1000,
      price: 1000,
      dayVolume: 0,
      lastTimestampMs: -1,
    );

QuoteTick _tick(double price, int ts, {int volume = 0, QuoteStatus status = QuoteStatus.active}) =>
    QuoteTick(code: '000001', price: price, dayVolume: volume, timestampMs: ts, status: status);

void main() {
  test('역순 tick: 더 오래된 timestamp는 최신 가격을 덮지 못한다', () {
    final cell = QuoteCell(_state());

    expect(cell.applyTick(_tick(1100, 100)), isTrue);
    expect(cell.state.price, 1100);

    expect(cell.applyTick(_tick(900, 50)), isFalse);
    expect(cell.state.price, 1100);

    expect(cell.applyTick(_tick(1200, 150)), isTrue);
    expect(cell.state.price, 1200);
  });

  test('거래정지 전이: halted 수신 시 상태 변경, active 수신 시 해제', () {
    final cell = QuoteCell(_state());

    cell.applyTick(_tick(1100, 100));
    expect(cell.state.isHalted, isFalse);

    expect(cell.applyTick(_tick(1100, 110, status: QuoteStatus.halted)), isTrue);
    expect(cell.state.isHalted, isTrue);

    expect(cell.applyTick(_tick(1100, 120)), isTrue);
    expect(cell.state.isHalted, isFalse);
  });

  test('값이 바뀌지 않은 tick은 notify하지 않는다', () {
    final cell = QuoteCell(_state());
    cell.applyTick(_tick(1100, 100, volume: 50));

    var notified = false;
    cell.addListener(() => notified = true);

    expect(cell.applyTick(_tick(1100, 110, volume: 50)), isFalse);
    expect(notified, isFalse);
  });

  test('고가/저가는 관측값으로 누적된다', () {
    final cell = QuoteCell(_state());
    cell.applyTick(_tick(1200, 100));
    cell.applyTick(_tick(900, 110));
    cell.applyTick(_tick(1050, 120));
    expect(cell.state.dayHigh, 1200);
    expect(cell.state.dayLow, 900);
  });
}
