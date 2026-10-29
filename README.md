# Aunt Flo Assistant

A retrieval-augmented chatbot for menstrual and reproductive health education, rebuilt on a modern
hybrid-RAG stack. It runs **entirely on your own machine** (macOS first): no cloud, no API keys, no
paid subscriptions, and your questions never leave your laptop.

## What changed from the original

| | Before | Now |
|---|---|---|
| Model format | GGML (deprecated) | GGUF via **Ollama** |
| Retrieval | FAISS, dense only | **Qdrant** + **BM25 hybrid search** + cross-encoder **reranker** (toggleable) |
| Embeddings | implicit/basic | **BAAI/bge-small-en-v1.5** |
| Architecture | single Streamlit script | **FastAPI backend** + Streamlit frontend, talking over SSE |
| Memory | in-process Streamlit state | **SQLite**-backed session history |
| Citations | none | source + page shown per answer |
| Safety | none | emergency-keyword short-circuit + disclaimer system prompt |
| Deployment | manual `streamlit run` | Local-first: **Docker Compose** or venv, zero paid services |
| Quality checks | none | lightweight keyword-based eval set |

## Architecture

```
Browser → Streamlit (:8501) → FastAPI (:8000) → hybrid retrieval (Qdrant + BM25 [+ reranker]) → Ollama (:11434) → streamed, cited answer
```

Ingestion (run once, whenever the source PDFs change):
```
PDFs in data/ → ingest.py → Qdrant (dense vectors) + BM25 (sparse index) in vectorstore/
```

## Repo structure

```
.
├── main.py              FastAPI backend: retrieval + generation + SSE streaming + safety check
├── retrieval.py          Hybrid search (Qdrant + BM25) with optional cross-encoder reranking
├── ingest.py             PDFs → chunks → embeddings → Qdrant + BM25
├── memory.py             SQLite-backed conversation history per session
├── config.py             Central config, everything overridable via env vars / .env
├── app.py                Streamlit frontend (API_URL env var points it at the backend)
├── Dockerfile(.frontend) Container images for the API and the UI
├── docker-compose.yml    Local API + UI containers (Ollama runs natively on the Mac)
├── Makefile              Shortcuts for every command below
├── eval/  tests/         Keyword eval set and smoke tests (CI runs the tests)
└── data/                 Put your PDFs here (not committed)
```

## Run it on macOS

**Prerequisites:** [Homebrew](https://brew.sh), **Python 3.11 or 3.12** (3.13+ fails to build the pinned `pydantic-core`; run `brew install python@3.12`), and optionally Docker Desktop.

### 1. Ollama (the local LLM)

```bash
brew install ollama
ollama pull qwen2.5:3b          # or qwen2.5:1.5b (faster) / llama3.1:8b (best, needs 16GB RAM)
```

Start the server in its own terminal and leave it running. Use `0.0.0.0` only if you run the Docker
option below, otherwise plain `ollama serve` is enough:

```bash
OLLAMA_HOST=0.0.0.0:11434 ollama serve      # or: make ollama
```

If you installed it with `brew services`, run `brew services stop ollama` first, or it will keep
respawning on 127.0.0.1.

### 2a. Option A: Python venv (simplest, fastest)

```bash
make setup                 # venv (Python 3.12), dependencies, .env, model pull
                           # use another interpreter: make setup PYTHON=/opt/homebrew/bin/python3.11
# copy your PDFs into data/
make ingest                # build the vector store
make api                   # terminal 1: http://localhost:8000
make ui                    # terminal 2: http://localhost:8501
```

Without make: `python3.12 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt`,
then `python ingest.py`, `uvicorn main:app --port 8000`, `streamlit run app.py`.

### 2b. Option B: Docker Compose

```bash
# copy your PDFs into data/
make docker-ingest         # one-off: builds the vector store into ./vectorstore
make docker-up             # API + UI at http://localhost:8501
```

The containers reach the native Ollama via `host.docker.internal`. Ollama is deliberately not
containerised: Docker on Mac cannot use the Apple GPU, so a containerised model is several times slower.

### Configuration

Copy `.env.example` to `.env` (venv) or set variables when running compose, for example
`LLM_MODEL=qwen2.5:1.5b make docker-up`. Key knobs: `LLM_MODEL`, `USE_RERANKER` (off by default
for speed), `RETRIEVAL_TOP_K`, `FINAL_TOP_K`.

### Troubleshooting

| Symptom | Fix |
|---|---|
| API container: `Connection refused` to Ollama | Ollama is bound to 127.0.0.1; restart it with `OLLAMA_HOST=0.0.0.0:11434` |
| Slow answers | Use a smaller model (`qwen2.5:1.5b`), keep `USE_RERANKER=false`, lower `FINAL_TOP_K` |
| Empty answers or "no context" | Run ingestion; check there are PDFs in `data/` |
| `sqlite3: unable to open database file` | Fixed by the `./state` directory mount; delete any stray `sessions.db` directory |
| `pydantic-core` fails to build (`PyO3 ... Python 3.14`) | The venv uses a too-new Python. `rm -rf .venv && brew install python@3.12 && make setup` |
| Docker build is huge or slow | Check `.dockerignore` is present (keeps `.venv`, PDFs and vector stores out) |

## Evaluation

```bash
python eval/run_eval.py
```

Runs a small set of test questions (`eval/qa_set.json`) against the running API and checks
whether expected keywords appear in the answers — catches obvious retrieval/prompt regressions
before they reach users.

## Notes on performance and safety

- Speed depends on your Mac and model size; Apple Silicon runs Ollama on the GPU through Metal.
- This is a health-information assistant, not a medical device. `config.py`'s `EMERGENCY_KEYWORDS`
  and the system prompt disclaimer are a starting point, not a complete safety solution.

## Future deployment (free, self-built)

The app has no cloud dependencies, so it can later be self-hosted for free, for example on an
always-on home machine behind a free tunnel or VPN, with the same Compose file. Nothing in the
codebase is tied to a particular host.

## License

MIT — see `LICENSE`.
