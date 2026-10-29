.PHONY: setup ollama ingest api ui docker-up docker-ingest test eval

setup:            ## venv + deps + model
	python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt
	[ -f .env ] || cp .env.example .env
	ollama pull $${LLM_MODEL:-qwen2.5:3b}

ollama:           ## run Ollama (bound to 0.0.0.0 so Docker containers can reach it)
	OLLAMA_HOST=0.0.0.0:11434 ollama serve

ingest:           ## PDFs in data/ -> vector store
	. .venv/bin/activate && python ingest.py

api:
	. .venv/bin/activate && uvicorn main:app --port 8000

ui:
	. .venv/bin/activate && streamlit run app.py

docker-up:
	mkdir -p state data vectorstore && docker compose up --build

docker-ingest:
	mkdir -p state data vectorstore && docker compose run --rm api python ingest.py

test:
	. .venv/bin/activate && pytest tests/ -v

eval:
	. .venv/bin/activate && python eval/run_eval.py
