"""Exact, descriptive profiling of scalar pandas DataFrames without mutation."""

from numbers import Integral

import numpy as np
import pandas as pd
from pandas.api.types import (
    is_bool_dtype, is_float_dtype, is_integer_dtype, is_object_dtype,
    is_scalar, is_string_dtype,
)

__all__ = [
    "dataset_overview", "column_summary", "missing_summary", "duplicate_summary",
    "numeric_summary", "category_frequencies", "text_summary", "profile_dataset",
]

_COLUMN_FIELDS = ["column", "dtype", "non_null_count", "missing_count", "missing_pct",
                  "unique_count", "unique_pct", "is_constant"]
_MISSING_FIELDS = ["column", "missing_count", "missing_pct", "non_null_count"]
_NUMERIC_FIELDS = ["column", "non_null_count", "finite_count", "positive_inf_count",
                   "negative_inf_count", "mean", "std", "min", "q25", "median",
                   "q75", "max", "zero_count", "negative_count"]
_CATEGORY_FIELDS = ["column", "value", "count", "pct_of_non_null", "rank"]
_TEXT_FIELDS = ["column", "string_count", "empty_string_count",
                "whitespace_only_count", "surrounding_whitespace_count"]


def _validate(df):
    if not isinstance(df, pd.DataFrame):
        raise TypeError("Expected a pandas DataFrame; load or construct one before profiling.")
    if isinstance(df.columns, pd.MultiIndex):
        raise ValueError("MultiIndex columns are unsupported in v1; use unique scalar labels.")
    if not df.columns.is_unique:
        raise ValueError("Duplicate column labels are unsupported; unambiguous labels are required.")
    for label, series in df.items():
        if not is_scalar(label):
            raise ValueError(f"Column label {label!r} must be scalar.")
        for value in series:
            if not is_scalar(value):
                raise ValueError(
                    f"Column {label!r} contains unsupported non-scalar cell values "
                    f"({type(value).__name__}); provide scalar tabular values."
                )


def _validate_top_n(top_n):
    if isinstance(top_n, (bool, np.bool_)) or not isinstance(top_n, Integral) or top_n <= 0:
        raise ValueError("top_n must be a positive integer (not a boolean).")


def _pct(count, total):
    return 100 * count / total if total else float("nan")


def _table(rows, fields):
    result = pd.DataFrame(rows, columns=fields)
    # Prevent inference from turning numeric labels or mixed values into floats.
    for field in ("column", "value"):
        if field in fields:
            result[field] = pd.Series([row[field] for row in rows], dtype=object)
    return result


def _text_eligible(dtype):
    return (is_object_dtype(dtype) or is_string_dtype(dtype)
            or isinstance(dtype, pd.CategoricalDtype))


def dataset_overview(df: pd.DataFrame) -> dict:
    """Return dimensions, pandas missingness, and deep memory usage including index."""
    _validate(df)
    rows, columns = df.shape
    missing = int(df.isna().to_numpy().sum())
    return dict(row_count=rows, column_count=columns, cell_count=rows * columns,
                missing_cell_count=missing, missing_cell_pct=_pct(missing, rows * columns),
                memory_bytes=int(df.memory_usage(index=True, deep=True).sum()))


def column_summary(df: pd.DataFrame) -> pd.DataFrame:
    """Describe actual dtypes, missingness, and distinct non-null values per column."""
    _validate(df)
    rows = []
    for label, series in df.items():
        non_null = int(series.notna().sum())
        unique = int(series.nunique(dropna=True))
        missing = len(df) - non_null
        rows.append(dict(column=label, dtype=str(series.dtype), non_null_count=non_null,
                         missing_count=missing, missing_pct=_pct(missing, len(df)),
                         unique_count=unique, unique_pct=_pct(unique, non_null),
                         is_constant=unique == 1))
    return _table(rows, _COLUMN_FIELDS)


def missing_summary(df: pd.DataFrame) -> pd.DataFrame:
    """Report pandas isna() counts for every column, including complete columns."""
    _validate(df)
    rows = []
    for label, series in df.items():
        missing = int(series.isna().sum())
        rows.append(dict(column=label, missing_count=missing,
                         missing_pct=_pct(missing, len(df)), non_null_count=len(df) - missing))
    return _table(rows, _MISSING_FIELDS)


def duplicate_summary(df: pd.DataFrame) -> dict:
    """Count repeated complete rows using pandas semantics, ignoring the index."""
    _validate(df)
    after_first = int(df.duplicated().sum()) if df.shape[1] else 0
    grouped = int(df.duplicated(keep=False).sum()) if df.shape[1] else 0
    return dict(duplicate_rows_after_first=after_first, rows_in_duplicate_groups=grouped,
                duplicate_rows_after_first_pct=_pct(after_first, len(df) if df.shape[1] else 0))


def numeric_summary(df: pd.DataFrame) -> pd.DataFrame:
    """Summarize finite real numeric values; count infinities separately (sample std)."""
    _validate(df)
    rows = []
    for label, series in df.items():
        dtype = series.dtype
        if is_bool_dtype(dtype) or not (is_integer_dtype(dtype) or is_float_dtype(dtype)):
            continue
        observed = series.dropna()
        finite = observed[np.isfinite(observed)]
        stats = {key: float("nan") for key in ("mean", "std", "min", "q25", "median", "q75", "max")}
        if len(finite):
            quantiles = finite.quantile([.25, .5, .75], interpolation="linear")
            stats.update(mean=finite.mean(), min=finite.min(), max=finite.max(),
                         q25=quantiles.iloc[0], median=quantiles.iloc[1], q75=quantiles.iloc[2])
            if len(finite) > 1:
                stats["std"] = finite.std(ddof=1)
        rows.append(dict(column=label, non_null_count=len(observed), finite_count=len(finite),
                         positive_inf_count=int((observed == np.inf).sum()),
                         negative_inf_count=int((observed == -np.inf).sum()),
                         **stats, zero_count=int((finite == 0).sum()),
                         negative_count=int((finite < 0).sum())))
    return _table(rows, _NUMERIC_FIELDS)


def category_frequencies(
    df: pd.DataFrame, columns: list | None = None, *, top_n: int = 10
) -> pd.DataFrame:
    """Count non-null categories, ranking ties by first appearance in full data."""
    _validate(df)
    _validate_top_n(top_n)
    if columns is None:
        selected = [i for i, dtype in enumerate(df.dtypes)
                    if _text_eligible(dtype) or is_bool_dtype(dtype)]
    else:
        if not isinstance(columns, list):
            raise TypeError("columns must be a list of existing column labels or None.")
        selected, unknown = [], []
        for label in columns:
            try:
                selected.append(df.columns.get_loc(label))
            except (KeyError, TypeError, pd.errors.InvalidIndexError):
                unknown.append(label)
        if unknown:
            raise ValueError(f"Unknown requested columns: {unknown!r}")
    rows = []
    for position in selected:
        label = df.columns[position]
        observed = df.iloc[:, position].dropna()
        # Factorization assigns codes in encounter order, independent of categorical levels.
        codes, _ = pd.factorize(observed, sort=False)
        counts = np.bincount(codes)
        first = {}
        for code, value in zip(codes, observed):
            first.setdefault(code, value)
        ranked = sorted(range(len(counts)), key=lambda code: (-int(counts[code]), code))
        for rank, code in enumerate(ranked[:top_n], start=1):
            count = int(counts[code])
            rows.append(dict(column=label, value=first[code], count=count,
                             pct_of_non_null=_pct(count, len(observed)), rank=rank))
    return _table(rows, _CATEGORY_FIELDS)


def text_summary(df: pd.DataFrame) -> pd.DataFrame:
    """Count actual strings and whitespace characteristics without normalization."""
    _validate(df)
    rows = []
    for label, series in df.items():
        if not _text_eligible(series.dtype):
            continue
        strings = [value for value in series if isinstance(value, str)]
        rows.append(dict(column=label, string_count=len(strings),
                         empty_string_count=sum(value == "" for value in strings),
                         whitespace_only_count=sum(bool(value) and not value.strip() for value in strings),
                         surrounding_whitespace_count=sum(value != value.strip() for value in strings)))
    return _table(rows, _TEXT_FIELDS)


def profile_dataset(df: pd.DataFrame, *, top_n: int = 10) -> dict:
    """Combine all seven standalone summaries without including the source data."""
    _validate(df)
    _validate_top_n(top_n)
    return dict(overview=dataset_overview(df), columns=column_summary(df),
                missing=missing_summary(df), duplicates=duplicate_summary(df),
                numeric=numeric_summary(df), categories=category_frequencies(df, top_n=top_n),
                text=text_summary(df))
