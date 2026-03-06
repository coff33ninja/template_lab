from {{project_module}}.worker import run_once


def test_run_once() -> None:
    assert run_once().endswith("::ok")
