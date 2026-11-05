# Data profilers

This repository contains two independent modules:

- [R time series profiler](#r-time-series-profiler): describe one numeric series and its time index.
- [Python data profiler](#python-data-profiler): describe a general pandas DataFrame.

Both modules return results you can inspect in a notebook or script. They leave
your input unchanged. You choose what to display or save.

## R time series profiler

Use the R profiler to check one numeric series: when observations occur, which
times or values are missing, and how values vary. It accepts a data.frame or
tibble. Select one series before calling it; the profiler does not combine groups.

### Create your first profile

Run this example from the repository folder. Core profiling needs only base R
and `stats`.

```r
source("time_series_profiler.R")

visits <- data.frame(
  date = as.Date(c("2024-01-01", "2024-01-02", "2024-01-04")),
  visits = c(12, NA, 18)
)

report <- profile_time_series(
  visits, time_col = "date", value_col = "visits",
  expected_frequency = "daily"
)

report$gaps$missing_times
report$values
```

This example has two different kinds of missing data. January 3 has no row, so
it appears in `missing_times`. January 2 has a row but no value, so it contributes
to the value summary's `missing_count`.

### Find the result you need

The report contains six named elements. You can also call each summary function
on its own.

| Report element | What to look for | Standalone function |
| --- | --- | --- |
| `overview` | Row counts, observed dates, and missing-value counts | `series_overview()` |
| `time_index` | Repeated timestamps, original ordering, and time intervals | `check_time_index()` |
| `gaps` | Expected times with no observation, plus rows outside the schedule | `find_time_gaps()` |
| `values` | Numeric statistics and counts of missing or infinite values | `summarise_values()` |
| `calendar` | Summaries by month and weekday, or other groups you request | `summarise_calendar()` |
| `settings` | The column names, frequency, time zone, and boundaries used | Included in the combined profile |

Tables use ordinary data.frames. You choose what to inspect, filter, or export.
See the [function reference](docs/r_time_series_reference.md) for arguments,
output fields, and calculation rules.

### Prepare your columns and schedule

Pass column names as strings, as the example does. Use a numeric value column
and a `Date` or `POSIXct` time column. Parse strings before profiling. For hourly
data, use `POSIXct` with an explicit time zone:

```r
time <- as.POSIXct("2024-01-01 09:00:00", tz = "Africa/Nairobi")
```

Choose `hourly` for `POSIXct`. For `Date`, choose `daily`, `weekly`, `monthly`,
`quarterly`, or `yearly`. Monthly through yearly schedules use first-of-month
anchors. The [time and grid rules](docs/r_time_series_reference.md#time-grids)
explain boundaries, time zones, and daylight-saving changes.

The profiler does not guess a frequency. If you omit `expected_frequency`, it
still returns the other summaries, but marks gap checking as `unavailable`.
By default, it checks only the range between your first and last valid timestamps.
Supply `grid_start` and `grid_end` when you need to check coverage beyond that range.

### Add a plot or diagnostic

The core profile does not run statistical tests. Install the optional packages
for the extra functions you want:

```r
install.packages("ggplot2") # Plots, including dependence and decomposition
install.packages("urca")    # ADF and KPSS stationarity tests
```

To view the example series:

```r
plot <- plot_series(visits, "date", "visits", expected_frequency = "daily")
print(plot)
```

The plot shows finite observations and breaks lines at missing slots or values.
Its caption explains which rows it omits.

| Function | What it helps you inspect |
| --- | --- |
| `plot_dependence()` | How values relate to earlier observations, through ACF and PACF |
| `test_stationarity()` | Evidence from ADF and KPSS tests, using lag settings you supply |
| `decompose_series()` | Trend, one seasonal cycle, and the remainder through STL |

These diagnostics need a complete, regular series with unique timestamps and
finite values. They return `status = "skipped"` and a reason when the data or
optional packages do not meet their requirements. They do not fill gaps or drop
rows to make a calculation run. Read the
[diagnostic reference](docs/r_time_series_reference.md#diagnostics) before choosing
test settings or interpreting results.

### Run the example and tests

For a longer example with core summaries and diagnostics:

```sh
Rscript examples/profile_time_series_usage.R
```

Install `testthat` with `install.packages("testthat")`, then run the single test
file from the repository folder:

```sh
Rscript tests/test_time_series_profiler.R
```

Tests for optional functions skip when their packages are missing. We tested with
R and `stats` 4.6.2, ggplot2 4.0.3, urca 1.3-4, and testthat 3.3.2. We have not
verified other versions.

The profiler describes data; it does not clean values, score quality, forecast,
or choose models. It uses all supplied rows, so larger datasets and time grids
need more time and memory. Sourcing the module only defines functions: it does
not attach packages, change global settings, install dependencies, or produce output.

---

## Python data profiler

`data_profiler` helps you get to know a dataset before you work with it. It shows
what each column contains, how much data is missing, which rows repeat, and how
often each value appears.

Use it with a pandas DataFrame in a notebook or Python script. It returns
dictionaries and DataFrames that you can inspect, filter, or export. Your original
data stays unchanged, including its column names, index, and data types.

### Getting started

From the project folder, install the module:

```sh
python -m pip install .
```

We tested the module with Python 3.10, pandas 2.3.3, and NumPy 2.2.6. The
package currently requires Python 3.10, pandas 2.3.3 or later in the 2.3 series,
and NumPy 2.2.6 or later in the 2.2 series. We have not tested other versions.

Load your data with pandas, then pass the DataFrame to a profiling function.
Here's a small example you can run as it is:

```python
import pandas as pd
from data_profiler import profile_dataset, category_frequencies

df = pd.DataFrame({
    "region": ["East", "West", "East", None],
    "amount": [0, 12, 12, None],
})

report = profile_dataset(df, top_n=10)
print(report["overview"])
print(report["missing"])

# You can also look at one column on its own.
regions = category_frequencies(df, columns=["region"], top_n=5)
print(regions)
```

The functions do not print results or save files themselves. You choose what to
show or export. For example:

```python
report["missing"].to_csv("missing_summary.csv", index=False)
```

For another example, run `python examples/basic_usage.py` after installation.

### Choosing a function

Each function works on its own, so you can ask for just the information you need.
Use `profile_dataset` to get all seven summaries at once.

| Function | What it tells you |
| --- | --- |
| `dataset_overview(df)` | The dataset's size, missing cell count, and estimated memory use. |
| `column_summary(df)` | Each column's data type, missing values, and number of distinct values. |
| `missing_summary(df)` | How many values are missing in each column. |
| `duplicate_summary(df)` | How many complete rows repeat. |
| `numeric_summary(df)` | Statistics for integer and floating-point columns. |
| `category_frequencies(df, columns=None, *, top_n=10)` | The most common values in each selected column. |
| `text_summary(df)` | Counts of strings, empty strings, and strings with whitespace. |
| `profile_dataset(df, *, top_n=10)` | A dictionary containing all seven summaries. |

Each table uses a new row index that starts at zero (a pandas `RangeIndex`).
Column summaries follow the order of your input columns and keep the original
labels. If you request specific columns for category frequencies, the result
follows the order you requested. Category values also keep their original values.

### Understanding the results

#### Dataset overview

`dataset_overview` returns a dictionary with `row_count`, `column_count`,
`cell_count`, `missing_cell_count`, `missing_cell_pct`, and `memory_bytes`.

A cell is one row-and-column position. To calculate the missing percentage, the
function divides the missing cell count by the total cell count and multiplies
the result by 100.

Memory use comes from pandas' deep memory estimate and includes the index. It is
an estimate of the DataFrame's size, rather than the memory your whole Python
process uses.

#### Column and missing-value summaries

`column_summary` returns these fields:

- `column`: the original column label.
- `dtype`: a string that names the column's pandas data type.
- `non_null_count` and `missing_count`: counts of present and missing values.
- `missing_pct`: the percentage of rows with a missing value in this column.
- `unique_count`: the number of distinct values, excluding missing values.
- `unique_pct`: the percentage you get when you divide the distinct count by the non-missing count and multiply by 100.
- `is_constant`: whether the column has exactly one distinct non-missing value.

For example, a column containing `["a", "a", "b", None]` has two distinct values
and three non-missing values. Its `unique_pct` is about 66.7%. The function does not mark a column as constant
when it contains only missing values.

`missing_summary` returns `column`, `missing_count`, `missing_pct`, and
`non_null_count`. It includes every column, even those with no missing values.

Both functions use pandas `isna()` to recognise missing values. Empty strings,
spaces, and the literal string `"NA"` count as present values. All percentages
use a scale from 0 to 100.

#### Repeated rows

`duplicate_summary` compares complete rows using pandas' duplicate rules,
including its handling of missing values. The function ignores row index labels.

It returns three fields:

- `duplicate_rows_after_first`: the number of repeated rows beyond the first occurrence.
- `rows_in_duplicate_groups`: the number of rows that belong to a repeated group, including the first occurrence.
- `duplicate_rows_after_first_pct`: the first count as a percentage of all rows.

For example, if the same row appears three times, it adds 2 to the first count
and 3 to the second. The function reports repeated rows as observations. You
decide whether they belong in your data based on your use case.

#### Numeric statistics

`numeric_summary` includes integer and floating-point columns, including pandas
nullable types such as `Int64` and `Float64`. It excludes booleans, complex
numbers, dates, durations, and strings such as `"123"`.

The result includes `column`, `non_null_count`, `finite_count`,
`positive_inf_count`, and `negative_inf_count`. These show how many values are
present and how many are finite or infinite.

The remaining fields use only finite values:

- `mean`, `std`, `min`, and `max`.
- `q25`, `median`, and `q75`: the 25th, 50th, and 75th percentiles.
- `zero_count` and `negative_count`.

Standard deviation uses the sample formula (`ddof=1`). Percentiles use linear
interpolation. The function counts infinite values separately and includes them
in `non_null_count`, but excludes them from these statistics.

#### Category frequencies

By default, `category_frequencies` looks at object, string, categorical, and
boolean columns. You can pass a list of column labels to choose your own,
including numeric columns that you use as category codes. Passing `columns=[]` returns
an empty table.

The output fields are `column`, `value`, `count`, `pct_of_non_null`, and `rank`.
Each column shows up to `top_n` values, with the most common first. When counts
match, the value that appeared first in the data comes first. Ranks start at
1 for each column.

The function leaves out missing values and unused categorical levels. It uses
all non-missing values to calculate percentages, even when it shows only a few
values. For
example, a value that appears 20 times among 100 non-missing values gets 20%,
regardless of `top_n`. The displayed percentages may therefore total less than
100%. Columns with no non-missing values have no frequency rows.

#### Text characteristics

`text_summary` examines Python strings in object, string, and categorical
columns. It leaves other values as they are and includes eligible columns even
when they contain no strings.

The output contains `column` and four counts:

- `string_count`: all string values.
- `empty_string_count`: strings equal to `""`.
- `whitespace_only_count`: nonempty strings containing only whitespace, such as `"   "` or `"\t"`.
- `surrounding_whitespace_count`: strings that change when `.strip()` removes whitespace from their ends, such as `" hello "`.

A string containing only spaces counts in both of the last two fields. Do not
add those counts together to get a total. The function reports whitespace
without removing it.

#### The combined profile

`profile_dataset` returns a dictionary with exactly these keys: `overview`,
`columns`, `missing`, `duplicates`, `numeric`, `categories`, and `text`.
Each value matches the corresponding standalone function. The `top_n` argument
controls the category frequency results. The dictionary does not include a copy
of your source data.

### Empty data and input requirements

The profiler supports empty DataFrames and columns containing only missing
values. It returns `NaN` when it cannot calculate a statistic or percentage.
For example, a percentage has no value when its denominator is zero, and sample
standard deviation needs at least two finite values.

For a DataFrame with no columns, both duplicate counts are zero and the duplicate
percentage is `NaN`. Empty result tables still have their documented fields.
Result data types can vary when missing or undefined values are present.

Every function checks its input:

- Pass a pandas DataFrame. Other input types raise `TypeError`.
- Use unique, scalar column labels. Numbers are fine; duplicate labels and MultiIndex columns raise `ValueError`.
- Cells must hold individual values. Every function rejects lists, dictionaries, sets, arrays, and tuples. The error names the column containing them.
- For category frequencies, `columns` must be a list or `None`. If you request unknown column labels, the function raises `ValueError` and lists them in the message.
- `top_n` must be a positive integer. Zero, negative numbers, and booleans raise `ValueError`.

The profiler supports MultiIndex rows and repeated row index labels. Object
columns can contain a mix of scalar values, such as strings and numbers.

### Scope and performance

The profiler reads all supplied data. It does not sample or impose a row limit.
Larger datasets need more time and working memory. Setting a small `top_n` limits
the frequency table's size, but counting still reads every value in each column.
Sorting categories can take O(k log k) time, where k is the number of distinct
values.

The combined profile repeats validation for each summary. If you only need one
summary, calling that function directly can be faster.

The module describes what is present in your data. It does not assign quality
scores, clean or fill values, convert types, infer identifiers, or apply business
validation rules. Time series analysis, outlier flags, correlations, plots, and
HTML/PDF reports are outside its scope. It has no CLI or web interface, makes no
network calls, and does not run profiling when you import it.

### Running the tests

Install the development dependencies, then run pytest from the project folder:

```sh
python -m pip install -e '.[dev]'
python -m pytest
```
