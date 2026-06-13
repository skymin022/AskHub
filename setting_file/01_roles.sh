#!/bin/bash
# 서비스별 DB 계정 생성 — 비밀번호는 env에서 주입(SQL 파일에 시크릿 하드코딩 금지, §13)
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  -- LOGIN 계정. 스키마 GRANT는 02/03 SQL에서 각각 부여(스키마 단위 격리).
  CREATE ROLE auth_service LOGIN PASSWORD '${AUTH_DB_PASSWORD}';
  CREATE ROLE app_service  LOGIN PASSWORD '${APP_DB_PASSWORD}';

  -- 기본 스키마(public) 무권한화: 격리 강제
  REVOKE ALL ON SCHEMA public FROM auth_service, app_service;
EOSQL
