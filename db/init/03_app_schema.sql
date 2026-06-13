-- ════════════════════════════════════════════════════════════
--  app 스키마 — Python(FastAPI) 소유 (audit_log, query_history)
--  user_sub는 JWT 'sub' 문자열만 보관(스키마 격리 위해 auth로 FK 걸지 않음).
-- ════════════════════════════════════════════════════════════
CREATE SCHEMA IF NOT EXISTS app;

-- 질의 이력
CREATE TABLE app.query_history (
    id               BIGINT GENERATED ALWAYS AS IDENTITY,
    correlation_id   UUID         NOT NULL,            -- 폴리글랏 추적 ID (D2)
    user_sub         VARCHAR(128) NOT NULL,            -- JWT sub
    question         TEXT         NOT NULL,            -- PII 가능 → 마스킹/보존 정책(D2)
    answer           TEXT,
    selected_chunks  INT,
    reranker_device  VARCHAR(16),
    model            VARCHAR(64),
    latency_ms       INT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- 감사 로그: 질의·근거 문서 접근 이력 (§13)
CREATE TABLE app.audit_log (
    id              BIGINT GENERATED ALWAYS AS IDENTITY,
    correlation_id  UUID         NOT NULL,
    user_sub        VARCHAR(128) NOT NULL,
    event_type      VARCHAR(64)  NOT NULL,             -- query/doc_access/upload/delete...
    doc_id          VARCHAR(128),                      -- 접근한 근거 문서
    detail          JSONB,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

CREATE INDEX idx_query_history_user_time ON app.query_history (user_sub, created_at DESC);
CREATE INDEX idx_audit_correlation       ON app.audit_log (correlation_id);
CREATE INDEX idx_audit_user_time         ON app.audit_log (user_sub, created_at DESC);

-- ── 권한: app_service는 app 스키마만 ───────────────────────────
GRANT USAGE ON SCHEMA app TO app_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA app TO app_service;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA app TO app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT USAGE, SELECT                  ON SEQUENCES TO app_service;
