# Custom Elasticsearch image: adds the ICU analysis plugin (analysis-icu)
# used by search-svc for the vietnamese_icu analyzer (icu_tokenizer + icu_folding).
# The official image does NOT bundle analysis-icu — without it, creating the
# search index with vietnamese_icu fails. Build: docker compose build elasticsearch.
# Docs: master-plan.md:238 (W6 Vietnamese analyzer).
FROM docker.elastic.co/elasticsearch/elasticsearch:8.13.2
RUN bin/elasticsearch-plugin install --batch analysis-icu