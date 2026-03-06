from {{project_module}}.main import run


def test_run() -> None:
    assert "Hello from" in run()
