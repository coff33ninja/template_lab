python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e .
python -m {{project_module}}.main
