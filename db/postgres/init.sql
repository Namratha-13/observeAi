-- ObserveAI PostgreSQL Schema

CREATE TABLE IF NOT EXISTS tenants (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       VARCHAR(255) NOT NULL,
    email      VARCHAR(255) NOT NULL UNIQUE,
    plan       VARCHAR(50)  NOT NULL DEFAULT 'free',
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS projects (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        VARCHAR(255) NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS api_keys (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    project_id   UUID         NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    key_hash     VARCHAR(255) NOT NULL UNIQUE,
    key_prefix   VARCHAR(10)  NOT NULL,
    name         VARCHAR(255),
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS users (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id  UUID         NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email      VARCHAR(255) NOT NULL UNIQUE,
    name       VARCHAR(255) NOT NULL,
    role       VARCHAR(50)  NOT NULL DEFAULT 'viewer',
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS alert_rules (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id      UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    project_id     UUID        NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    rule_type      VARCHAR(50) NOT NULL,
    threshold      FLOAT       NOT NULL,
    window_hours   INT         NOT NULL DEFAULT 24,
    channel        VARCHAR(50) NOT NULL DEFAULT 'webhook',
    channel_config JSONB,
    is_active      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS model_pricing (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    model_id           VARCHAR(100) NOT NULL UNIQUE,
    provider           VARCHAR(50)  NOT NULL,
    input_cost_per_1k  FLOAT        NOT NULL,
    output_cost_per_1k FLOAT        NOT NULL,
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS project_eval_config (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id              UUID    NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    hallucination_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    rag_quality_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    toxicity_enabled        BOOLEAN NOT NULL DEFAULT TRUE,
    pii_detection_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    hallucination_threshold FLOAT   NOT NULL DEFAULT 0.5,
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_projects_tenant   ON projects(tenant_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_hash     ON api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_tenant   ON api_keys(tenant_id);
CREATE INDEX IF NOT EXISTS idx_alert_rules_project ON alert_rules(project_id);

INSERT INTO model_pricing (model_id, provider, input_cost_per_1k, output_cost_per_1k) VALUES
    ('gpt-4o',            'openai',    0.005,   0.015),
    ('gpt-4o-mini',       'openai',    0.00015, 0.0006),
    ('gpt-4-turbo',       'openai',    0.01,    0.03),
    ('gpt-3.5-turbo',     'openai',    0.0005,  0.0015),
    ('claude-3-5-sonnet', 'anthropic', 0.003,   0.015),
    ('claude-3-5-haiku',  'anthropic', 0.001,   0.005),
    ('claude-3-opus',     'anthropic', 0.015,   0.075)
ON CONFLICT (model_id) DO NOTHING;
