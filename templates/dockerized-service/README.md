# {{project_name}}

Dockerized FastAPI service scaffold.

## Local run

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt -r requirements-dev.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## Docker run

```powershell
docker compose up --build
```
