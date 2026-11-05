"""Run from the project root after installation: python examples/basic_usage.py."""
import pandas as pd

from data_profiler import category_frequencies, profile_dataset


def main():
    df = pd.DataFrame({
        "region": ["East", "West", "East", None, "East"],
        "amount": pd.Series([0, 12, 12, None, 12], dtype="Float64"),
        "note": ["", " reviewed ", "ok", "\t", "ok"],
    })
    report = profile_dataset(df, top_n=3)
    print(report["overview"])
    print(report["numeric"])
    print(report["text"])
    print(category_frequencies(df, columns=["region"], top_n=2))


if __name__ == "__main__":
    main()
