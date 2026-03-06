# {{project_name}}

FastAPI service scaffold.

## Run

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .[dev]
uvicorn {{project_module}}.main:app --reload --host 0.0.0.0 --port 8000
```
