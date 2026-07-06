# Edencrew Flutter 과제 — 실시간 관심종목

이 문서는 과제 설명, seed, 평가 기준, 제출물, 부록 코드를 한 곳에 모은 단일 기준 문서입니다.
실시간으로 갱신되는 대규모 관심종목 화면을 직접 설계하고 구현하는 과제이며,
경력 5~10년차(미들~시니어)를 대상으로 두 가지 역량을 집중적으로 봅니다.

1. **아키텍처 설계** — 주어진 데이터 소스(seed) 위에 계층/추상화/상태/에러 모델을 스스로 설계
2. **실시간 성능** — 2,000종목이 고빈도로 갱신되는 목록을 60fps로 매끄럽게 유지

- 이 과제는 정답 코드를 채우는 과제가 아닙니다. 통과해야 할 테스트도 주지 않습니다.
  우리는 여러분이 **어떤 구조를 택했고 왜 그렇게 했는지**를 봅니다.
  산출물의 핵심은 **동작하는 앱 + 두 개의 설계 문서(DESIGN.md, PERF.md)**입니다.
- feed는 깨끗하지 않습니다. 지연·역순 tick, 거래정지, (평가자가 켤 수 있는) 스트림 에러가
  섞여 들어옵니다. "빠르게만" 짜면 정합성이 깨집니다. **성능과 정합성을 동시에 지키는 설계**인지를 봅니다.

## 범위와 권장 시간

완성도보다 **판단의 근거**를 봅니다. 모든 요구를 다 채우지 못해도, 어디에 시간을 쓰고 무엇을 의도적으로 생략했는지가 드러나면 됩니다.

- 권장 소요 시간: **8~12시간** 수준을 상정합니다. 이 이상을 갈아 넣는 것을 기대하지 않습니다.
- 우선순위: **화면 1(목록·요약·Top-20·초성 검색) + DESIGN.md + PERF.md** 가 핵심입니다.
  화면 2(상세·스파크라인)는 시간이 허락하는 선에서 구현하고, 부족하면 DESIGN.md에 "어떻게 했을 것인지"를 적는 것으로 갈음할 수 있습니다.
- 생략·미완이 있다면 그 사실과 이유를 문서에 명시하세요. 침묵보다 낫습니다.

## AI 도구

AI 도구 사용은 허용합니다. 다만 제출 후 기술 면접에서 구현과 설계 결정에 대해 구체적으로 질문합니다. 본인이 내린 판단이라고 설명할 수 있어야 합니다.

## 0. 시작 방법

1. 새 Flutter 앱을 만듭니다: `flutter create watchlist_assignment`
2. 이 문서 부록 A·B의 두 파일을 그대로 아래 경로에 저장합니다. **이 파일들은 수정하지 마세요.**
   - `lib/seed/market_models.dart`
   - `lib/seed/market_feed.dart`
3. 여러분의 화면·상태·계층을 그 위에 구현합니다.
4. 필요하면 `pubspec.yaml`에 라이브러리를 추가하되, 그 선택의 근거를 DESIGN.md에 남기세요.

> `lib/seed/`는 "데이터 소스"입니다. 여기에 캐싱·throttle·변환·정렬을 넣지 마세요. 그런 처리는 여러분이 그 위에 쌓을 계층의 책임입니다.

## 1. 데이터 소스 (MarketFeed)

`MarketFeed`는 실제 서비스의 폴링/WebSocket 피드를 로컬에서 재현한 것입니다.

- 종목 2,000개 (KOSPI/KOSDAQ 혼합), 순서 고정
- `start()` 이후 고빈도로 시세 배치를 `ticks` 스트림에 흘려보냄
- 기본값: 초당 60배치 × 배치당 최대 250건 ≈ **초당 최대 15,000 갱신**
- `initialSnapshot()` 으로 구독 시작 시점의 전체 시세 스냅샷을 받음
- broadcast stream 이므로 여러 구독자가 붙을 수 있음

### feed의 비정상 특성 (반드시 다뤄야 합니다)

- **지연·역순 tick** — 일부 tick은 지연되어, 더 최신 tick보다 나중에(=더 작은 `timestampMs`를 달고) 도착합니다.
  도착 순서만 믿으면 가격이 과거로 되돌아갑니다. 정합성은 `timestampMs`로 보장하세요.
- **거래정지(halt)** — 종목이 수시로 정지/해제됩니다. 정지 tick은 `QuoteStatus.halted`이고 가격이 고정됩니다.
  정지 구간을 등락률·순위·시총 등에 어떻게 반영/제외할지는 여러분의 판단이며, 그 판단을 DESIGN.md에 남기세요.
  - 주의 1: 정지/해제 상태는 해당 종목이 배치에 뽑혀 tick으로 올 때만 관측됩니다. 별도의 상태 이벤트가 따로 오지 않습니다.
  - 주의 2: 해제에는 명시적인 "재개" 신호가 없습니다. 이후 그 종목의 tick이 다시 `QuoteStatus.active` 로 도착하는 것으로만 해제를 알 수 있습니다.
  - 주의 3: `initialSnapshot()` 에는 정지 상태 정보가 없습니다. 구독 시작 시점에 이미 정지 중인 종목은 첫 tick이 올 때까지 알 수 없습니다.
- **일시적 스트림 에러** — 기본은 꺼져 있으나, 평가자는 `transientErrorProbability`를 올려 스트림에 간헐적 에러를 실을 수 있습니다.
  구독은 에러로 끊기지 않고 살아남아 다음 배치로 복구되어야 합니다. 에러를 어떤 상태/UI로 표현할지(무시가 정답이 아닐 수 있음)를 설계하세요.
  - 회귀 테스트를 작성할 때는 `MarketFeed(transientErrorProbability: 0.1)` 정도로 켜서 "에러가 와도 구독이 유지되고 다음 배치로 복구되는지"를 검증하는 것을 권장합니다. (평가 시 평가자가 사용하는 정확한 값은 이와 다를 수 있습니다.)

feed는 **전일 종가(previousClose)** 를 스냅샷으로만 주고, 이후에는 tick으로 현재가/거래량만 흘려보냅니다.
등락률 등 파생 값은 여러분이 계산합니다. 네트워크·백엔드는 없습니다 — 이 과제는 데이터 연동이 아니라 **설계와 성능**입니다.

## 2. 만들 화면

### 화면 1. 관심종목 목록 (Watchlist)

2,000개 종목을 하나의 스크롤 목록으로 보여줍니다. 각 행:

- 종목명, 종목코드
- 현재가 (실시간 갱신)
- 전일 대비 등락률 % (상승 빨강 / 하락 파랑 / 보합 회색)
- 당일 누적 거래량
- 거래정지 종목은 정지 상태임을 시각적으로 구분 (가격은 직전가로 고정)

목록 상단 요약 영역:

- 표시 중인 종목 수 (검색 필터가 걸리면 필터를 통과한 종목 수, 아니면 전체 2,000. 정지 종목을 "표시 중"에서 어떻게 셀지 등 집계 기준은 스스로 정하고 그 판단을 남기세요.)
- 시가총액 합계 (현재가 × 상장주식수의 총합, 실시간 갱신). 필터가 걸렸을 때 이 합계를 필터 집합 기준으로 낼지 전체 기준으로 낼지는 아래 검색 항목의 판단을 따릅니다.
- 실시간 등락률 상위 20 종목 (등락률 내림차순, 실시간 갱신). 형태는 자유이나 feed 갱신에 따라 순위가 라이브로 바뀌어야 합니다.

목록 검색 — **초성 검색 (필수)**:

- 목록 상단에 검색 입력을 두고, 입력에 맞는 종목만 실시간으로 필터링합니다.
- 한글 초성 검색을 반드시 지원합니다. 예: `ㄱㅇ` → "가온…", `ㄴㄹㅎㅎ` → "나래화학", `ㄱㅇㅈㅈ` → "가온전자". (종목명은 seed의 `_nameFor()`가 생성하는 한글 조합입니다.) 완성형 한글 부분일치(예: "전자")와 종목코드 부분일치(예: "000590")도 함께 지원하세요.
- 초성 추출·매칭을 직접 구현할지 라이브러리를 쓸지는 자유이며, 그 선택의 근거를 DESIGN.md에 남기세요.
- 2,000종목을 고빈도 tick이 흐르는 중에 필터링합니다. 매 tick / 매 keystroke마다 전체를 재계산·재정렬하지 않도록 하세요 (검색 인덱스·debounce·메모이제이션 등은 여러분의 판단). 필터가 걸린 상태에서도 위의 신선도·프레임 제약이 그대로 유지되어야 합니다.
- 시총 합계와 Top-20이 필터된 집합 기준인지 전체 기준인지를 스스로 정의하고 DESIGN.md에 밝히세요. (표시 중인 종목 수는 정의상 화면에 보이는 = 필터 통과 수입니다.) 필터 아웃되어 보이지 않는 종목의 갱신 비용을 어떻게 처리할지도 설계 판단입니다.

요구 동작:

- feed의 실시간 tick이 목록·요약·순위에 반영되어야 합니다.
- 2,000행을 스크롤하는 동안 프레임 드랍이 눈에 띄지 않아야 합니다 (목표 60fps).
- 화면에 보이지 않는 행의 갱신이 보이는 행의 렌더링을 방해하지 않아야 합니다.
- **신선도 제약**: 화면에 보이는 행의 가격은 해당 종목의 최신 tick 도착 후 **200ms 이상 stale 상태로 남지 않아야** 합니다 — 빠르게 스크롤하는 중에도. (이 제약은 60fps 목표와 부분적으로 상충합니다. coalescing/throttle을 세게 걸수록 프레임은 안정되지만 신선도가 나빠집니다. 어디에 선을 긋고 왜 그렇게 했는지를 DESIGN.md에 근거와 함께 남기세요.)
  - 이 200ms는 벽시계 기준의 실시간(`start()`) 동작 요구입니다. 60Hz에서 200ms는 약 12프레임에 해당하므로, 그 안에서 얼마나 coalescing할지가 여러분의 설계 여지입니다.
  - 검증은 `start()` 로 실제 시간 흐름에서 육안·DevTools로 확인하고, before/after 프레임 타임 비교는 `pump()`(3장) 로 재현하세요 — 두 목적을 분리해 다루면 됩니다.
- 지연·역순 tick이 와도 표시 가격이 과거로 되돌아가지 않아야 합니다.

### 화면 2. 종목 상세 (Detail)

목록에서 한 종목을 탭하면 진입합니다. 표시 정보:

- 종목명, 코드, 현재가, 등락폭/등락률
- 시가·고가·저가 성격의 파생 값 (feed의 tick 흐름에서 여러분이 계산/누적)
- 당일 거래량
- 최근 시세 흐름을 보여주는 간단한 스파크라인 또는 미니 차트 (실시간 갱신). 최근 N개 체결가를 유지해 그리되, 고빈도 tick 아래에서 히스토리 버퍼가 무한정 커지거나 매 tick마다 전체를 다시 그리지 않도록 하세요.

요구 동작:

- 상세 화면도 동일 feed에서 실시간 갱신됩니다.
- 상세 화면이 떠 있는 동안 목록 화면의 갱신 비용이 불필요하게 유지되지 않아야 합니다 (구독 수명 관리는 여러분의 설계 판단).
- 거래정지 구간은 상세 화면에서도 구분되어야 합니다.

## 3. 성능 — 측정과 재현

- 성능 측정은 반드시 **profile 또는 release 모드**로 하세요. debug는 실제보다 훨씬 느립니다.
- DevTools의 Performance 뷰로 프레임 빌드/래스터 시간을 확인하는 것을 권장합니다.
- **재현 가능한 벤치마크**: baseline과 개선본을 같은 조건에서 비교해야 합니다. `MarketFeed`는 벽시계 대신 결정론적으로 배치를 밀어 넣는 `pump()`를 제공합니다.

```dart
// 기본 seed(20260703)로 항상 같은 tick 수열이 재현됩니다.
final feed = MarketFeed(); // start() 대신 pump() 사용
// ... ticks에 리스너(=여러분의 소비 계층)를 붙인 뒤:
feed.pump(600); // 10초 분량(60Hz×10s)을 결정론적으로 방출
```

> 주의: `pump()` 는 리스너가 붙어 있어야만 배치를 방출합니다(리스너가 없으면 조용히 아무것도 안 합니다). 반드시 `ticks.listen(...)` 을 먼저 건 뒤 `pump()` 를 호출하세요. "pump했는데 tick이 안 온다"의 대부분은 이 순서 문제입니다.

`integration_test`에서 이 시나리오로 프레임 타임을 재면 후보 간 비교가 가능합니다.

> **baseline(before)이란?** 먼저 "가장 순진한" 구현 — tick 배치마다 `setState()`로 화면 전체를 rebuild하고, 요약값을 매 build마다 전체 순회로 재계산하고, 행에 `RepaintBoundary`도 없는 형태 — 을 기준선으로 두고, 거기서 무엇을 얼마나 줄였는지를 수치로 보이면 됩니다.

## 4. 제출물

- 구현 코드 (`lib/seed/`는 미수정 상태 유지)
- **DESIGN.md** — 아키텍처 결정과 근거. 최소한 다음을 담으세요.
  - 계층/경계, 추상화, 상태관리 방식과 그 이유
  - 에러/엣지 모델: 지연·역순 tick 정합성 / 거래정지 처리 / 스트림 에러 복구
  - 검토했지만 기각한 대안 (최소 3가지: 무엇을 왜 택했고 무엇을 왜 버렸는지)
  - 성능↔신선도 트레이드오프에서 어디에 선을 그었는지
- **PERF.md** — 병목 분석 + 개선 + 재현 가능한 before/after 수치
  - 못 재는 환경이면 "왜 못 쟀는지"와 "어떻게 잴 것인지"라도 구체적으로. 빈 표는 감점입니다.
- `flutter analyze` / `flutter test` 결과
- (선택) 프로파일링 스크린샷

## 5. 평가 항목

- **아키텍처 설계 (45%)**: 계층/경계/추상화/상태/에러 모델의 타당성과 일관성, 변경에 대한 견고함. 기각한 대안을 근거와 함께 밝혔는가
- **실시간 성능 (45%)**: baseline 대비 개선의 근거·측정·효과. rebuild 범위 축소, 스트림 coalescing/throttle, 증분 집계, Top-20 라이브 순위를 매 tick 전체 재정렬 없이 유지하는가, 초성 검색 필터를 매 tick·keystroke 전체 재계산 없이 처리하는가. 성능↔신선도 트레이드오프
- **코드 완성도·테스트 (10%)**: 가독성, 네이밍, 적절한 테스트 선택 (특히 지연·역순/정지 같은 엣지의 회귀 테스트)

DESIGN.md와 PERF.md의 품질이 코드만큼 중요합니다.

## 6. 진행 순서 추천

1. 부록 코드를 `lib/seed/`에 넣고, 순진한 구현으로 먼저 띄워 jank를 눈과 DevTools로 확인합니다.
2. DESIGN.md에 목표 구조를 먼저 스케치합니다 (코드보다 설계 먼저). 지연·역순 tick, 거래정지, 스트림 에러를 어디서 흡수할지 경계를 먼저 정하세요.
3. 목록 화면(요약·Top-20·초성 검색 포함)을 구현하고, `pump()` 기반 벤치로 측정하며 개선합니다.
4. 상세 화면(스파크라인)과 구독 수명주기를 마무리합니다.
5. DESIGN.md(기각한 대안 포함) / PERF.md(재현 가능한 수치)를 채웁니다.

## 라이선스

이 과제는 평가 목적으로만 제공됩니다. Edencrew의 명시적 허가 없이 복사·수정·배포·상업적 이용을 허용하지 않습니다.

---

## 부록 A — `lib/seed/market_models.dart` (수정 금지)

```dart
/// ============================================================================
/// DOMAIN SEED — 수정하지 마세요 (Do NOT modify)
/// ============================================================================
///
/// 이 파일은 "데이터 소스가 주는 원시(raw) 형태"를 정의합니다.
/// 과제의 시작점일 뿐, 앱 전역에서 이 타입을 그대로 쓰라는 뜻은 아닙니다.
///
/// - 프레젠테이션 계층까지 이 raw 타입을 그대로 흘려보낼지,
///   별도의 도메인/뷰 모델로 변환할지는 여러분의 설계 판단입니다.
/// - 변환한다면 그 경계(boundary)를 어디에 둘지, 왜 그렇게 했는지를
///   DESIGN.md에 적어 주세요.
/// ============================================================================

library;

enum MarketType { kospi, kosdaq }

/// 종목의 실시간 거래 상태.
///
/// feed는 정상 거래 중에는 [active] tick을, 거래정지 구간에는 [halted] tick을
/// 내보냅니다. 정지 상태를 어떻게 표시/누적할지는 여러분의 설계 판단입니다.
enum QuoteStatus {
  /// 정상 거래 중.
  active,

  /// 거래정지(halt). 이 구간의 [QuoteTick.price] 는 직전 체결가로 고정되며,
  /// 등락률·시총 등 파생값에 정지 구간을 어떻게 반영할지는 여러분이 정합니다.
  halted,
}

/// 종목의 정적 메타데이터. 앱 수명 동안 바뀌지 않습니다.
class SymbolInfo {
  const SymbolInfo({
    required this.code,
    required this.name,
    required this.market,
    required this.listedShares,
  });

  /// 6자리 종목코드. 예: "005930"
  final String code;

  /// 종목명. 예: "삼성전자"
  final String name;

  final MarketType market;

  /// 상장 주식 수 (시가총액 계산에 사용).
  final int listedShares;
}

/// 스트림으로 밀려오는 한 건의 시세 갱신.
///
/// feed는 이 값을 **배치(`List<QuoteTick>`)** 로, 초당 수천 건 규모로 내보냅니다.
/// 한 배치 안에 같은 종목이 여러 번 등장하지 않습니다.
///
/// 주의: 실제 피드와 마찬가지로 **도착 순서가 시간 순서와 일치하지 않을 수
/// 있습니다.** 일부 tick은 지연되어, 더 최신 tick보다 나중에(=더 작은
/// [timestampMs] 를 달고) 도착합니다. 도착 순서만 믿고 마지막 값을 그대로
/// 반영하면 가격이 과거로 되돌아갈 수 있습니다. 정합성은 [timestampMs] 로
/// 여러분이 보장해야 합니다.
class QuoteTick {
  const QuoteTick({
    required this.code,
    required this.price,
    required this.dayVolume,
    required this.timestampMs,
    this.status = QuoteStatus.active,
  });

  final String code;

  /// 현재가 (원). [status] 가 [QuoteStatus.halted] 이면 직전 체결가로 고정됩니다.
  final double price;

  /// 당일 누적 거래량.
  final int dayVolume;

  /// 이 tick이 관측된 시각 (feed 내부 시계 기준, epoch milliseconds).
  /// **도착 순서와 무관하게** 이 값이 이벤트의 실제 시간 순서입니다.
  final int timestampMs;

  /// 이 tick 시점의 거래 상태.
  final QuoteStatus status;
}

/// feed 구독 직후 받는 전체 스냅샷의 한 종목 항목.
class QuoteSnapshotEntry {
  const QuoteSnapshotEntry({
    required this.info,
    required this.previousClose,
    required this.price,
    required this.dayVolume,
  });

  final SymbolInfo info;

  /// 전일 종가. 등락률/등락폭 계산의 기준값이며, 세션 동안 고정입니다.
  final double previousClose;

  final double price;
  final int dayVolume;
}
```

## 부록 B — `lib/seed/market_feed.dart` (수정 금지)

```dart
/// ============================================================================
/// DOMAIN SEED — 수정하지 마세요 (Do NOT modify)
/// ============================================================================
///
/// [MarketFeed] 는 여러분이 상대해야 하는 "실시간 시세 데이터 소스"입니다.
/// 실제 서비스의 폴링/WebSocket 피드를 로컬에서 재현한 것으로, 다음 특성을 가집니다.
///
/// - 종목 2,000개 (KOSPI/KOSDAQ 혼합)
/// - [start] 이후 고빈도로 시세 배치를 [ticks] 스트림에 흘려보냄
///   기본값: 초당 60배치 × 배치당 최대 250건 ≈ 초당 최대 15,000 갱신
/// - broadcast stream 이므로 여러 구독자가 붙을 수 있음
/// - **지연·역순 tick**: 일부 tick은 지연되어 더 최신 tick보다 나중에
///   (=더 작은 timestampMs를 달고) 도착합니다. 도착 순서 = 시간 순서가 아닙니다.
/// - **거래정지(halt)**: 종목이 수시로 정지/해제됩니다. 정지 구간의 tick은
///   [QuoteStatus.halted] 이고 가격이 고정됩니다.
/// - **일시적 스트림 에러**: 실제 소켓처럼 [ticks] 스트림이 간헐적으로 에러를
///   낼 수 있습니다(기본 확률 0 — 평가자가 [transientErrorProbability] 로 켭니다).
///   구독자는 에러에도 살아남아 갱신을 이어갈 수 있어야 합니다.
///
/// 결정론성: 모든 무작위성은 생성자 [seed] 하나에서 나옵니다. 같은 seed + 같은
/// 배치 수열이면 tick 시퀀스가 **바이트 단위로 재현**됩니다. 벤치마크는 [start]
/// 대신 [pump] 로 배치를 결정론적으로 밀어 넣어 before/after를 공정하게 비교하세요.
///
/// 이 클래스의 동작/시그니처는 고정입니다. 여기에 캐싱·throttle·변환·정렬을 넣지
/// 마세요. 그런 처리는 여러분이 이 위에 쌓을 계층의 책임입니다.
///
/// 이 feed를 앱에서 어떻게 소비할지 — 어떤 추상화로 감쌀지, 어디서 throttle/batch
/// 할지, 어떤 단위로 rebuild를 유발할지 — 가 이번 과제의 핵심입니다.
/// ============================================================================
library;

import 'dart:async';
import 'dart:math';

import 'market_models.dart';

class MarketFeed {
  MarketFeed({
    this.symbolCount = 2000,
    this.batchesPerSecond = 60,
    this.updatesPerBatch = 250,
    this.lateTickProbability = 0.008,
    this.haltProbability = 0.002,
    this.transientErrorProbability = 0.0,
    int seed = 20260703,
  }) : _random = Random(seed) {
    _buildUniverse();
  }

  /// 생성할 종목 수.
  final int symbolCount;

  /// 초당 스트림 배치 수 (기본 60Hz).
  final int batchesPerSecond;

  /// 한 배치에서 갱신되는 종목 수의 상한.
  final int updatesPerBatch;

  /// tick 하나가 지연되어 나중 배치에서 (더 작은 timestampMs로) 방출될 확률.
  /// 도착 순서 ≠ 시간 순서 상황을 재현합니다.
  final double lateTickProbability;

  /// 매 배치에서 새 거래정지가 발생할 확률. 정지는 1~6초 뒤 자동 해제됩니다.
  final double haltProbability;

  /// 매 배치 후 [ticks] 스트림에 일시적 에러를 실을 확률.
  /// 기본 0(꺼짐). 평가자는 이 값을 올려 에러 복구 설계를 검증할 수 있습니다.
  final double transientErrorProbability;

  final Random _random;

  final List<SymbolInfo> _symbols = [];
  final Map<String, double> _previousClose = {};
  final Map<String, double> _price = {};
  final Map<String, int> _dayVolume = {};

  /// 현재 거래정지 중인 종목 → 해제 예정 배치 index.
  final Map<String, int> _haltedUntilBatch = {};

  /// 방출이 지연된 tick들. (원본 timestamp를 유지한 채) 예정 배치에서 풀린다.
  final List<_DelayedTick> _delayed = [];

  int _clockMs = 0;
  int _batchIndex = 0;
  Timer? _timer;

  final StreamController<List<QuoteTick>> _controller =
      StreamController<List<QuoteTick>>.broadcast();

  /// 2,000개 종목의 정적 메타데이터. 순서는 고정입니다.
  List<SymbolInfo> get symbols => List.unmodifiable(_symbols);

  /// 구독 시작 시점의 전체 시세 스냅샷.
  List<QuoteSnapshotEntry> initialSnapshot() {
    return _symbols
        .map(
          (info) => QuoteSnapshotEntry(
            info: info,
            previousClose: _previousClose[info.code]!,
            price: _price[info.code]!,
            dayVolume: _dayVolume[info.code]!,
          ),
        )
        .toList(growable: false);
  }

  /// 고빈도 시세 배치 스트림. [start] 를 호출해야 흐르기 시작합니다.
  Stream<List<QuoteTick>> get ticks => _controller.stream;

  void start() {
    if (_timer != null) return;
    final period = Duration(microseconds: 1000000 ~/ batchesPerSecond);
    _timer = Timer.periodic(period, (_) => _emitBatch());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 결정론적 벤치마크용. 타이머 없이 [count]개의 배치를 즉시 방출합니다.
  ///
  /// [start] 와 달리 벽시계에 의존하지 않으므로, 같은 seed로는 항상 같은 tick
  /// 수열이 재현됩니다. before/after 성능 비교는 이 API로 동일 시나리오를 돌려
  /// 측정하세요. (호출 전에 [ticks] 에 리스너가 붙어 있어야 방출됩니다.)
  void pump([int count = 1]) {
    for (var i = 0; i < count; i++) {
      _emitBatch();
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }

  void _emitBatch() {
    if (_controller.isClosed || !_controller.hasListener) return;
    _batchIndex++;
    _clockMs += 1000 ~/ batchesPerSecond;

    _updateHalts();

    final batch = <QuoteTick>[];
    final touched = <String>{};

    // 지연되었던 tick을 (원래의 오래된 timestamp 그대로) 먼저 풀어 넣는다.
    _releaseDelayed(batch, touched);

    // 한 배치에 한 종목은 최대 1건이므로, 요청 건수는 종목 수를 넘을 수 없다.
    // (지연 tick도 touched를 소비하므로) touched가 전 종목을 덮으면 종료한다.
    final count = 1 + _random.nextInt(updatesPerBatch);

    while (batch.length < count && touched.length < _symbols.length) {
      final info = _symbols[_random.nextInt(_symbols.length)];
      if (!touched.add(info.code)) continue;

      // 거래정지 종목: 가격 고정, 상태만 halted로 알린다.
      if (_haltedUntilBatch.containsKey(info.code)) {
        batch.add(
          QuoteTick(
            code: info.code,
            price: _price[info.code]!,
            dayVolume: _dayVolume[info.code]!,
            timestampMs: _clockMs,
            status: QuoteStatus.halted,
          ),
        );
        continue;
      }

      final prev = _price[info.code]!;
      // 전일 종가 대비 ±0.05% 내외의 랜덤워크.
      final drift = (_random.nextDouble() - 0.5) * 0.001;
      final next = (prev * (1 + drift)).clamp(prev * 0.7, prev * 1.3);
      final rounded = _roundToTick(next);
      _price[info.code] = rounded;
      _dayVolume[info.code] = _dayVolume[info.code]! + _random.nextInt(500);

      final tick = QuoteTick(
        code: info.code,
        price: rounded,
        dayVolume: _dayVolume[info.code]!,
        timestampMs: _clockMs,
      );

      // 낮은 확률로 이 tick을 지연시킨다. 그 사이 같은 종목의 후속 tick이 먼저
      // 나가므로, 이 tick은 나중에 "과거 시각"을 달고 도착한다(=역순 도착).
      if (_random.nextDouble() < lateTickProbability) {
        _delayed.add(
          _DelayedTick(tick, _batchIndex + 1 + _random.nextInt(3)),
        );
      } else {
        batch.add(tick);
      }
    }

    _controller.add(batch);

    if (transientErrorProbability > 0 &&
        _random.nextDouble() < transientErrorProbability) {
      _controller.addError(
        const MarketFeedException('일시적 피드 오류 (재구독 없이 복구 가능)'),
      );
    }
  }

  /// 정지 해제 시각이 지난 종목을 풀고, 낮은 확률로 새 정지를 건다.
  void _updateHalts() {
    _haltedUntilBatch.removeWhere((_, until) => _batchIndex >= until);
    if (_random.nextDouble() < haltProbability) {
      final info = _symbols[_random.nextInt(_symbols.length)];
      // 1~6초(60~360배치) 동안 정지.
      _haltedUntilBatch[info.code] =
          _batchIndex + 60 + _random.nextInt(300);
    }
  }

  /// 예정 배치에 도달한 지연 tick을 batch에 방출한다.
  /// 같은 배치에 같은 종목이 중복되지 않도록, 이미 나간 종목은 다음 배치로 미룬다.
  void _releaseDelayed(List<QuoteTick> batch, Set<String> touched) {
    if (_delayed.isEmpty) return;
    _delayed.removeWhere((d) {
      if (_batchIndex < d.releaseAtBatch) return false;
      if (!touched.add(d.tick.code)) return false;
      batch.add(d.tick);
      return true;
    });
  }

  void _buildUniverse() {
    for (var i = 0; i < symbolCount; i++) {
      final code = (i + 1).toString().padLeft(6, '0');
      final market = i.isEven ? MarketType.kospi : MarketType.kosdaq;
      final base = 1000 + _random.nextInt(490000).toDouble();
      final basePrice = _roundToTick(base);

      _symbols.add(
        SymbolInfo(
          code: code,
          name: _nameFor(i),
          market: market,
          listedShares: 1000000 + _random.nextInt(500000000),
        ),
      );
      _previousClose[code] = basePrice;
      _price[code] = basePrice;
      _dayVolume[code] = _random.nextInt(2000000);
    }
  }

  String _nameFor(int i) {
    const prefixes = [
      '가온', '나래', '다온', '라온', '마루', '바로', '사라', '아라',
      '자람', '차미', '카나', '타온', '파랑', '하늘', '누리', '온새',
    ];
    const suffixes = [
      '전자', '화학', '바이오', '중공업', '제약', '통신', '엔터', '소재',
      '에너지', '금융', '물산', '테크', '반도체', '건설', '식품', '항공',
    ];
    final p = prefixes[i % prefixes.length];
    final s = suffixes[(i ~/ prefixes.length) % suffixes.length];
    return '$p$s';
  }

  /// 국내 주식 호가단위를 대략적으로 흉내낸 반올림.
  double _roundToTick(double price) {
    final int tick;
    if (price < 2000) {
      tick = 1;
    } else if (price < 5000) {
      tick = 5;
    } else if (price < 20000) {
      tick = 10;
    } else if (price < 50000) {
      tick = 50;
    } else if (price < 200000) {
      tick = 100;
    } else if (price < 500000) {
      tick = 500;
    } else {
      tick = 1000;
    }
    return (price / tick).round() * tick.toDouble();
  }
}

/// 방출이 지연된 tick과 그 해제 예정 배치 index.
class _DelayedTick {
  const _DelayedTick(this.tick, this.releaseAtBatch);

  final QuoteTick tick;
  final int releaseAtBatch;
}

/// [MarketFeed.ticks] 스트림이 낼 수 있는 일시적 오류.
/// 스트림은 닫히지 않으며, 구독을 유지한 채 다음 배치로 복구됩니다.
class MarketFeedException implements Exception {
  const MarketFeedException(this.message);

  final String message;

  @override
  String toString() => 'MarketFeedException: $message';
}
```
