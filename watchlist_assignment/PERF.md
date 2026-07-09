# PERF — 성능 측정과 개선

## 1. 측정 목적

같은 tick 수열에 대해 baseline(순진한 구현)과 개선본의 프레임 비용을 비교한다.
"빠르다"가 아니라 재현 가능한 수치로 개선과 트레이드오프를 함께 보인다.

## 2. 공통 조건

- Flutter 3.44.0 stable / Dart 3.12.0
- 입력: `MarketFeed` 기본 seed(20260703)에서 프레임마다 `pump(1)`을 호출해 총 600배치(60Hz 기준 약 10초 분량) 방출. 두 구현에 **완전히 동일한 tick 수열**을 흘린다(결정론적).
- baseline 화면: `lib/baseline/naive_watchlist_page.dart`
- 벤치 코드: host = `test/perf_benchmark_test.dart`, 기기 = `integration_test/perf_test.dart`

### baseline 정의 (과제 규정 그대로)

- tick 배치마다 `setState()`로 페이지 전체 rebuild
- 매 build마다 요약값을 전체 순회로 재계산: 시가총액 2,000개 전부 합산 + Top-20을 위해 2,000개 전부 정렬
- 행에 `RepaintBoundary` 없음, 종목별 notifier 없음, 역순 tick 가드 없음

## 3. 결과 A — 안드로이드 기기 profile 실측 (주 증거)

- 기기: Samsung SM N986N (Android 13, API 33), **profile 모드**
- 실행: `flutter drive`, 각 602프레임의 실제 렌더 프레임에서 `FrameTiming`(빌드 스레드 + 래스터 스레드) 수집

| 지표 | Baseline 빌드 | Improved 빌드 | Baseline 래스터 | Improved 래스터 |
|---|---|---|---|---|
| avg | 3.12 ms | **1.33 ms** | 2.36 ms | 3.46 ms |
| p50 | 2.97 ms | **0.85 ms** | 2.27 ms | 3.53 ms |
| p95 | 4.93 ms | 4.51 ms | 3.32 ms | 4.36 ms |
| max | 15.55 ms | 26.94 ms | 9.00 ms | 34.20 ms |
| jank(>16.7ms) | 0 | 1 | 0 | 1 |

해석:

- **빌드 스레드**(우리가 rebuild 범위로 직접 제어하는 부분)에서 개선본이 확실히 빠르다. 평균 3.12→1.33ms(2.3배), 중앙값 2.97→0.85ms(3.5배). baseline의 빌드 비용은 매 프레임 2,000개 전체 합산+정렬에서 온다.
- **래스터 스레드**는 개선본이 오히려 약간 높다(2.36→3.46ms). 개선본은 행마다 `RepaintBoundary`를 둬 합성(compositing) 레이어가 늘고, 상단 급상승 섹션·sliver 구조가 더해지기 때문이다. 다만 둘 다 16.7ms 예산에 크게 못 미친다.
- 이 벤치는 **정지 화면**을 잰다. `RepaintBoundary`의 이득(바뀐 한 행의 repaint를 목록 전체로 번지지 않게 격리, 스크롤 중 재합성 절감)은 이 시나리오에서 거의 드러나지 않고 **레이어 비용만 계상**된다. 스크롤·부분 갱신이 잦은 실사용에서는 이 경계가 이득으로 돌아선다.
- 개선본의 max/jank 1프레임(빌드 26.94 / 래스터 34.20ms)은 **최초 프레임**에서 2,000개 셀 + sliver + 급상승 섹션 트리를 처음 구성하는 일회성 비용이다. 이 워밍업 프레임을 제외하면 p95(빌드 4.51 / 래스터 4.36ms)가 정상 상태를 대변한다.

## 4. 결과 B — host 상대 비교 (보조)

`flutter test`의 위젯 바인딩에서 프레임마다 `Stopwatch`로 `tester.pump()`(빌드+레이아웃) 시간 측정. debug 바인딩이라 절대값은 기기와 다르지만, 동일 조건 상대 비교로 빌드 비용 차이를 재현한다. (600프레임, 3회 반복 대표값)

| 지표 | Baseline | Improved | 개선 |
|---|---|---|---|
| 평균 프레임 | 1.30 ms | 0.60 ms | 약 2.2배 |
| 중앙값 p50 | 1.24 ms | 0.05 ms | 약 25배 |
| p95 | 3.9 ms | 3.2 ms | — |
| 최악 프레임 | 25.8 ms | 10.2 ms | 약 2.5배 |
| jank(>16.7ms) | 1 / 600 | 0 / 600 | — |

host에서 개선본 p50이 0.05ms로 낮은 것은, 한 배치가 평균 약 130개 종목을 갱신해도 화면에 보이는 약 10개 행이 그 배치에 포함되는 경우가 드물어 대부분 프레임에서 보이는 행 rebuild가 거의 0이기 때문이다. baseline은 보이든 안 보이든 매 프레임 전체를 setState한다.

## 5. 무엇이 비용을 줄였나

**(1) 증분 집계 (시가총액)** — baseline은 매 프레임 2,000개를 전부 합산. 개선본은 가격이 바뀐 종목의 차액만 더한다(`Aggregates.onPriceChanged`, tick당 O(1)). 600배치마다 1회 전체 재합산으로 부동소수점 오차를 보정한다.

**(2) Top-20을 매 프레임이 아니라 100ms에, 전체 정렬 없이** — baseline은 매 프레임 2,000개 정렬(O(n log n)). 개선본은 100ms에 한 번, 크기 20 후보 목록의 부분 선택으로 계산한다. 빈도(60→10Hz)와 1회 비용(정렬→부분 선택)을 동시에 낮춘다.

**(3) 종목별 notifier로 rebuild 범위 축소** — 각 행이 자기 `QuoteCell`만 listen한다. 배치에 실제로 포함된, 보이는 행만 다시 빌드된다. baseline은 매 프레임 전체 setState.

**(4) 표시값이 바뀐 tick에만 notify + RepaintBoundary** — 가격·거래량·상태가 안 바뀐 tick(정지 종목 등)은 notify를 생략한다. `RepaintBoundary`는 빌드 스레드의 repaint 격리를 위한 것으로, 정지 벤치에서는 래스터 레이어 비용으로 나타나지만(§3) 스크롤·부분 갱신에서 이득이 된다.

정리: 개선본은 빌드 스레드 비용을 증분화·저빈도화·국소화로 줄였다. 래스터는 `RepaintBoundary` 레이어만큼 정지 상태에서 소폭 늘지만 예산 대비 여유가 크고, 실사용(스크롤)에서 상쇄된다.

## 6. 남은 병목과 다음 단계

- **개선본 래스터 소폭 증가**: 정지 화면에서 `RepaintBoundary` 레이어 비용이 이득을 상회한다. 스크롤 시나리오를 벤치에 추가해 경계의 순이득을 정량화하거나, 화면당 경계 수를 조정(예: 급상승 섹션은 섹션 단위 경계)해 최적점을 찾을 수 있다. 현재 절대값이 예산의 20% 수준이라 우선순위는 낮다.
- **초기 프레임 스파이크**: 최초 트리 구성 1프레임이 jank로 잡힌다. 첫 화면을 지연 구성하거나 warmup을 분리해 정상 상태 수치를 보고한다.
- **빌드 스파이크(p95)**: 100ms 요약 flush가 겹치는 프레임이 원인. 등락률로 정렬된 자료구조를 두고 바뀐 종목만 순위 구조에서 갱신하면 낮출 수 있다(설계서 §6).

## 7. 재현

```bash
# 기기 profile 실측 (안드로이드 예시)
flutter drive \
  --driver=test_driver/perf_driver.dart \
  --target=integration_test/perf_test.dart \
  -d <deviceId> --profile
# 콘솔에 [BASELINE]/[IMPROVED] build·raster 통계 출력

# host 상대 비교
flutter test test/perf_benchmark_test.dart

# 정적 검사 / 전체 테스트
flutter analyze          # 0 issues
flutter test             # 전체 통과 (벤치 포함)

# 실시간 육안 + DevTools Performance
flutter run --profile -d <deviceId>   # lib/main.dart (개선본)
```
