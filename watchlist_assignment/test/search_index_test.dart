import 'package:flutter_test/flutter_test.dart';
import 'package:watchlist_assignment/domain/quote_state.dart';
import 'package:watchlist_assignment/domain/search_index.dart';
import 'package:watchlist_assignment/seed/market_models.dart';

QuoteState _state(String code, String name) => QuoteState(
      code: code,
      name: name,
      market: MarketType.kospi,
      listedShares: 1000,
      previousClose: 1000,
      price: 1000,
      dayVolume: 0,
      lastTimestampMs: -1,
    );

void main() {
  final index = SearchIndex.build([
    _state('000001', '가온전자'),
    _state('000002', '나래화학'),
    _state('000003', '가온화학'),
    _state('000590', '다온전자'),
  ]);

  test('초성 검색: ㄱㅇ → 가온으로 시작하는 종목', () {
    final codes = index.match('ㄱㅇ');
    expect(codes, containsAll(['000001', '000003']));
    expect(codes, isNot(contains('000002')));
  });

  test('초성 검색: ㄴㄹㅎㅎ → 나래화학', () {
    expect(index.match('ㄴㄹㅎㅎ'), ['000002']);
  });

  test('초성 검색: ㄱㅇㅈㅈ → 가온전자', () {
    expect(index.match('ㄱㅇㅈㅈ'), ['000001']);
  });

  test('완성형 부분일치: 전자', () {
    expect(index.match('전자'), containsAll(['000001', '000590']));
  });

  test('종목코드 부분일치: 000590', () {
    expect(index.match('000590'), ['000590']);
  });

  test('혼합 입력: 가ㅇ → 가 뒤에 초성 ㅇ이 이어지는 종목', () {
    final codes = index.match('가ㅇ');
    expect(codes, containsAll(['000001', '000003']));
    expect(codes, isNot(contains('000002')));
  });

  test('빈 검색어는 전체를 순서대로 반환', () {
    expect(index.match(''), ['000001', '000002', '000003', '000590']);
  });
}
