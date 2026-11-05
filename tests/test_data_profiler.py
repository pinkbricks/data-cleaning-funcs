import math
import subprocess
import sys

import numpy as np
import pandas as pd
import pytest
from pandas.testing import assert_frame_equal

import data_profiler as dp

FUNCTIONS = [getattr(dp, name) for name in dp.__all__]


@pytest.fixture
def sample():
    return pd.DataFrame({
        "n": [0., -2., 4., 4., np.nan, 0.],
        "s": ["", " a ", "b", "b", None, ""],
        "c": ["z", "a", "b", "b", "a", "z"],
    }, index=[7, 7, 2, 3, 4, 8])


def test_hand_calculated(sample):
    overview = dp.dataset_overview(sample)
    assert overview == dict(row_count=6, column_count=3, cell_count=18,
                            missing_cell_count=2, missing_cell_pct=100 * 2 / 18,
                            memory_bytes=int(sample.memory_usage(index=True, deep=True).sum()))
    columns = dp.column_summary(sample).set_index("column")
    assert columns.loc["n", "unique_count"] == 3
    assert columns.loc["n", "unique_pct"] == 60
    assert columns.loc["n", "non_null_count"] == 5
    assert columns.loc["n", "dtype"] == "float64"
    assert not columns.loc["n", "is_constant"]
    missing = dp.missing_summary(sample)
    assert missing.missing_count.tolist() == [1, 1, 0]
    assert missing.missing_pct.tolist() == [100 / 6, 100 / 6, 0]
    assert dp.duplicate_summary(sample) == dict(duplicate_rows_after_first=2,
        rows_in_duplicate_groups=4, duplicate_rows_after_first_pct=100 * 2 / 6)
    numeric = dp.numeric_summary(sample).iloc[0]
    assert numeric["mean"] == 1.2
    assert numeric["std"] == pytest.approx(math.sqrt(7.2))
    assert numeric[["min", "q25", "median", "q75", "max"]].tolist() == [-2, 0, 0, 4, 4]
    assert numeric.zero_count == 2
    assert numeric.negative_count == 1
    frequencies = dp.category_frequencies(sample, ["c"], top_n=2)
    assert frequencies.value.tolist() == ["z", "a"]
    assert frequencies["count"].tolist() == [2, 2]
    assert frequencies.pct_of_non_null.tolist() == [100 / 3, 100 / 3]
    assert frequencies["rank"].tolist() == [1, 2]
    text = dp.text_summary(sample).iloc[0]
    assert text.tolist() == ["s", 5, 2, 0, 1]


@pytest.mark.parametrize("function", FUNCTIONS)
def test_no_mutation(function, sample):
    sample.columns = pd.Index([1, "text", 2.5], dtype=object)
    sample.index = pd.MultiIndex.from_arrays([[1] * 6, [0, 0, 1, 2, 3, 4]])
    before = sample.copy(deep=True)
    function(sample)
    assert_frame_equal(sample, before)


@pytest.mark.parametrize("frame", [pd.DataFrame(), pd.DataFrame(index=[1, 1]),
    pd.DataFrame({"a": pd.Series(dtype="Float64"), "s": pd.Series(dtype="string")}),
    pd.DataFrame({"a": [None, None], "b": pd.Series([pd.NA, pd.NA], dtype="Int64")})])
def test_empty_and_all_null(frame):
    report = dp.profile_dataset(frame)
    for key, name in zip(["overview", "columns", "missing", "duplicates", "numeric", "categories", "text"], dp.__all__):
        expected = getattr(dp, name)(frame)
        actual = report[key]
        if isinstance(expected, pd.DataFrame):
            assert_frame_equal(actual, expected)
            assert isinstance(actual.index, pd.RangeIndex)
            assert len(actual.columns) > 0
        else:
            assert actual.keys() == expected.keys()
            for field, value in expected.items():
                assert (math.isnan(actual[field]) if isinstance(value, float) and math.isnan(value)
                        else actual[field] == value)
    assert set(report) == {"overview", "columns", "missing", "duplicates", "numeric", "categories", "text"}
    if not frame.size:
        assert math.isnan(report["overview"]["missing_cell_pct"])
    if not len(frame.columns):
        assert report["duplicates"]["duplicate_rows_after_first"] == 0
        assert math.isnan(report["duplicates"]["duplicate_rows_after_first_pct"])
    if len(frame) == 0:
        assert report["missing"].missing_pct.isna().all()
    assert not report["columns"].is_constant.any()
    assert report["columns"].unique_pct.isna().all()


def test_numeric_boundaries():
    df = pd.DataFrame({"int": pd.Series([0, -2, None, 4], dtype="Int64"),
        "float": pd.Series([np.inf, -np.inf, 3, None], dtype="Float64"),
        "null": pd.Series([None] * 4, dtype="Float64"),
        "bool": pd.Series([True, False, None, True], dtype="boolean"),
        "complex": [1j] * 4, "date": pd.date_range("2020-01-01", periods=4),
        "delta": pd.to_timedelta([1, 2, 3, 4], unit="D"), "strings": ["1"] * 4})
    result = dp.numeric_summary(df).set_index("column")
    assert result.index.tolist() == ["int", "float", "null"]
    assert result.loc["float", ["non_null_count", "finite_count", "positive_inf_count", "negative_inf_count"]].tolist() == [3, 1, 1, 1]
    assert result.loc["float", "mean"] == 3
    assert result.loc["float", "negative_count"] == 0
    assert math.isnan(result.loc["float", "std"])
    assert result.loc["null", ["mean", "std", "min", "q25", "median", "q75", "max"]].isna().all()
    assert dp.category_frequencies(df, ["bool"]).value.tolist() == [True, False]


def test_mixed_categories_and_text():
    df = pd.DataFrame({"mixed": [3, " ", "", "NA", " x", None],
        "cat": pd.Categorical(["b", "a", "a", "b", None, None], categories=["a", "b", "unused"], ordered=True),
        "no_strings": pd.Series([1, 2, None, 1, 2, None], dtype=object),
        "string": pd.Series(["", "\t", "x", None, "x", "x"], dtype="string")})
    result = dp.category_frequencies(df)
    assert result[result.column == "cat"].value.tolist() == ["b", "a"]
    assert result[result.column == "mixed"].value.tolist() == [3, " ", "", "NA", " x"]
    text = dp.text_summary(df).set_index("column")
    assert text.loc["mixed"].tolist() == [4, 1, 1, 2]
    assert text.loc["no_strings"].tolist() == [0, 0, 0, 0]
    assert text.loc["string"].tolist() == [5, 1, 1, 1]
    assert dp.missing_summary(df).missing_count.tolist() == [1, 2, 2, 1]


def test_labels_order_and_explicit_numeric():
    df = pd.DataFrame([[1, 2], [1, 3]], columns=pd.Index([7, 2.5], dtype=object))
    for function in [dp.column_summary, dp.missing_summary, dp.numeric_summary]:
        result = function(df)
        assert result.column.tolist() == [7, 2.5]
        assert isinstance(result.column.iloc[0], int)
    assert dp.category_frequencies(df).empty
    assert dp.category_frequencies(df, []).columns.tolist() == ["column", "value", "count", "pct_of_non_null", "rank"]
    assert dp.category_frequencies(df, [2.5, 7]).column.tolist() == [2.5, 2.5, 7]


@pytest.mark.parametrize("function", FUNCTIONS)
def test_shared_validation(function):
    with pytest.raises(TypeError, match="DataFrame"):
        function([[1]])
    with pytest.raises(ValueError, match="unambiguous"):
        function(pd.DataFrame([[1, 2]], columns=["a", "a"]))
    with pytest.raises(ValueError, match="MultiIndex"):
        function(pd.DataFrame([[1]], columns=pd.MultiIndex.from_tuples([("a", "b")])))
    for value in [[1], {"a": 1}, {1}, np.array([1])]:
        with pytest.raises(ValueError, match="'nested'.*non-scalar"):
            function(pd.DataFrame({"nested": [value]}))


@pytest.mark.parametrize("top_n", [0, -1, True, np.bool_(True), 1.5, "2", None])
@pytest.mark.parametrize("function", [dp.category_frequencies, dp.profile_dataset])
def test_invalid_top_n(function, top_n):
    with pytest.raises(ValueError, match="positive integer"):
        function(pd.DataFrame(), top_n=top_n)


def test_unknown_columns_and_constant():
    df = pd.DataFrame({"x": [1, 1, None], "empty": [None] * 3})
    with pytest.raises(ValueError, match="missing.*other"):
        dp.category_frequencies(df, ["missing", "other"])
    with pytest.raises(TypeError, match="list"):
        dp.category_frequencies(df, "x")
    assert dp.column_summary(df).is_constant.tolist() == [True, False]
    assert dp.category_frequencies(df, ["x"], top_n=np.int64(1))["count"].tolist() == [2]


def test_duplicate_missing_values():
    df = pd.DataFrame({"x": [1, 1, None, None], "s": [None, None, "a", "a"]}, index=[0] * 4)
    assert dp.duplicate_summary(df) == dict(duplicate_rows_after_first=2,
        rows_in_duplicate_groups=4, duplicate_rows_after_first_pct=50.)


def test_combined_matches_nonempty(sample):
    report = dp.profile_dataset(sample, top_n=1)
    for key, function in [("columns", dp.column_summary), ("missing", dp.missing_summary),
                          ("numeric", dp.numeric_summary), ("text", dp.text_summary)]:
        assert_frame_equal(report[key], function(sample))
    assert_frame_equal(report["categories"], dp.category_frequencies(sample, top_n=1))
    assert report["overview"] == dp.dataset_overview(sample)
    assert report["duplicates"] == dp.duplicate_summary(sample)


def test_import_is_silent():
    result = subprocess.run([sys.executable, "-c", "import data_profiler"], capture_output=True, text=True)
    assert result.returncode == 0
    assert result.stdout == result.stderr == ""
