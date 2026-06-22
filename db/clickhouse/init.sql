-- ══════════════════════════════════════════════════════
--  ObserveAI — ClickHouse Schema
--  Engine: MergeTree (columnar, optimized for analytics)
-- ══════════════════════════════════════════════════════

CREATE DATABASE IF NOT EXISTS observeai;

-- ── traces ─────────────────────────────────────────────
-- Every LLM call intercepted by the SDK lands here.
-- ORDER BY is critical — ClickHouse sorts data on disk by
-- (tenant_id, model, created_at) for fast per-tenant queries.
CREATE TABLE IF NOT EXISTS observeai.traces
(
    trace_id        UUID,
    tenant_id       UUID,
    project_id      UUID,
    session_id      UUID,
    model           String,
    prompt          String,
    response        String,
    input_tokens    UInt32,
    output_tokens   UInt32,
    total_tokens    UInt32,
    cost_usd        Float64,
    latency_ms      UInt32,
    status          String,
    error_message   String,
    created_at      DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (tenant_id, model, created_at)
PARTITION BY toYYYYMM(created_at)
TTL created_at + INTERVAL 90 DAY;

-- ── evaluations ────────────────────────────────────────
-- AI quality scores for each trace, written by eval-engine.
-- Linked to traces by trace_id.
CREATE TABLE IF NOT EXISTS observeai.evaluations
(
    eval_id              UUID,
    trace_id             UUID,
    tenant_id            UUID,
    project_id           UUID,
    hallucination_score  Float32,
    context_precision    Float32,
    context_recall       Float32,
    answer_relevancy     Float32,
    toxicity_score       Float32,
    pii_detected         UInt8,
    semantic_drift_score Float32,
    evaluated_at         DateTime DEFAULT now()
)
ENGINE = MergeTree()
ORDER BY (tenant_id, trace_id, evaluated_at)
PARTITION BY toYYYYMM(evaluated_at);

-- ── Materialized View 1: hourly cost by model ──────────
-- Pre-aggregates cost data every hour so dashboard queries
-- are instant instead of scanning millions of raw rows.
CREATE TABLE IF NOT EXISTS observeai.hourly_cost_by_model
(
    tenant_id   UUID,
    model       String,
    hour        DateTime,
    total_cost  Float64,
    trace_count UInt64
)
ENGINE = SummingMergeTree()
ORDER BY (tenant_id, model, hour);

CREATE MATERIALIZED VIEW IF NOT EXISTS observeai.mv_hourly_cost
TO observeai.hourly_cost_by_model
AS SELECT
    tenant_id,
    model,
    toStartOfHour(created_at) AS hour,
    sum(cost_usd)             AS total_cost,
    count()                   AS trace_count
FROM observeai.traces
GROUP BY tenant_id, model, hour;

-- ── Materialized View 2: daily token usage ─────────────
CREATE TABLE IF NOT EXISTS observeai.daily_token_usage
(
    tenant_id     UUID,
    project_id    UUID,
    date          Date,
    input_tokens  UInt64,
    output_tokens UInt64,
    total_tokens  UInt64
)
ENGINE = SummingMergeTree()
ORDER BY (tenant_id, project_id, date);

CREATE MATERIALIZED VIEW IF NOT EXISTS observeai.mv_daily_tokens
TO observeai.daily_token_usage
AS SELECT
    tenant_id,
    project_id,
    toDate(created_at)      AS date,
    sum(input_tokens)       AS input_tokens,
    sum(output_tokens)      AS output_tokens,
    sum(total_tokens)       AS total_tokens
FROM observeai.traces
GROUP BY tenant_id, project_id, date;

-- ── Materialized View 3: latency percentiles ───────────
CREATE TABLE IF NOT EXISTS observeai.hourly_latency
(
    tenant_id    UUID,
    model        String,
    hour         DateTime,
    p50_ms       Float64,
    p95_ms       Float64,
    p99_ms       Float64,
    trace_count  UInt64
)
ENGINE = AggregatingMergeTree()
ORDER BY (tenant_id, model, hour);

CREATE MATERIALIZED VIEW IF NOT EXISTS observeai.mv_latency_percentiles
TO observeai.hourly_latency
AS SELECT
    tenant_id,
    model,
    toStartOfHour(created_at)           AS hour,
    quantile(0.50)(latency_ms)          AS p50_ms,
    quantile(0.95)(latency_ms)          AS p95_ms,
    quantile(0.99)(latency_ms)          AS p99_ms,
    count()                             AS trace_count
FROM observeai.traces
GROUP BY tenant_id, model, hour;
