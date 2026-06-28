#!/usr/bin/env bash
# 사내문서 RAG — Ollama 모델 다운로드 (설계 §5.1, 인프라 가이드 §3.2)
#
# 언제 실행하나:
#   - 새 머신/CI처럼 호스트에 모델 스토어가 없을 때.
#   - 이 레포는 기본적으로 .env의 OLLAMA_STORE가 호스트 ~/.ollama(이미 받아둔 스토어)를
#     컨테이너에 마운트하므로, 로컬에서는 보통 이 스크립트가 필요 없다.
#   - OLLAMA_STORE를 비워 named volume(ollama_data)로 시작했다면 이 스크립트로 모델을 받는다.
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose up -d ollama

echo "==> LLM (생성, GPU, Q4_K_M ~5GB)"
docker compose exec ollama ollama pull qwen3:8b

echo "==> VLM (이미지·표 이해, 색인 시, GPU ~6GB)"
# 주의: VLM 태그는 변동 가능. https://ollama.com/library/qwen3-vl 에서 확인 후 필요시 교체.
docker compose exec ollama ollama pull qwen3-vl:8b

echo "==> 임베딩은 pull하지 않음 (RAGFlow 풀 에디션 내장 BGE-M3 사용)"

docker compose exec ollama ollama list
