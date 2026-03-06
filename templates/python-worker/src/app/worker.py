from .jobs.tasks import run_job


def run_once() -> str:
    return run_job("health-check")


def main() -> None:
    print(run_once())


if __name__ == "__main__":
    main()
