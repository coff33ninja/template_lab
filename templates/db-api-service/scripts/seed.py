from pathlib import Path

from {{project_module}}.models.item import Item


def seed_file() -> Path:
    return Path("seed.txt")


def main() -> None:
    _ = Item(name="demo")
    seed_file().write_text("seeded", encoding="utf-8")


if __name__ == "__main__":
    main()
