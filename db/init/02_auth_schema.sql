-- ════════════════════════════════════════════════════════════
--  auth 스키마 — Spring Boot 소유 (users, roles, departments, credentials)
--  JWT claim의 roles[], department[]가 배열이므로 사용자↔역할/부서는 다대다.
-- ════════════════════════════════════════════════════════════
CREATE SCHEMA IF NOT EXISTS auth;

-- 부서: 'security', 'all'(전사 공개) 등 (§8.1)
CREATE TABLE auth.departments (
    id          BIGINT GENERATED ALWAYS AS IDENTITY,
    code        VARCHAR(64)  NOT NULL UNIQUE,
    name        VARCHAR(128) NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- 역할: 'employee', 'admin' 등
CREATE TABLE auth.roles (
    id          BIGINT GENERATED ALWAYS AS IDENTITY,
    code        VARCHAR(64)  NOT NULL UNIQUE,
    name        VARCHAR(128) NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- 사용자: external_id = JWT sub(사번/계정 ID)
CREATE TABLE auth.users (
    id            BIGINT GENERATED ALWAYS AS IDENTITY,
    external_id   VARCHAR(128) NOT NULL UNIQUE,   -- JWT 'sub'
    email         VARCHAR(255) NOT NULL UNIQUE,
    display_name  VARCHAR(128) NOT NULL,
    status        VARCHAR(32)  NOT NULL DEFAULT 'active', -- active/suspended/left (A2)
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

-- 로컬/SSO 자격증명. SSO 전용이면 password_hash는 NULL.
CREATE TABLE auth.credentials (
    user_id        BIGINT      NOT NULL,
    provider       VARCHAR(32) NOT NULL DEFAULT 'local',  -- local/oidc/saml
    password_hash  VARCHAR(255),                          -- bcrypt/argon2 (local만)
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id),
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- 사용자 ↔ 역할 (다대다)
CREATE TABLE auth.user_roles (
    user_id  BIGINT NOT NULL,
    role_id  BIGINT NOT NULL,
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (user_id) REFERENCES auth.users(id)  ON DELETE CASCADE,
    FOREIGN KEY (role_id) REFERENCES auth.roles(id)  ON DELETE CASCADE
);

-- 사용자 ↔ 부서 (다대다)
CREATE TABLE auth.user_departments (
    user_id        BIGINT NOT NULL,
    department_id  BIGINT NOT NULL,
    PRIMARY KEY (user_id, department_id),
    FOREIGN KEY (user_id)       REFERENCES auth.users(id)        ON DELETE CASCADE,
    FOREIGN KEY (department_id) REFERENCES auth.departments(id)  ON DELETE CASCADE
);

-- 시드(개발용 최소값)
INSERT INTO auth.departments (code, name) VALUES
    ('all', '전사 공개'), ('security', '보안팀'), ('hr', '인사팀');
INSERT INTO auth.roles (code, name) VALUES
    ('employee', '일반 직원'), ('admin', '관리자');

-- ── 권한: auth_service는 auth 스키마만 ──────────────────────────
GRANT USAGE ON SCHEMA auth TO auth_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA auth TO auth_service;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA auth TO auth_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO auth_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth
    GRANT USAGE, SELECT                  ON SEQUENCES TO auth_service;
