#!/usr/bin/env bash
# 사내문서 RAG — 디렉토리 구조 부트스트랩 (설계문서 §12.2 기준)
# 사용: bash bootstrap.sh   (레포 루트에서 실행)
set -euo pipefail

echo "==> 디렉토리 생성"
mkdir -p \
  auth-service \
  rag-service/auth \
  rag-service/acl \
  rag-service/ragflow_client \
  rag-service/rerank \
  rag-service/generate \
  rag-service/audit \
  nginx \
  eval \
  models \
  db/init

echo "==> Python 패키지 마커(__init__.py)"
for d in auth acl ragflow_client rerank generate audit; do
  touch "rag-service/${d}/__init__.py"
done
touch rag-service/__init__.py

echo "==> 빈 디렉토리 유지용 .gitkeep"
for d in auth-service nginx eval models; do
  touch "${d}/.gitkeep"
done

echo "==> 플레이스홀더 파일"
[ -f rag-service/main.py ] || cat > rag-service/main.py <<'PY'
# FastAPI 엔트리포인트 (PB1~). 실제 라우팅은 후속 단계에서 구현.
from fastapi import FastAPI

app = FastAPI(title="internal-docs-rag")


@app.get("/api/health")
def health():
    # 후속: RAGFlow/Ollama/모델/GPU까지 확인하는 deep health (부록 D.2 B4)
    return {"status": "ok"}
PY

[ -f README.md ] || cat > README.md <<'MD'
# 사내 문서 RAG 시스템

RAGFlow 기반 Internal Document RAG (폴리글랏: Spring Boot + Python + nginx).
설계: `사내문서_RAG_시스템_설계문서_v3.md` 참조.

## 부팅 (DB 먼저 검증)
```bash
cp .env.example .env   # 값 채우기
docker compose up -d postgres
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c '\dn'
```
MD

echo "==> 완료. 트리:"
find . -maxdepth 3 -not -path '*/.git/*' | sort
