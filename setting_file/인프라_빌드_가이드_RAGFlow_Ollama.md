# 인프라 빌드 가이드 — RAGFlow + Ollama (1단계)

> 사내문서 RAG 시스템(v3)의 **1단계: 추론·검색 인프라** 빌드 가이드.
> 전제: **0단계(디렉토리 골격 + PostgreSQL auth/app 스키마 격리) 완료**, Docker 엔진 설치됨.
> 이 문서만 읽고 **RAGFlow 풀 스택 + Ollama(LLM/VLM) 기동 + 상호 연동·검증**까지 재현하도록 작성됨.
> 이 파일을 레포 루트의 `CLAUDE.md`로 두면 Claude Code가 자동 로드함.
> 설계 근거: `사내문서_RAG_시스템_설계문서_v3.md` §5(모델·실행 위치), §12.1(인프라), 부록 D.2 B1(색인↔질의 동시성), D.1 A1(RAGFlow 격리).

---

## 0. 목표

RAGFlow **풀 에디션** 스택과 **Ollama**(LLM·VLM)를 올리고, RAGFlow가 Ollama를 로컬 모델 서버로 인식하도록 연결한다.
완성선(Definition of Done): **(1) 컨테이너 안에서 GPU가 보이고, (2) Ollama가 모델에 응답하고, (3) RAGFlow UI가 뜨고 Ollama 모델이 연결되며, (4) 스모크 문서 1개가 파싱·검색된다.**
실제 RAG 파이프라인(검색 호출·리랭킹·적응형 컷오프·생성)은 다음 단계(Python `rag-service`)로 미룬다.

---

## 1. 스코프 가드 (반드시 지킬 것)

**이번 단계에서 할 것**
- [x] Ollama 컨테이너 기동 + 모델 pull (LLM=`qwen3:8b`, VLM=`qwen3-vl:8b`)
- [x] 단일 모델 적재 정책(`OLLAMA_MAX_LOADED_MODELS=1`)으로 B1(VRAM 경합) 선제 대응
- [x] RAGFlow 공식 compose 기동(풀 에디션, 안정 태그 핀)
- [x] RAGFlow UI에서 Ollama(채팅·VLM) + 내장 BGE-M3(임베딩) 모델 등록
- [x] GPU 패스스루 검증 + 스모크 문서 1개 파싱·검색

**이번 단계에서 하지 말 것 (feature creep 금지)**
- [ ] ❌ 리랭커(`bge-reranker-v2-m3`) 설치 — Python `rag-service`의 **런타임 의존**(FlagEmbedding·CPU)이라 다음 단계
- [ ] ❌ 검색 호출·리랭킹·**적응형 컷오프**·생성 코드 (PB 트랙)
- [ ] ❌ `rag-service` ↔ RAGFlow API 클라이언트 코드
- [ ] ❌ nginx 라우팅, Spring `auth-service`
- [ ] ❌ 사내 문서 **대량** 업로드 — 동작 확인용 **1~2개만**
- [ ] ❌ `DEVICE=gpu`를 무조건 켜기 — VRAM 보고 결정(§4.3 주의)

> 임베딩은 **RAGFlow 풀 에디션 내장(TEI)** 으로 처리한다. Ollama에 임베딩 모델을 올리지 않는다(설계 §5.1: 임베딩=CPU/RAGFlow 내장).

---

## 2. 사전 점검 — 호스트 (한 번만)

```bash
# (1) 버전: Docker >= 24, Compose >= 2.26.1
docker --version
docker compose version

# (2) ES용 커널 파라미터: vm.max_map_count >= 262144
sysctl vm.max_map_count
#   값이 작으면:
sudo sysctl -w vm.max_map_count=262144
#   재부팅 후에도 유지:
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf

# (3) GPU 패스스루: NVIDIA Container Toolkit이 컨테이너에서 GPU를 보이게 하는지
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
#   → RTX 4070 Ti가 보이면 OK. 안 보이면 nvidia-container-toolkit 설치 후
#     sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
```

---

## 3. Ollama — 컨테이너 + 모델

### 3.1 compose 서비스 (0단계 `docker-compose.yml`에 병합)
> 0단계에는 `postgres`만 있다. 아래 `ollama` 서비스를 같은 파일에 추가한다.

```yaml
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    ports: ["11434:11434"]          # 로컬 개발 편의. 운영 전환 시 내부망 한정 검토.
    volumes: ["ollama_data:/root/.ollama"]
    environment:
      - OLLAMA_MAX_LOADED_MODELS=1   # B1: VLM(색인)·LLM(질의) 동시 적재로 인한 OOM 방지
      - OLLAMA_KEEP_ALIVE=5m         # 유휴 시 언로드해 VRAM 회수(콜드스타트 비용은 B3에서 별도)
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

volumes:
  ollama_data:
  # (0단계의 pg_data 등 기존 volume과 같은 블록에 합칠 것)
```

### 3.2 모델 pull (`models/pull_models.sh`)
```bash
#!/usr/bin/env bash
# 사내문서 RAG — Ollama 모델 다운로드 (설계 §5.1)
set -euo pipefail

docker compose up -d ollama

echo "==> LLM (생성, GPU, Q4_K_M ~6GB)"
docker compose exec ollama ollama pull qwen3:8b

echo "==> VLM (이미지·표 이해, 색인 시, GPU ~6GB)"
# 주의: VLM 태그는 변동 가능. https://ollama.com/library/qwen3-vl 에서
#       실제 제공 태그(예: qwen3-vl:8b)를 확인 후 필요시 교체.
docker compose exec ollama ollama pull qwen3-vl:8b

echo "==> 임베딩은 pull하지 않음 (RAGFlow 풀 에디션 내장 BGE-M3 사용)"

docker compose exec ollama ollama list
```

> **버전 확인 메모**: `qwen3` 계열은 상위 버전(예: 3.5/3.6)이 나왔을 수 있다. `https://ollama.com/library` 에서 VRAM(실효 8~10GB, **14B 경로 제외 — 설계 §5.3**)에 맞는 최신 8B급을 확인하고 태그를 고정한다.

---

## 4. RAGFlow — 공식 스택

### 4.1 클론 + 안정 태그 핀
> RAGFlow는 **자체 compose**(ES/Infinity·MySQL·MinIO·Redis 포함)로 뜬다. 앱 레포와 별도 디렉토리(예: 레포 외부 또는 `infra/ragflow`)에 클론한다.

```bash
git clone https://github.com/infiniflow/ragflow.git
cd ragflow
# 안정 태그 고정 (현재 기준 v0.26.0; releases에서 최신 stable 재확인)
#   https://github.com/infiniflow/ragflow/releases
git checkout v0.26.0
```

### 4.2 `.env` 설정 (`ragflow/docker/.env`)
```bash
# (1) 풀 에디션 사용 — 슬림(-slim) 금지.
#     이유: 데이터 비유출 + 임베딩(BGE-M3) 오프라인 내장이 필요.
RAGFLOW_IMAGE=infiniflow/ragflow:v0.26.0

# (2) 기본 크리덴셜은 반드시 교체 (A3 대비: 번들 MySQL·Redis·MinIO 기본 비번)
#     MYSQL_PASSWORD / MINIO_PASSWORD / REDIS 등 .env의 비밀번호를 새 값으로.

# (3) 웹/HTTP 포트 확인 (기본 80; 0단계 서비스와 충돌하면 SVR_HTTP_PORT 변경)
```

### 4.3 DeepDoc GPU 여부 — VRAM 보고 결정 (B1 직결, **주의**)
```bash
# 선택지 A) DeepDoc을 GPU로 (.env 맨 앞에 DEVICE=gpu 추가)
#   sed -i '1i DEVICE=gpu' .env
#
# 선택지 B) DeepDoc은 CPU(기본, DEVICE 미설정) — 권장 시작점
```
> **왜 무조건 GPU가 아닌가**: 실효 VRAM 8~10GB에서 색인 시 **VLM(~6GB) + DeepDoc GPU**가 겹치면 한도를 넘긴다(설계 §5.3·부록 D.2 B1). 시작은 **DeepDoc=CPU**로 두고 VLM만 GPU에 올리는 쪽이 안전하다. 색인 처리량이 답답하면 그때 `DEVICE=gpu`로 올리되, 색인↔질의 **시간 분리**(야간 배치)를 함께 적용한다.

### 4.4 기동
```bash
cd ragflow
docker compose -f docker/docker-compose.yml up -d
docker compose -f docker/docker-compose.yml ps
# ragflow 컨테이너 로그에서 기동 완료 라인 확인 (수 분 소요 가능)
docker compose -f docker/docker-compose.yml logs -f ragflow
```

---

## 5. RAGFlow ↔ Ollama 연동 (UI 설정)

> RAGFlow는 Ollama를 추가 환경설정 없이 로컬 모델 서버로 바로 연동한다(공식 지원).

1. 브라우저에서 RAGFlow UI 접속 → 첫 계정 생성(관리자).
2. **모델 공급자(Model Providers)** 에서 **Ollama** 추가.
   - Base URL: Ollama가 같은 도커 네트워크면 `http://ollama:11434`,
     아니면 호스트 경유 `http://host.docker.internal:11434`.
3. 모델 등록:
   - **Chat model**: `qwen3:8b` — *이번 단계는 연결 확인용*. 실제 답변 생성은 **모드 B**라 Python `rag-service`가 한다(여기서 끝까지 쓰지 않음).
   - **Embedding model**: 내장 **BGE-M3** 선택(풀 에디션 포함).
   - **Image2Text(VLM)**: `qwen3-vl:8b` — 색인 시 표·이미지 이해.

---

## 6. 네트워크 격리 — A1 준비 (이번 단계는 "메모"만)

- 목표: RAGFlow API를 **Python `rag-service`만** 호출하도록 좁히고, **API 토큰**을 추가(심층 방어). → 설계 결정사항 #4 (a)+(b).
- 이번 단계 범위: RAGFlow가 만드는 **도커 네트워크 이름을 확인**해 둔다.
  ```bash
  docker network ls | grep -i ragflow
  ```
- **강제는 다음 단계**: `rag-service`를 위 네트워크에 합류시키고, RAGFlow API 포트(:9380)를 **호스트로 공개하지 않도록** 정리 + 토큰 적용.
- 지금 RAGFlow API를 호스트 포트로 노출했다면, 다음 단계에서 닫을 것을 README/TODO에 남긴다.

---

## 7. 검증 게이트 (Definition of Done)

아래가 모두 통과해야 1단계 완료:

```bash
# (1) 컨테이너에서 GPU 인식
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi   # 4070 Ti 표시

# (2) Ollama 모델 목록
docker compose exec ollama ollama list                                     # qwen3:8b, qwen3-vl:8b

# (3) Ollama 생성 스모크 (한국어 응답 확인)
curl -s http://localhost:11434/api/generate \
  -d '{"model":"qwen3:8b","prompt":"한 문장으로 자기소개 해줘","stream":false}'

# (4) RAGFlow 스택 상태 (모든 의존 컨테이너 Up/healthy)
docker compose -f docker/docker-compose.yml ps

# (5) RAGFlow UI 접속 (기본 80, 변경했다면 해당 포트)
curl -sI http://localhost:80 | head -n 1                                   # HTTP 200/302
```

UI 수동 확인:
- [ ] (6) RAGFlow UI 로그인 → **Ollama 모델 연결 성공**(채팅·임베딩·VLM 등록 OK)
- [ ] (7) **스모크 문서 1개**(한국어 PDF 또는 표 포함) 업로드 → 파싱·청킹 완료, 검색창에서 1건 이상 회수

체크리스트:
- [ ] (1) 컨테이너 GPU 인식
- [ ] (2) 모델 2개 존재
- [ ] (3) LLM 한국어 응답
- [ ] (4) RAGFlow 의존 스택 전부 Up
- [ ] (5) UI HTTP 응답
- [ ] (6) Ollama 모델 연결
- [ ] (7) 스모크 문서 파싱·검색

---

## 8. 미해결 / 다음 단계로 넘김 (여기서 구현 금지)

- **Python `rag-service` (PB 트랙)**: RAGFlow API 클라이언트 → 리랭킹(`bge-reranker-v2-m3`, FlagEmbedding·CPU) → **적응형 컷오프** → Ollama 생성 → 인용 매핑.
- **A1 완성**: `rag-service`를 RAGFlow 네트워크에 합류 + RAGFlow API 토큰, :9380 호스트 비공개.
- **B1 동시성 확정**: 색인=야간 배치 강제(MVP) vs 큐잉+VRAM 가드(고도화). 어느 쪽이든 §5.3 실효 8~10GB 전제 위에서.
- **A3**: RAGFlow 번들 스택(MySQL·Redis·MinIO) 기본 크리덴셜 전수 교체 확인 + 내부 구간 암호화 범위.
- **B3 콜드스타트**: `OLLAMA_KEEP_ALIVE` / 모델 상주 정책 — 첫 질의 로드 지연 측정 후 결정.
