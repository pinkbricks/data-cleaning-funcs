# Python data profiling module — version 1 specification

## Purpose

Build a small Python module named `data_profiler` whose functions can be imported into notebooks or scripts to describe a general tabular dataset. The module reports observed properties, without deciding whether the dataset is good or bad.

The deliverable is a module, documentation, an example, and tests. Do not build a web app or command-line interface.

## Scope

Include dataset overview, column summaries, missingness, duplicate rows, numeric summaries, category frequencies, and basic text characteristics.

Exclude data quality scores, cleaning, imputation, automatic type conversion, validation rules, inferred identifiers, time series analysis, outlier flags, correlations, plots, and HTML/PDF reporting. These may be considered separately later.

## Design principles

- Accept pandas DataFrames; users load CSV, Excel, or other files themselves.
- Never modify the input DataFrame, its index, column names, values, or dtypes.
- Return ordinary dictionaries and pandas DataFrames that users can inspect, filter, and export themselves.
- Individual functions work independently. A convenience function combines their results.
- Do not print, display, write files, make network calls, or run profiling at import time.
- Describe observations neutrally. Repeated rows, missingness, and rare categories are not automatically errors.
- Use full data for all calculations; never silently sample.

## Public API

```python
dataset_overview(df: pd.DataFrame) -> dict
column_summary(df: pd.DataFrame) -> pd.DataFrame
missing_summary(df: pd.DataFrame) -> pd.DataFrame
duplicate_summary(df: pd.DataFrame) -> dict
numeric_summary(df: pd.DataFrame) -> pd.DataFrame
category_frequencies(
    df: pd.DataFrame, columns: list | None = None, *, top_n: int = 10
) -> pd.DataFrame
text_summary(df: pd.DataFrame) -> pd.DataFrame
profile_dataset(df: pd.DataFrame, *, top_n: int = 10) -> dict
```

All table outputs use a fresh RangeIndex. Column-level tables contain a `column` field holding the original column label and preserve input column order. Never convert labels to strings just to identify columns.

### Dataset overview

Return `row_count`, `column_count`, `cell_count`, `missing_cell_count`, `missing_cell_pct`, and `memory_bytes`. Memory includes the index and uses deep memory accounting. Missing percentage is on a 0–100 scale; it is undefined (`NaN`) when there are no cells.

### Column summary

One row per column with `column`, `dtype` (string representation of the actual pandas dtype), `non_null_count`, `missing_count`, `missing_pct`, `unique_count`, `unique_pct`, and `is_constant`.

Unique counts exclude missing values. Unique percentage is `100 * unique_count / non_null_count`, or `NaN` when no non-null values exist. A column is constant when it has exactly one distinct non-null value; an entirely missing column is not constant.

### Missing summary

One row per column with `column`, `missing_count`, `missing_pct`, and `non_null_count`. Include columns with zero missing values. Recognise missingness using pandas `isna()`. Empty strings, whitespace-only strings, and literal strings such as `"NA"` are not missing; report text characteristics separately. Missing percentage uses total row count, with `NaN` for zero rows.

### Duplicate summary

Return `duplicate_rows_after_first` (rows that could be removed while retaining the first occurrence), `rows_in_duplicate_groups` (all members of repeated-row groups), and `duplicate_rows_after_first_pct` (denominator: all rows; `NaN` for zero rows).

Compare complete rows, ignore the index, and follow pandas duplicate semantics, including missing values. Do not infer keys. For zero-column DataFrames, return zero counts and an undefined percentage because no fields are available for comparison.

### Numeric summary

Include real-valued integer and floating columns, including nullable pandas numeric dtypes. Exclude boolean, complex, datetime, and timedelta columns. Do not convert numeric-looking strings.

Return `column`, `non_null_count`, `finite_count`, `positive_inf_count`, `negative_inf_count`, `mean`, `std`, `min`, `q25`, `median`, `q75`, `max`, `zero_count`, and `negative_count`.

Calculate descriptive statistics and zero/negative counts using finite values only. Use sample standard deviation (`ddof=1`) and linear quantile interpolation. Undefined statistics are `NaN`; fewer than two finite values yields undefined standard deviation. Infinity counts keep excluded infinite values visible.

### Category frequencies

By default, include object, string, categorical, and boolean columns. With explicit `columns`, profile only the requested existing columns, in the requested order; this allows numeric category codes to be inspected without guessing their meaning.

Return a long table with `column`, `value`, `count`, `pct_of_non_null`, and `rank`. Exclude missing values and unused categorical levels. Preserve original values. Show at most `top_n` values per column, sorted by count descending, with ties broken by first appearance in the data. Percentages use all non-null observations, not only the displayed values; top-N percentages need not total 100. All-null columns contribute no frequency rows and remain visible in the other summaries.

### Text summary

Inspect actual Python string values in object, string, and categorical columns; do not stringify other values. Include eligible columns even when they contain no strings.

Return `column`, `string_count`, `empty_string_count`, `whitespace_only_count`, and `surrounding_whitespace_count`. Empty means `value == ""`; whitespace-only means a nonempty string whose stripped value is empty; surrounding whitespace means `value != value.strip()`. The last two counts can overlap and must not be added together as a total. No normalisation or suggested replacements.

### Combined profile

`profile_dataset` returns exactly these keys: `overview`, `columns`, `missing`, `duplicates`, `numeric`, `categories`, and `text`. Each value matches the corresponding standalone function called with the same arguments. Do not include a copy of the source dataset in the result.

## Input validation and edge cases

- Non-DataFrame input: raise `TypeError` with an actionable message.
- Duplicate column labels: raise `ValueError`, explaining that unambiguous labels are required. Do not rename them.
- MultiIndex columns: explicitly unsupported in v1; raise `ValueError`. MultiIndex rows are allowed.
- Non-string, unique scalar column labels are supported.
- Nested list/dict/set/array cell values are outside the supported scalar tabular input. Reject them with a clear error identifying the column; do not stringify or silently skip them. Share this validation across public functions.
- Invalid `top_n`: raise `ValueError` unless it is a positive integer; booleans do not count as integers.
- Unknown requested columns: raise `ValueError` listing them. An explicit empty column list returns an empty frequency table.
- Zero rows, zero columns, all-null columns, mixed scalar object columns, nullable dtypes, and nonunique row indices must have defined behaviour and must not crash.
- Empty result tables retain their documented columns. Do not promise fixed result dtypes where missing values require nullable or floating representations.
- No row count limits in v1. Document that exact profiling requires time and memory proportional to the supplied data; frequency output is bounded, but counting still uses full columns.

## Suggested project structure

- `data_profiler.py`: public functions and small shared private helpers.
- `tests/test_data_profiler.py`: meaningful correctness and boundary tests.
- `examples/basic_usage.py`: small synthetic dataset and usage.
- `README.md`: installation, function reference, definitions, and limitations.
- `pyproject.toml`: runtime dependency on pandas; pytest as a development dependency. Declare a Python/pandas support range matching the environment actually tested.

Keep the first implementation in one module. Add packages, plugin systems, configuration files, and classes only when a concrete need emerges.

## Example usage

```python
import pandas as pd
from data_profiler import (
    dataset_overview, missing_summary, numeric_summary,
    category_frequencies, profile_dataset,
)

df = pd.read_csv("survey.csv")
overview = dataset_overview(df)
missing = missing_summary(df)
numeric = numeric_summary(df)
regions = category_frequencies(df, columns=["region"], top_n=5)
report = profile_dataset(df)

# Optional display or export remains the caller's responsibility.
print(report["overview"])
report["missing"].to_csv("missing_summary.csv", index=False)
```

## Acceptance criteria

1. Public functions can be imported and used independently without side effects.
2. A hand-calculated synthetic fixture verifies missing percentages, uniqueness, two duplicate metrics, numeric statistics, text counts, frequency denominators, and tie ordering.
3. Edge-case tests cover empty/all-null inputs, nullable numeric/boolean columns, infinities, mixed scalar objects, categorical unused levels, invalid arguments, and unsupported structures.
4. Input equality, including dtypes, labels, and index, is preserved after every function.
5. Combined and standalone outputs agree, including empty results and undefined statistics.
6. Results contain no quality scores, pass/fail ratings, automatic cleaning, or inferred business rules.

## Implementation sequence

Implement shared validation and basic summaries first, then numeric/category/text functions, then the combined function. Complete the example, documentation, and tests before adding further features. This specification authorises the profiling module only; cleaning and report rendering belong to later versions.
