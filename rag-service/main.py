# FastAPI 엔트리포인트 (PB1~). 실제 라우팅은 후속 단계에서 구현.
from fastapi import FastAPI

app = FastAPI(title="internal-docs-rag")


@app.get("/api/health")
def health():
    # 후속: RAGFlow/Ollama/모델/GPU까지 확인하는 deep health (부록 D.2 B4)
    return {"status": "ok"}
