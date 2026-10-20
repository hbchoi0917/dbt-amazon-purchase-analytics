# dbt Retention Analytics Pipeline

**Analytics Engineering Portfolio Project** · **애널리틱스 엔지니어링 포트폴리오 프로젝트**

> 🌐 **Language / 언어** — Click a heading below to expand or collapse it. / 아래 제목을 클릭하면 펼치거나 접을 수 있습니다.

<details open>
<summary><h2>🇺🇸 English</h2></summary>

Production-style dbt pipeline for cohort-based customer retention analysis and **monthly revenue forecasting with an out-of-sample backtest**.

**Stack:** dbt Core · DuckDB · dbt_utils

---

### Dataset

**E-commerce transactions** (synthetic):
- 1,000 transactions · 1,000 unique customers
- Date range: 2023-01 – 2024-01
- Fields: transaction_id, customer_id, date, product_category, quantity, price_per_unit, total_amount, gender, age

> **Note:** This seed represents a proof-of-concept dataset (1 transaction/customer).
> In production, swap `raw_transactions` for a source table with repeat-purchase history to observe meaningful retention curves.

---

### Architecture

```
seeds/
└── raw_transactions.csv          # Source: denormalized e-commerce transactions

models/
├── staging/                      # Rename, type-cast, deduplicate — no business logic
│   ├── stg_customers.sql         # 1 row per customer (QUALIFY dedup)
│   ├── stg_transactions.sql      # 1 row per transaction
│   └── schema.yml                # Column docs + unique/not_null/relationships tests
│
├── intermediate/                 # Business logic
│   ├── int_customer_cohorts.sql  # Transactions enriched with cohort_month & month_offset
│   ├── int_monthly_revenue.sql   # Monthly revenue series (date spine + complete-month flag)
│   ├── int_revenue_forecast_fits.sql  # Every method fitted at every training cutoff
│   └── schema.yml
│
└── mart/                         # Aggregated, BI-ready metrics (materialized: table)
    ├── mart_customer_retention.sql
    ├── mart_revenue_forecast_backtest.sql   # Forecast vs actual at every cutoff
    ├── mart_revenue_forecast_accuracy.sql   # MAE / RMSE / MAPE / WAPE / bias + model selection
    ├── mart_revenue_forecast.sql            # Next 3 months + 80% interval
    └── schema.yml

tests/                            # Singular tests: reconciliation, no-lookahead, model selection
```

#### Lineage

![DAG lineage](lineage_screenshot.png)

---

### Key Metrics — `mart_customer_retention`

| Column | Description |
|---|---|
| `cohort_month` | Month of first purchase |
| `month_offset` | Months since acquisition (0 = acquisition month) |
| `cohort_size` | Customers acquired in that month |
| `active_customers` | Customers still transacting at this offset |
| `retention_rate_pct` | `active / cohort_size * 100` |
| `churn_rate_pct` | `(1 - active / cohort_size) * 100` |

---

### Revenue Forecasting & Backtest

**Question:** How much revenue should we expect over the next 3 months, and how much can we trust that number?

**Approach**
1. **Build a clean monthly series** (`int_monthly_revenue`). A date spine keeps zero-revenue months, and the in-progress month is flagged. Here, 2024-01 has only one day of data (1,530 vs ~38K normal). Training on it would look like a 96% revenue collapse.
2. **Fit four baseline methods at every historical cutoff** (`int_revenue_forecast_fits`) on an expanding window: `naive`, `historical_mean`, `moving_average` (3 months), and `linear_trend` (OLS). Each cutoff only sees data up to itself.
3. **Backtest out-of-sample** (`mart_revenue_forecast_backtest`). From each cutoff (2023-03 → 2023-11), forecast 1–3 months ahead and score against actuals: 96 scored forecasts.
4. **Select the model by accuracy** (`mart_revenue_forecast_accuracy`). The method with the lowest WAPE across all horizons becomes the headline forecast.
5. **Forecast forward with an uncertainty band** (`mart_revenue_forecast`). The 80% interval is forecast ± 1.28 × backtest RMSE at the same horizon.

**Backtest results**

| Method | WAPE (all horizons) | MAE (1-month ahead) | RMSE (1-month ahead) | Selected |
|---|---|---|---|---|
| `historical_mean` | **16.8%** | 6,815 | 8,848 | ✅ |
| `moving_average` (3m) | 19.1% | 7,793 | 9,667 | |
| `naive` | 27.6% | 11,230 | 13,358 | |
| `linear_trend` | 28.4% | 9,609 | 11,513 | |

**Forecast:** ~**37.9K / month** for 2024-01 to 2024-03. The 1-month-ahead 80% interval is 26.5K to 49.2K.

**What the backtest shows:** The series is noisy with no reliable trend, so the simplest stable method wins. `linear_trend` chases noise and is the least accurate. Without the backtest, the trend model would look like the more sophisticated choice. The interval is wide (about ±30%), and saying so is part of the answer.

**Limitations:** 12 complete months are too few to estimate seasonality, and the backtest sample is small (7–9 forecasts per horizon). The interval assumes roughly normal, unbiased errors. The harness is model-agnostic, so a new method is one more `union all` block in `int_revenue_forecast_fits` and is scored automatically.

---

### Design Decisions

| Decision | Rationale |
|---|---|
| Monthly cohorts (`date_trunc`) | Daily cohorts produce cohort sizes of 1–2, making rates meaningless |
| `QUALIFY ROW_NUMBER()` in `stg_customers` | Deterministic dedup when customer attributes vary across transactions |
| `product_category` propagated to intermediate | Enables downstream category-level retention slices |
| Mart materialized as `table` | Retention queries scan the full dataset; pre-aggregation reduces BI tool latency |
| Exclude incomplete months from training | A partial month looks like a revenue crash and would drag every forecast down |
| One fit model drives both backtest and forecast | The code that is evaluated is the code that is shipped |
| WAPE as the selection metric | Revenue-weighted and stable; MAPE over-weights small months |
| Baselines in SQL, horizon and windows as `vars` | Runs in-warehouse with no Python runtime, and is tunable without code changes |

---

### Data Quality Tests

Defined in `schema.yml` at every layer:

- **Staging:** `unique`, `not_null` on all PKs; `relationships` from `stg_transactions.customer_id` → `stg_customers`; `accepted_values` on `customer_gender`
- **Intermediate:** `unique` on keys, `not_null` on all columns; `accepted_range` (revenue ≥ 0); `unique_combination_of_columns` on forecast fits
- **Mart:** `not_null` on output columns; `unique_combination_of_columns` on every forecast table's grain
- **Singular tests (`tests/`):**
  - `assert_monthly_revenue_reconciles_to_transactions`: monthly totals equal transaction totals (no dropped months, no fan-out)
  - `assert_backtest_has_no_lookahead`: every forecast is trained only on data before its target month
  - `assert_one_selected_forecast_method`: exactly one headline model
  - `assert_forecast_starts_after_last_complete_month`: partial months are forecast, never trained on

`dbt build` passes cleanly: 1 seed, 9 models, 63 tests. To confirm the leakage test is not vacuous, a deliberately injected one-month lookahead made it fail 96 rows and blocked the downstream marts.

---

### Getting Started

```bash
# Install packages
dbt deps

# Load the seed data
dbt seed

# Run all models
dbt run

# Run data quality tests
dbt test

# Run + test together
dbt build
```

---

### Next Steps

1. **Stronger forecast models** — add ETS / Prophet as a dbt Python model and score it in the same backtest harness
2. **Seasonality** — add a seasonal-naive method once 24+ months of history exist
3. **LTV model** — cumulative revenue per cohort → CLTV prediction
4. **Category-level retention & forecast** — slice by `product_category`
5. **Cloud migration** — Snowflake/BigQuery (mostly a `profiles.yml` change, with minor SQL dialect adjustments)

</details>

<details>
<summary><h2>🇰🇷 한국어</h2></summary>

코호트 기반 고객 리텐션 분석과 **백테스트로 검증한 월별 매출 예측**을 위한 프로덕션 스타일 dbt 파이프라인입니다.

**기술 스택:** dbt Core · DuckDB · dbt_utils

---

### 데이터셋

**이커머스 거래 데이터** (합성 데이터):
- 거래 1,000건 · 고유 고객 1,000명
- 기간: 2023-01 ~ 2024-01
- 컬럼: transaction_id, customer_id, date, product_category, quantity, price_per_unit, total_amount, gender, age

> **참고:** 이 시드 데이터는 개념 검증(PoC)용으로, 고객당 거래가 1건뿐입니다.
> 실제 운영 환경에서는 `raw_transactions`를 재구매 이력이 있는 소스 테이블로 교체해야 의미 있는 리텐션 곡선을 확인할 수 있습니다.

---

### 아키텍처

```
seeds/
└── raw_transactions.csv          # 소스: 비정규화된 이커머스 거래 데이터

models/
├── staging/                      # 컬럼명 정리, 타입 변환, 중복 제거 — 비즈니스 로직 없음
│   ├── stg_customers.sql         # 고객당 1행 (QUALIFY로 중복 제거)
│   ├── stg_transactions.sql      # 거래당 1행
│   └── schema.yml                # 컬럼 문서 + unique/not_null/relationships 테스트
│
├── intermediate/                 # 비즈니스 로직
│   ├── int_customer_cohorts.sql  # 거래에 cohort_month, month_offset 추가
│   ├── int_monthly_revenue.sql   # 월별 매출 시계열 (date spine + 완전 월 플래그)
│   ├── int_revenue_forecast_fits.sql  # 모든 학습 시점에서 모든 방법을 fitting
│   └── schema.yml
│
└── mart/                         # 집계된 BI용 지표 (materialized: table)
    ├── mart_customer_retention.sql
    ├── mart_revenue_forecast_backtest.sql   # 시점별 예측 vs 실제
    ├── mart_revenue_forecast_accuracy.sql   # MAE / RMSE / MAPE / WAPE / bias + 모델 선택
    ├── mart_revenue_forecast.sql            # 향후 3개월 예측 + 80% 구간
    └── schema.yml

tests/                            # Singular 테스트: 정합성, 미래 데이터 누수 방지, 모델 선택
```

#### 리니지 (Lineage)

![DAG lineage](lineage_screenshot.png)

---

### 핵심 지표 — `mart_customer_retention`

| 컬럼 | 설명 |
|---|---|
| `cohort_month` | 첫 구매 월 |
| `month_offset` | 첫 구매 이후 경과 개월 수 (0 = 첫 구매 월) |
| `cohort_size` | 해당 월에 신규 획득한 고객 수 |
| `active_customers` | 해당 시점에도 구매 중인 고객 수 |
| `retention_rate_pct` | `active / cohort_size * 100` |
| `churn_rate_pct` | `(1 - active / cohort_size) * 100` |

---

### 매출 예측 & 백테스트

**질문:** 향후 3개월 매출은 얼마로 예상되고, 그 숫자를 얼마나 믿을 수 있는가?

**접근 방식**
1. **깨끗한 월별 시계열 구축** (`int_monthly_revenue`): date spine으로 매출 0인 달도 유지하고, 진행 중인 달은 플래그로 표시합니다. 이 데이터에서 2024-01은 하루치뿐입니다(1,530, 평소 약 38K). 그대로 학습하면 매출이 96% 폭락한 것처럼 보입니다.
2. **모든 과거 시점에서 4가지 베이스라인 fitting** (`int_revenue_forecast_fits`): expanding window 방식으로 `naive`, `historical_mean`, `moving_average`(3개월), `linear_trend`(OLS)를 fitting합니다. 각 시점은 자기 자신까지의 데이터만 봅니다.
3. **표본 외(out-of-sample) 백테스트** (`mart_revenue_forecast_backtest`): 각 시점(2023-03 → 2023-11)에서 1~3개월 앞을 예측해 실제값과 비교합니다. 채점한 예측은 총 96건입니다.
4. **정확도 기반 모델 선택** (`mart_revenue_forecast_accuracy`): 전체 horizon 기준 WAPE가 가장 낮은 방법을 대표 예측으로 씁니다.
5. **불확실성 구간을 포함한 미래 예측** (`mart_revenue_forecast`): 80% 구간은 같은 horizon의 백테스트 RMSE로 계산합니다(예측 ± 1.28 × RMSE).

**백테스트 결과**

| 방법 | WAPE (전체 horizon) | MAE (1개월 후) | RMSE (1개월 후) | 선택 |
|---|---|---|---|---|
| `historical_mean` | **16.8%** | 6,815 | 8,848 | ✅ |
| `moving_average` (3개월) | 19.1% | 7,793 | 9,667 | |
| `naive` | 27.6% | 11,230 | 13,358 | |
| `linear_trend` | 28.4% | 9,609 | 11,513 | |

**예측:** 2024-01 ~ 2024-03 매출은 **월 약 37.9K**로 예상됩니다. 1개월 후 기준 80% 구간은 26.5K ~ 49.2K입니다.

**백테스트가 보여준 것:** 시계열에 노이즈가 크고 믿을 만한 추세가 없어서, 가장 단순하고 안정적인 방법이 이겼습니다. `linear_trend`는 노이즈를 추세로 착각해 가장 부정확했습니다. 백테스트가 없었다면 더 정교해 보이는 추세 모델을 골랐을 것입니다. 구간이 넓다(약 ±30%)는 점을 숨기지 않고 함께 보고하는 것도 답의 일부입니다.

**한계:** 완전한 월이 12개뿐이라 계절성은 추정할 수 없고, 백테스트 표본도 horizon당 7~9건으로 작습니다. 구간은 오차가 대략 정규분포이고 편향이 없다고 가정합니다. 하네스는 모델에 독립적이라, `int_revenue_forecast_fits`에 `union all` 블록 하나만 추가하면 새 방법도 자동으로 채점됩니다.

---

### 설계 의사결정

| 결정 | 근거 |
|---|---|
| 월 단위 코호트 (`date_trunc`) | 일 단위 코호트는 규모가 1~2명에 그쳐 비율이 의미 없어짐 |
| `stg_customers`에서 `QUALIFY ROW_NUMBER()` 사용 | 거래마다 고객 속성이 다를 때도 결정적으로(deterministic) 중복 제거 |
| `product_category`를 intermediate까지 전달 | 카테고리별 리텐션 분석으로 확장 가능 |
| Mart를 `table`로 구체화 | 리텐션 쿼리는 전체 데이터를 스캔하므로, 사전 집계로 BI 도구 응답 속도 개선 |
| 불완전 월은 학습에서 제외 | 부분 월은 매출 급락처럼 보여 모든 예측을 끌어내림 |
| 백테스트와 실제 예측이 같은 fit 모델 사용 | 평가한 코드가 곧 배포되는 코드 |
| 모델 선택 지표로 WAPE 사용 | 매출 가중이라 안정적이며, MAPE는 매출이 작은 달에 과도하게 반응 |
| 베이스라인은 SQL로, horizon·윈도우는 `vars`로 | Python 런타임 없이 웨어하우스 안에서 실행되고, 코드 수정 없이 조정 가능 |

---

### 데이터 품질 테스트

모든 레이어의 `schema.yml`에 정의되어 있습니다:

- **Staging:** 모든 PK에 `unique`, `not_null`; `stg_transactions.customer_id` → `stg_customers` 간 `relationships`; `customer_gender`에 `accepted_values`
- **Intermediate:** 키에 `unique`, 전 컬럼 `not_null`; `accepted_range`(매출 ≥ 0); forecast fit에 `unique_combination_of_columns`
- **Mart:** 출력 컬럼 `not_null`; 모든 예측 테이블의 grain에 `unique_combination_of_columns`
- **Singular 테스트 (`tests/`):**
  - `assert_monthly_revenue_reconciles_to_transactions`: 월별 합계와 거래 합계 일치 (누락 월·중복 집계 방지)
  - `assert_backtest_has_no_lookahead`: 모든 예측은 대상 월 이전 데이터로만 학습
  - `assert_one_selected_forecast_method`: 대표 모델은 정확히 하나
  - `assert_forecast_starts_after_last_complete_month`: 부분 월은 예측 대상일 뿐 학습에 쓰지 않음

`dbt build` 결과 seed 1개, 모델 9개, 테스트 63개가 모두 통과합니다. 누수 테스트가 형식적이지 않은지 확인하려고 1개월 미래 데이터 누수를 일부러 넣어 봤고, 96건 실패로 잡아내며 하위 마트 빌드를 막았습니다.

---

### 시작하기

```bash
# 패키지 설치
dbt deps

# 시드 데이터 로드
dbt seed

# 전체 모델 실행
dbt run

# 데이터 품질 테스트 실행
dbt test

# 실행 + 테스트 한 번에
dbt build
```

---

### 향후 계획

1. **더 강한 예측 모델** — ETS / Prophet을 dbt Python 모델로 추가하고 같은 백테스트 하네스로 채점
2. **계절성** — 24개월 이상 데이터가 쌓이면 seasonal-naive 방법 추가
3. **LTV 모델** — 코호트별 누적 매출 → CLTV 예측
4. **카테고리별 리텐션 & 예측** — `product_category`로 세분화
5. **클라우드 마이그레이션** — Snowflake/BigQuery (주로 `profiles.yml` 변경, 일부 SQL 방언 조정 필요)

</details>
