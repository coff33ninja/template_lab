# {{project_name}}

Project slug: {{project_slug}}

Database-backed FastAPI service scaffold with migrations and seed scripts.

## Run

```powershell
uvicorn {{project_module}}.main:app --reload --host 0.0.0.0 --port 8000
```

## Check

```powershell
pytest -q
```
