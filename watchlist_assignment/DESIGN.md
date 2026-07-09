# DESIGN — 실시간 관심종목

## 1. 목표

이 앱은 과제에서 제공한 `MarketFeed`를 실시간 시세 데이터 소스로 사용해 2,000개 관심종목 목록을 보여준다.

핵심 목표는 두 가지다.

- 지연·역순 tick이 와도 가격과 상태가 과거로 되돌아가지 않게 한다.
- 초당 최대 약 15,000건의 갱신이 들어와도 스크롤과 화면 갱신이 부드럽게 유지되게 한다.

`lib/seed/` 아래 seed 파일은 외부 데이터 소스로 취급하고 수정하지 않는다. 캐싱, 검색, 집계, 정렬, throttling은 seed 위에 별도 계층으로 구현한다.

## 2. 결정 요약

| 항목 | 결정 | 근거 |
|---|---|---|
| 상태관리 | 외부 패키지 없이 커스텀 `ChangeNotifier` 기반 | 병목은 상태 보관보다 갱신 전파 범위다. 종목 단위 notifier로 rebuild 범위를 좁힌다. |
| 행 갱신 | 종목별 notifier로 즉시 반영 | 보이는 행만 listen하므로 200ms 신선도 조건을 여유 있게 만족한다. |
| 요약·Top-20 | 100ms 단위 coalescing | 전체 공통 위젯을 60Hz로 rebuild하지 않는다. |
| 시총 합계 | tick당 증분 갱신 O(1) | flush마다 2,000개 전체 재합산을 피한다. |
| Top-20 | 100ms마다 부분 선택, 매 tick 전체 정렬 없음 | 성능 요구를 만족하면서 구현 복잡도를 낮춘다. |
| 검색 | 시작 시 인덱스 1회 구축 + 입력 debounce | 필터 조건은 불변 메타데이터에만 의존하므로 tick 경로와 분리한다. |
| 필터 시 요약 | 표시 종목 수만 필터 기준, 시총·Top-20은 전체 기준 | 검색은 목록 필터, 요약은 전체 관심종목 지표로 역할을 분리한다. |
| 거래정지 | 목록 유지 + 정지 배지 표시 + 집계 포함 | 관심종목에서 사라지는 것보다 정지 상태를 보여주는 편이 사용자에게 자연스럽다. |
| 상세 화면 | 구현 완료 (스파크라인 포함) | 같은 store의 선택 종목 셀 하나만 listen해 목록 갱신 비용과 분리한다. |

## 3. 계층 구조

```text
lib/
  seed/                      수정 금지
  data/
    market_repository.dart   feed 생성, snapshot 로드, ticks 구독, 에러 전달
  domain/
    quote_state.dart         종목별 상태와 파생값, 셀 단위 notifier와 timestamp 가드
    watchlist_store.dart     tick 반영, 집계/검색 조율, notifier 관리
    aggregates.dart          시총 증분 집계, Top-20 계산
    search_index.dart        초성/부분일치/코드 검색 인덱스
  ui/
    watchlist_page.dart      단일 스크롤(급상승 섹션 + 전체 목록), 검색, 오류 배너
    quote_row.dart
    summary_bar.dart
    top_movers_section.dart  급상승 Top-20 세로 순위 섹션(더보기 접힘)
    detail_page.dart
    sparkline.dart
  baseline/
    naive_watchlist_page.dart  성능 비교용 순진한 구현(PERF.md)
integration_test/perf_test.dart  기기 profile 프레임 측정
test_driver/perf_driver.dart     flutter drive 진입점
```

경계 원칙은 다음과 같다.

- `MarketFeed`, `QuoteTick`, `QuoteSnapshotEntry` 같은 seed raw 타입은 data/domain 경계에서 앱 상태로 변환한다.
- UI는 seed를 직접 import하지 않는다.
- repository는 feed 수명주기와 raw stream 처리를 맡는다.
- timestamp 정합성과 파생값 계산은 실제 상태를 가진 `WatchlistStore`가 맡는다.

## 4. 데이터 흐름과 정합성

초기화 순서는 고정한다.

```text
MarketFeed 생성
-> initialSnapshot() 로드
-> WatchlistStore 구축
-> ticks.listen 등록
-> feed.start()
```

`initialSnapshot()`에는 `timestampMs`가 없다. 따라서 feed를 먼저 시작한 뒤 snapshot을 섞어 적용하면 초기 상태와 실시간 tick의 순서가 애매해질 수 있다. 시작 전에 snapshot으로 전체 상태를 만들고, 그 다음 실시간 tick만 timestamp 기준으로 반영한다.

종목별 상태는 다음 정보를 가진다.

```dart
class QuoteState {
  final String code;
  final String name;
  final MarketType market;
  final int listedShares;
  final double previousClose;

  double price;
  int dayVolume;
  int lastTimestampMs;
  QuoteStatus status;

  // 구독 시작 이후 관측된 고가/저가 (상세 화면용, 매 tick 갱신).
  double dayHigh;
  double dayLow;
}
```

`QuoteState`는 종목별 mutable cell로 사용한다. `ValueNotifier<QuoteState>`에 같은 객체를 다시 대입하면 identity가 같아 통지가 발생하지 않으므로 사용하지 않는다. 대신 종목별 커스텀 `ChangeNotifier`를 둔다.

역순 tick 가드는 셀 안에 캡슐화한다. 셀은 자기가 마지막으로 반영한 시각보다
오래된 tick을 스스로 거부하므로, store는 배분만 하고 과거 tick 판단은 셀이 맡는다.

```dart
class QuoteCell extends ChangeNotifier {
  QuoteCell(this.state);

  final QuoteState state;

  bool applyTick(QuoteTick tick) {
    final s = state;
    if (tick.timestampMs < s.lastTimestampMs) {
      return false; // 늦게 도착한 과거 tick — 무시한다.
    }
    final priceChanged = tick.price != s.price;
    final volumeChanged = tick.dayVolume != s.dayVolume;
    final statusChanged = tick.status != s.status;

    s.lastTimestampMs = tick.timestampMs;
    s.price = tick.price;
    s.dayVolume = tick.dayVolume;
    s.status = tick.status;
    if (tick.price > s.dayHigh) s.dayHigh = tick.price;
    if (tick.price < s.dayLow) s.dayLow = tick.price;

    final changed = priceChanged || volumeChanged || statusChanged;
    if (changed) notifyListeners();
    return changed;
  }
}
```

이 구조는 상태 객체를 매 tick 새로 만들지 않으면서도, 실제 표시값이 바뀐 경우에만 명시적으로 행 rebuild를 유발한다.

store의 배치 처리는 집계에 필요한 이전 가격만 셀 밖에서 관측한다.

```dart
for (final tick in batch) {
  final cell = _cells[tick.code];
  if (cell == null) continue;

  final state = cell.state;
  final oldPrice = state.price;
  final changed = cell.applyTick(tick); // 가드는 이 안에서 처리
  if (!changed) continue;

  if (state.price != oldPrice) {
    _aggregates.onPriceChanged(oldPrice, state.price, state.listedShares);
  }
  _summaryDirty = true;
}
```

`<` 가드를 기본으로 둔다. feed는 한 batch 안에서 같은 종목을 중복 방출하지 않지만, 같은 timestamp의 tick을 무조건 버리는 것보다 일반적인 stream 중복 상황에서 더 보수적이다. 구현 중 동일 timestamp 중복을 명확히 배제할 수 있으면 `<=`로 강화할 수 있다.

파생값:

```text
등락폭 = 현재가 - 전일 종가
등락률 = 등락폭 / 전일 종가 * 100
시가총액 = 현재가 * 상장 주식 수
```

`previousClose`는 tick에 포함되지 않으므로 초기 snapshot에서 보존한다.

## 5. 갱신 전파 — 2단 주기

성능의 핵심은 tick 처리와 화면 rebuild를 분리하는 것이다.

| 대상 | 주기 | 구현 | 근거 |
|---|---|---|---|
| 개별 행 가격·거래량·상태 | batch 처리 직후 즉시 | 종목별 `QuoteCell extends ChangeNotifier` | 보이는 행만 listen하므로 비용이 작고 신선도 조건을 만족한다. |
| 시총 합계·Top-20 | 100ms | 별도 summary notifier | 공통 위젯의 60Hz rebuild를 피한다. |
| 오류 배너 | 에러 발생 즉시 표시, 3초 후 자동 해제 | summary notifier + 타이머 | 에러는 드물어 즉시 반영해도 비용이 없고, 최소 표시 시간을 보장한다. |
| 검색 필터 | 입력 debounce 후 | 검색 인덱스에서 재계산 | 종목명/코드는 불변이라 tick과 무관하다. |

Flutter 레벨 수단:

- 목록은 `ListView.builder`를 사용한다.
- 각 행은 자기 종목 `QuoteCell`만 `AnimatedBuilder` 또는 `ListenableBuilder`로 listen한다.
- 행은 `RepaintBoundary`로 감싼다.
- 가격, 거래량, 상태가 실제로 바뀌지 않은 tick은 notify하지 않는다.
- 화면 밖 행은 위젯과 listener가 없으므로 offscreen 갱신이 visible row rebuild를 유발하지 않는다.

batch 하나에 최대 250개 종목이 들어올 수 있으므로 notify 호출 자체는 여러 번 발생할 수 있다. 다만 listener가 붙은 cell은 화면에 보이는 행 중심이고, listener가 없는 cell의 notify 비용은 작다. 또한 값이 실제로 바뀌지 않은 halted tick이나 동일 가격 tick은 notify를 생략한다.

이 구조에서 내부 상태는 tick batch마다 즉시 최신화된다. 반면 화면 전체에 영향을 주는 요약 영역은 100ms 단위로 모아 갱신한다. 100ms는 과제의 200ms stale 제한보다 작으므로 신선도 마진이 있다.

## 6. 시총 합계와 Top-20

### 시총 합계

시총 합계는 전체 관심종목 기준으로 유지한다.

초기 snapshot에서 한 번 계산한다.

```text
totalMarketCap = 모든 종목의 price * listedShares 합
```

tick으로 가격이 바뀌면 전체 재합산을 하지 않고 차액만 반영한다.

```text
delta = (newPrice - oldPrice) * listedShares
totalMarketCap += delta
```

따라서 tick당 O(1)로 집계가 유지된다. 거래정지 tick처럼 가격이 변하지 않는 경우에는 delta가 0이고, 불필요한 summary 갱신도 생략할 수 있다.

단, 전체 시총 합계는 값의 규모가 크다. 종목당 시총은 대략 `현재가 * 상장주식수`이고, 전체 합계는 `double`의 정수 정밀 한계를 넘을 수 있다. 증분 갱신 자체는 유지하되, 장시간 세션에서 부동소수점 오차가 누적되지 않도록 10초마다 전체 2,000개를 한 번 재합산해 보정한다. O(2,000) 비용은 10초 주기에서는 무시할 수 있다.

### Top-20

Top-20은 전체 관심종목의 등락률 기준 내림차순으로 보여준다.

초기 구현은 100ms summary flush 시점에 전체 2,000개에서 20개 후보만 유지하는 부분 선택 방식으로 계산한다. 매 tick 전체 정렬은 하지 않는다.

부분 선택은 다음 방식이다.

```text
top = 빈 후보 목록
for quote in allQuotes:
  if top.length < 20:
    top에 quote 삽입
    top을 등락률 내림차순, 코드 오름차순으로 정렬
  else if quote가 top의 마지막 후보보다 높음:
    마지막 후보 제거
    quote 삽입
    top을 다시 정렬
```

후보 목록 크기가 20으로 고정되므로 2,000개 기준 비용은 O(n * 20)에 가깝다. 100ms마다 수행하기에는 충분히 작다고 판단한다. 측정 결과 병목이면 등락률 keyed ordered structure를 두고 tick으로 변경된 종목만 순위 구조에서 갱신한다.

동률 tie-break는 코드순으로 둔다. 시작 직후에는 전 종목 등락률이 0%일 수 있으므로, tie-break가 없으면 Top-20 순서가 불안정해질 수 있다.

## 7. 검색 정책

검색 인덱스는 초기 snapshot 기준으로 한 번 만든다.

각 종목에 저장하는 검색용 값:

- 종목명
- 종목코드
- 종목명에서 추출한 한글 초성

지원 검색:

- 초성 검색: `ㄱㅇ` -> `가온...`
- 완성형 한글 부분 검색: `전자` -> `가온전자`
- 종목코드 부분 검색: `000590`
- 혼합 입력: 완성형 음절은 이름 부분 문자열로, 자음 단독은 초성으로 문자 단위 매칭한다. 예를 들어 `가ㅇ`은 이름에 `가`가 등장하고 그 뒤 초성 `ㅇ`이 이어지는 후보를 찾는다.

초성 추출은 라이브러리 없이 유니코드 산술로 직접 구현한다. 완성형 한글의 초성 인덱스는 `(codePoint - 0xAC00) ~/ 588`로 계산할 수 있고, seed의 종목명은 완성형 한글 조합으로 한정되어 있다. 수십 줄 안에서 해결되는 로직에 외부 의존성을 추가할 이유가 없다고 판단했다.

검색 결과는 검색어가 바뀔 때만 다시 계산한다. tick이 와도 종목명과 코드는 변하지 않으므로 tick 처리 경로에서 검색을 다시 돌리지 않는다.

필터 정책:

- 표시 종목 수: 검색 필터를 통과한 종목 수
- 목록: 검색 필터를 통과한 종목만 표시
- 시총 합계: 전체 관심종목 기준
- Top-20: 전체 관심종목 기준
- 검색 중에는 급상승 Top-20 섹션을 화면에서 숨긴다. 전체 기준 지표를 검색 결과와
  나란히 두면 사용자가 "검색 집합의 순위"로 오해할 수 있어, 검색 모드에서는 결과
  목록에 집중시킨다.

요약 영역은 "현재 검색 결과의 부분 통계"가 아니라 "전체 관심종목 상태"를 보여주는 영역으로 정의한다. 이 결정으로 검색어 입력이 고빈도 실시간 집계를 흔들지 않고, 시총 합계도 O(1) 증분 집계로 유지할 수 있다.

## 8. 거래정지 모델

거래정지는 tick의 `status`로만 관측된다.

```dart
tick.status == QuoteStatus.halted
```

정책:

- 거래정지 종목도 목록에 계속 표시한다.
- 가격은 마지막으로 반영한 가격을 유지한다.
- 행에는 정지 배지나 muted 스타일을 적용한다.
- 이후 `QuoteStatus.active` tick이 오면 거래 재개로 본다.
- 거래정지 종목도 시총 합계와 Top-20 대상에 포함한다.

초기 snapshot에는 거래정지 정보가 없다. 따라서 모든 종목은 처음에는 active로 시작하고, halted tick을 받은 뒤에만 정지 상태로 바뀐다. 해제도 별도 이벤트가 없으므로 active tick을 받을 때 인지한다.

이 해제 인지 지연은 feed 모델의 특성으로 받아들인다. 별도 상태 이벤트가 없으므로 앱이 임의로 해제를 추정하지 않는다.

## 9. 스트림 에러 모델

feed는 일시적 에러를 stream에 실을 수 있지만 stream을 닫지는 않는다.

구독은 유지한다.

```dart
_subscription = repository.ticks.listen(
  _handleBatch,
  onError: _handleFeedError,
);
```

정책:

- `onError`에서 최근 에러와 시간을 저장한다.
- 구독을 취소하지 않는다.
- 화면 상단에 작은 feed 오류 배너를 표시한다.
- 오류 배너는 최소 3초 동안 유지한다.
- 3초 안에 오류가 다시 발생하면 표시 시간을 연장한다.
- 다음 정상 batch가 오면 내부 복구 상태는 기록하되, 배너는 최소 표시 시간이 지난 뒤 해제한다.

에러를 무시하지는 않지만, 재구독으로 더 큰 상태 흔들림을 만들지 않는다.

## 10. 화면 1 — 관심종목 목록

탭 없이 하나의 세로 스크롤로 구성한다. 실제 국내 증권 앱(관심종목 세로 리스트 +
별도 실시간 랭킹 영역) 패턴을 따른다.

고정 영역(스크롤 위):

- 검색 입력
- feed 오류 배너 (에러 발생 시에만)
- 요약: 표시 종목 수 + 전체 시가총액 합계

스크롤 영역(하나의 `CustomScrollView`):

- 급상승 Top-20 세로 순위 섹션 — 순위 번호(1~3위 강조), 기본 5개만 접어 두고
  '더보기'로 20위까지 펼친다(화면 공간 절약). 100ms 요약 갱신에 맞춰 순위가 바뀐다.
- 전체 관심종목 목록 (코드순 고정, 컴팩트 행)

검색 중에는 급상승 섹션을 숨기고 "검색 결과 N종목" 헤더 + 결과 목록만 보여준다.
요약 지표(시총·Top-20)는 전체 기준이므로 검색 결과 부분집합과 섞지 않는다.

각 행 표시:

- 종목명
- 종목코드
- 현재가
- 전일 대비 등락률
- 당일 누적 거래량
- 거래정지 상태

색상 정책:

- 상승: 빨간색
- 하락: 파란색
- 보합: 회색
- 거래정지: badge와 muted 스타일

## 11. 화면 2 — 상세

화면 2는 동일 feed를 새로 구독하지 않고, 같은 store에서 선택 종목 셀(`QuoteCell`) 하나만 listen한다.

표시 정보:

- 종목명과 코드
- 현재가
- 등락폭과 등락률
- 당일 거래량
- 관측 기준 고가와 저가
- 최근 가격 흐름 스파크라인

시가·고가·저가는 feed snapshot에 명확한 장 시작 값이 없으므로 "앱 구독 시작 이후의 관측값"으로 정의한다. tick 반영 시 전 종목에 대해 고가·저가를 함께 갱신한다. tick당 비교 2회만 추가되므로 비용은 작고, 상세 화면을 언제 열어도 같은 기준의 값을 보여줄 수 있다.

스파크라인은 무한히 커지는 리스트를 쓰지 않는다. 최근 120개 가격만 ring buffer로 유지하고, `CustomPaint`로 그린다.

## 12. 코드에서 주의할 함정

### 12.1 snapshot에는 timestamp가 없다

초기 snapshot은 실시간 tick과 같은 방식으로 timestamp 비교하면 안 된다. snapshot은 feed 시작 전에 전체 초기 상태를 만드는 용도로만 사용한다.

### 12.2 pump는 listener가 있어야 동작한다

`feed.pump(600)`은 `ticks.listen(...)`이 붙어 있어야 batch를 방출한다. 성능 테스트와 회귀 테스트에서는 반드시 listen을 먼저 등록한다.

### 12.3 시작 직후 전 종목 등락률이 같을 수 있다

초기에는 많은 종목의 등락률이 0%일 수 있다. Top-20의 순서가 흔들리지 않도록 등락률이 같으면 코드순으로 정렬한다.

### 12.4 halted 해제는 명시 이벤트가 없다

해제 이벤트가 따로 오지 않는다. 이후 active tick을 받을 때만 해제 상태를 알 수 있다. 앱이 임의 타이머로 해제를 추정하지 않는다.

### 12.5 pump는 burst 처리량과 실시간 프레임 측정을 구분해야 한다

`pump(600)`은 10초 분량의 batch를 한 번에 방출한다. 따라서 순수 처리량 비교에는 유용하지만, 100ms summary timer나 실제 60Hz 프레임 타임을 그대로 재현하지는 않는다. 실시간 프레임 측정은 integration test에서 프레임마다 `pump(1)`을 호출하거나, profile/release 모드에서 `start()`로 별도 확인한다.

## 13. 기각한 대안

### 13.1 전역 `setState`로 전체 화면 rebuild

구현은 단순하지만 feed가 초당 60 batch를 보내고 batch마다 최대 250개 종목이 바뀔 수 있다. 전체 화면 rebuild는 baseline으로는 적합하지만 최종 구조로는 rebuild 범위 축소 요구에 답하지 못한다.

### 13.2 전역 불변 리스트 상태

매 tick마다 2,000개 리스트를 copy하거나 새 view model 리스트를 만들면 GC 압박이 커지고, 변경 전파 범위가 전체 목록으로 넓어진다. 이 과제에서는 종목별 mutable state와 notifier가 더 직접적이다.

### 13.3 행마다 stream을 만들고 `StreamBuilder`로 필터링

2,000개 행이 각자 stream을 구독하거나 code filter를 수행하면 구독 관리가 복잡해진다. 현재 요구에는 종목별 커스텀 `ChangeNotifier`가 더 작고 예측 가능하다.

### 13.4 tick 처리 isolate 분리

tick 처리는 map lookup과 산술 연산 중심이라 가볍다. isolate로 옮기면 메시지 복사 비용과 동기화 비용이 더 커질 가능성이 있다. 먼저 메인 isolate에서 전파 범위를 줄이는 것이 맞다.

### 13.5 거래정지 종목을 목록에서 제외

거래정지 종목도 사용자의 관심종목이며, 제외하면 사용자는 왜 사라졌는지 알기 어렵다. 목록에는 유지하고 상태 표시로 구분한다.

### 13.6 처음부터 큰 상태관리 프레임워크 도입

이번 과제의 핵심은 feed 처리, 정합성, rebuild 범위, 집계 전략이다. 외부 프레임워크 없이도 구조를 명확히 설명하고 구현할 수 있다.

## 14. 테스트 계획

| 테스트 | 검증 내용 |
|---|---|
| 역순 tick | 더 오래된 `timestampMs` tick이 최신 가격을 덮지 못하는지 확인 |
| 거래정지 전이 | halted tick 수신 시 정지 표시, active tick 수신 시 해제 |
| 스트림 에러 생존 | `transientErrorProbability`를 켠 feed에서 에러 후에도 다음 batch가 처리되는지 확인 |
| 검색 | 초성, 완성형 한글, 코드 검색이 기대 종목을 찾는지 확인 |
| 혼합 검색어 | `가ㅇ` 같은 혼합 입력 규칙이 의도대로 동작하는지 확인 |
| 시총 증분 집계 | 가격 변경 시 `(신가 - 구가) * 주식수`만큼 합계가 바뀌는지 확인 |
| 시총 보정 | 주기적 전체 재합산 후 증분 합계와 표시값이 일치하는지 확인 |
| Top-20 안정성 | 등락률 내림차순과 코드순 tie-break가 유지되는지 확인 |

## 15. 성능 측정 계획

성능은 debug 모드가 아니라 profile 또는 release 모드에서 본다.

재현 가능한 처리량 측정은 `start()`가 아니라 `pump()`를 사용한다.

```dart
final feed = MarketFeed();
feed.ticks.listen(handleBatch, onError: handleError);
feed.pump(600);
```

`pump(600)`은 기본 60Hz 기준 약 10초 분량의 tick batch를 결정론적으로 방출한다. 다만 벽시계 기준 10초가 아니라 즉시 방출되는 burst 부하이므로, PERF.md에는 이 측정이 "동일 tick 수열에 대한 처리량 비교"임을 명시한다.

실시간 프레임 확인은 별도로 수행한다.

```dart
for (var i = 0; i < 600; i++) {
  feed.pump(1);
  await tester.pump(const Duration(milliseconds: 16));
}
```

이 방식은 60Hz에 가까운 흐름에서 summary coalescing과 프레임 반응을 확인하기 위한 보조 측정이다.

비교 대상:

- baseline: tick batch마다 전체 화면 또는 전체 목록 상태를 rebuild하는 구현
- 개선본: 종목별 notifier, 시총 증분 집계, 100ms summary coalescing, 검색 인덱스를 적용한 구현

`PERF.md`에는 측정 환경, 측정 방법, before/after 프레임 시간, jank 여부, 남은 병목을 기록한다.

## 16. 구현 순서

1. baseline 구현으로 전체 rebuild 비용 확인
2. data/domain 계층 구현
3. timestamp 가드, 시총 증분 집계, 검색 인덱스 단위 테스트
4. 화면 1 구현
5. `pump(600)` 기준 after 측정
6. 가능하면 화면 2 구현
7. DESIGN.md / PERF.md 최종 정리
