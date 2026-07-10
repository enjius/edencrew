# 실시간 관심종목 (watchlist_assignment)

제공된 `MarketFeed`를 실시간 시세 소스로 사용해 2,000개 관심종목을 보여주는 Flutter 앱이다.

두 가지가 핵심 과제였다.

- **정합성** — 지연·역순 tick이 와도 가격과 상태가 과거로 되돌아가지 않게 한다.
- **성능** — 초당 최대 약 15,000건의 갱신에도 스크롤과 화면 갱신이 부드럽게 유지되게 한다.

설계 판단의 근거와 트레이드오프는 [`DESIGN.md`](DESIGN.md), 성능 측정 결과는 [`PERF.md`](PERF.md)에 정리했다.

## 주요 기능

- 2,000개 종목 실시간 목록 (현재가·등락률·거래량·거래정지 상태)
- 전체 기준 시가총액 합계와 급상승 Top-20 (100ms coalescing)
- 초성·완성형 한글·종목코드·혼합 검색 (예: `ㄱㅇ`, `전자`, `000590`, `가ㅇ`)
- 종목 상세 화면 (등락·고저가·최근 가격 스파크라인)
- 스트림 오류 시 구독을 유지한 채 배너 안내 후 자동 복구

## 실행

```bash
flutter pub get
flutter run                    # 개발 실행 (개선본: lib/main.dart)
flutter run --profile          # 성능 확인은 profile 모드 권장
```

## 검증

```bash
flutter analyze                # 정적 분석 (0 issues)
flutter test                   # 단위·위젯·벤치 테스트 전체
```

## 성능 측정

같은 seed의 동일 tick 수열로 baseline(순진한 전체 rebuild 구현)과 개선본을 비교한다. 자세한 수치·해석은 [`PERF.md`](PERF.md) 참고.

```bash
# 기기 profile 실측 (주 증거)
flutter drive \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/perf_test.dart \
  -d <deviceId> --profile

# host 상대 비교 (보조)
flutter test test/perf_benchmark_test.dart
```

## 구조

```text
lib/
  seed/         제공된 데이터 소스 (수정 금지)
  data/         feed 수명주기·raw stream 처리 (market_repository)
  domain/       상태·정합성·집계·검색 (quote_state, watchlist_store, aggregates, search_index)
  ui/           화면 (watchlist_page, quote_row, summary_bar, top_movers_section, detail_page, sparkline)
  baseline/     성능 비교용 순진한 구현 (naive_watchlist_page)
integration_test/  기기 profile 프레임 측정
test/              단위·위젯·벤치 테스트
```

경계 원칙: seed raw 타입(`QuoteTick` 등)은 data/domain 경계에서 앱 상태(`QuoteState`)로 변환하고, UI는 seed를 직접 import하지 않는다. timestamp 정합성과 파생값 계산은 상태를 가진 `WatchlistStore`(및 종목별 `QuoteCell`)가 맡는다.

## 문서

- [`DESIGN.md`](DESIGN.md) — 설계 결정, 데이터 흐름, 정합성/성능 전략, 기각한 대안, 테스트 계획
- [`PERF.md`](PERF.md) — 측정 환경·방법, baseline 대비 프레임 시간, jank, 남은 병목
