from {{project_module}} import create_greeting


def test_create_greeting() -> None:
    assert "{{project_slug}}" in create_greeting("dev")
