from sentence_transformers import CrossEncoder

reranker = CrossEncoder("BAAI/bge-reranker-v2-m3", device="cpu")
pairs = [
    ["출장비 정산 방법", "출장비는 사전 승인 후 영수증 첨부로 정산합니다."],
    ["출장비 정산 방법", "사내 연차는 연 15일 부여됩니다."],
]
print(reranker.predict(pairs))   # 첫 번째가 더 높으면 정상
