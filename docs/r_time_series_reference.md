# R time series function reference

Start with the [README example](../README.md#r-time-series-profiler) if you want
to run a profile. Use this reference to check arguments, output fields, and
calculation rules.

## Shared input rules

Every function accepts a data.frame or tibble. Supply `time_col` and `value_col`
as single strings. Use different columns for time and values. Give every column
a unique, nonmissing, nonempty name. The functions ignore extra columns and leave
the input unchanged.

| Column | Accepted values | Values the profiler rejects |
| --- | --- | --- |
| Time | `Date` or `POSIXct`, including missing times | Strings, factors, numeric epochs, `POSIXlt`, custom date classes, matrices, and infinite times |
| Value | Plain integer or double values | Logicals, factors, strings, complex numbers, dates, matrices, and lists |

The profiler treats numeric `NA` and `NaN` as missing. It counts positive and
negative infinity separately. A finite value is a number other than a missing
value or infinity. Numeric statistics use finite values only.

Invalid inputs or configuration raise errors. The functions never parse strings
or convert columns for you.

### Time zones

For `POSIXct`, use a valid, nonempty time zone in the column's `tzone` attribute
or supply `tz`. An override changes calendar grouping and labels while preserving
the actual instants. The profiler never uses the computer's local zone as a fallback.

`series_overview()` and `check_time_index()` have no `tz` argument, so their
standalone calls require the column to carry a valid zone. `profile_time_series()`
passes its effective zone to these summaries through a local copy.

Keep `tz = NULL` for `Date`; a Date column has no intraday time zone.

### Empty results

Empty tables keep their fields and timestamp classes. Counts start at zero.
Undefined statistics and percentages return `NA_real_`; missing start and end
times keep the input time class. Sample standard deviation needs at least two
finite values.

## Time grids

A grid lists the times you expect to observe. The caller supplies
`expected_frequency`; the profiler never infers it.

| Frequency | Required class | Step from the starting point |
| --- | --- | --- |
| `hourly` | `POSIXct` | 3,600 elapsed seconds |
| `daily` | `Date` | One calendar day |
| `weekly` | `Date` | Seven calendar days |
| `monthly` | `Date` | One month, on the first day |
| `quarterly` | `Date` | Three months, on the first day |
| `yearly` | `Date` | Twelve months, on the first day |

Hourly grids follow elapsed time across daylight-saving changes. Two different
instants may share a local clock label when clocks move back. Convert intraday
data to `Date` deliberately before using daily through yearly frequencies.

Daily grids include weekends and holidays. This version does not support
business-day, trading-day, holiday, or custom schedules.

### Starting points and boundaries

The starting point, or *anchor*, determines the schedule. By default, the grid
runs from the earliest to the latest nonmissing timestamp. Use `grid_start` or
`grid_end` to override either boundary.

- A supplied `grid_start` becomes the anchor.
- Both boundaries must share the time column's class. The start cannot follow the end.
- An explicit end must align exactly with the anchor and frequency. A default end
  may fall between slots; the grid stops at the last slot within that boundary.
- Monthly, quarterly, and yearly anchors and explicit boundaries must use the
  first day of a month. They can start in any month. A quarterly anchor on February 1
  gives February, May, August, and November.

Without explicit boundaries, the profiler cannot detect unrecorded periods before
the first observation or after the last. With no valid times, it needs both
boundaries to build a grid. One timestamp defines one slot by default.

The profiler matches timestamps exactly. It does not round times or use month-end
arithmetic. It refuses grids above `max_grid_size` rather than truncating or
sampling them. The default limit is 1,000,000 slots; you can raise it explicitly.

## Core functions

### `profile_time_series()`

Combine the core summaries without running statistical diagnostics.

```r
profile_time_series(
  data, time_col, value_col, expected_frequency = NULL,
  grid_start = NULL, grid_end = NULL, tz = NULL,
  calendar_groups = c("month", "weekday"), max_grid_size = 1000000L
)
```

The result contains exactly `overview`, `time_index`, `gaps`, `values`, `calendar`,
and `settings`. Each summary matches its standalone function. The report does
not include a copy of the source data.

With `expected_frequency = NULL`, `gaps$status` is `"unavailable"` and
`gaps$reason` is `"expected_frequency_not_supplied"`. Other summaries still run.

`settings` records `time_col`, `value_col`, `expected_frequency`, `time_zone`,
`calendar_groups`, effective `grid_start` and `grid_end`, and `max_grid_size`.
The grid-size limit must be a positive integer.

### `series_overview()`

Describe the size, observed time range, and value coverage of the series.

```r
series_overview(data, time_col, value_col)
```

The function returns a named list:

| Fields | Meaning |
| --- | --- |
| `row_count` | Total supplied rows |
| `valid_time_count`, `missing_time_count` | Counts of present and missing times |
| `start`, `end` | Earliest and latest nonmissing times, in the original time class |
| `time_class`, `time_zone` | Time type and zone; the zone is `NULL` for Date |
| `value_non_missing_count`, `value_missing_count` | Counts across all rows, including rows with missing times |
| `value_missing_pct` | `100 * value_missing_count / row_count` |
| `finite_value_count`, `positive_inf_count`, `negative_inf_count` | Counts of finite values and each kind of infinity |

### `check_time_index()`

Check original ordering, repeated timestamps, and spacing between observations.

```r
check_time_index(data, time_col)
```

The result contains `summary`, `duplicate_times`, and `intervals`.

| Summary field | Meaning |
| --- | --- |
| `missing_time_count` | Rows with missing times |
| `unique_time_count` | Distinct nonmissing times |
| `duplicate_rows_after_first` | Repeated timestamp rows beyond the first occurrence |
| `rows_in_duplicate_time_groups` | All rows sharing a repeated timestamp, including the first occurrence |
| `is_nondecreasing` | Whether nonmissing times stay the same or increase in original row order |
| `is_strictly_increasing` | Whether each nonmissing time follows the previous one |

For a timestamp that appears three times, the duplicate metrics count 2 and 3
respectively. They exclude missing times and compare actual instants for POSIXct.
Both ordering fields return `NA` with fewer than two valid times.

`duplicate_times` contains `timestamp` and `count`, in chronological order.
`intervals` contains `interval`, `unit`, and `count`. It measures consecutive
sorted unique times in `"seconds"` for POSIXct or `"days"` for Date. Different
month lengths can produce different intervals without any missing monthly slots.
Sorting for these tables does not change the input or the ordering checks.

### `find_time_gaps()`

Compare observations with the [expected time grid](#time-grids).

```r
find_time_gaps(
  data, time_col, expected_frequency, grid_start = NULL,
  grid_end = NULL, tz = NULL, max_grid_size = 1000000L
)
```

The result contains `status`, `reason`, `summary`, `missing_times`, and
`off_grid_rows`. Status `"ok"` means the calculation completed, even if it found
gaps. Status `"unavailable"` means it lacks enough time information.

| Summary fields | Meaning |
| --- | --- |
| `expected_frequency`, `grid_start`, `grid_end` | Frequency and effective boundaries |
| `expected_slot_count` | Number of grid times |
| `observed_slot_count` | Grid times with at least one observation |
| `missing_slot_count` | Grid times with no observation |
| `missing_slot_pct` | `100 * missing_slot_count / expected_slot_count` |
| `off_grid_row_count` | Rows within the boundaries whose timestamps do not match a grid slot |
| `outside_range_row_count` | Rows beyond the boundaries |

Repeated timestamps occupy one slot. A timestamp with a missing value still
occupies its slot. An unavailable grid has zero counts and an undefined
missing-slot percentage.

`missing_times` has one `timestamp` column in chronological order.
`off_grid_rows` contains `row_number`, `timestamp`, and `reason`. Row numbers
start at 1 and refer to original positions, not row names. Reasons are `"off_grid"`
or `"outside_range"`; outside-range takes precedence. Missing times appear in the
time-index summary instead of this table.

### `summarise_values()`

Calculate statistics from finite values and count missing or infinite values.

```r
summarise_values(data, value_col)
```

The function returns one row:

| Fields | Meaning |
| --- | --- |
| `row_count`, `missing_count`, `finite_count` | Total, missing, and finite value counts |
| `positive_inf_count`, `negative_inf_count` | Infinity counts |
| `mean`, `sd`, `min`, `max` | Mean, sample standard deviation, minimum, and maximum |
| `q25`, `median`, `q75` | 25th, 50th, and 75th percentiles using R quantile type 7 (linear interpolation) |
| `zero_count`, `negative_count` | Counts among finite values only |

### `summarise_calendar()`

Group observations by calendar time and summarize the values in each group.

```r
summarise_calendar(
  data, time_col, value_col, groups = c("month", "weekday"), tz = NULL
)
```

Choose unique group names from `weekday`, `month`, and `year`. POSIXct also
supports `hour`. Pass `character()` for no groups. Invalid or repeated group names
raise errors, as does `hour` with Date input.

The function returns a named list of tables, one per requested group:

| Fields | Meaning |
| --- | --- |
| `group`, `label` | Calendar number and English label |
| `row_count` | Rows in that group |
| `finite_value_count`, `missing_value_count`, `infinite_value_count` | Value counts within that group |
| `mean`, `median`, `sd` | Finite-value statistics, using sample standard deviation |

Tables exclude missing times and include every observed group, even when it has
no finite values. Rows follow calendar order: Monday=1 through Sunday=7,
months 1–12, hours 0–23, or numeric years. Labels always use English.

Pooling Mondays or Januaries can mix trends, uneven coverage, and changes over
time. These group summaries do not establish seasonality.

## Plotting a series

`plot_series()` returns a ggplot object for finite observations with valid times.

```r
plot_series(data, time_col, value_col, expected_frequency = NULL, tz = NULL)
```

Call `print()` to display the returned plot. The function sorts a temporary copy
chronologically. Its caption counts missing-time rows separately from rows that
have valid times but nonfinite values.

Without a frequency, the plot shows points only. A frequency permits lines when
all observed times are unique and align with the grid. Lines stop at absent slots
and nonfinite values. Repeated or off-grid timestamps leave the plot as points
only. If ggplot2 is missing, this function raises an error with installation guidance.

## Diagnostics

Dependence, stationarity, and STL functions require a supplied frequency and:

- Nonmissing, unique timestamps that align with the grid.
- No absent grid slots.
- Finite values for every observation.

The functions may sort a temporary copy chronologically. They never omit rows,
fill gaps, aggregate values, or transform data to meet these requirements.

Each returns the same outer structure:

| Element | Meaning |
| --- | --- |
| `status` | `"ok"` for a result or `"skipped"` when the calculation cannot run |
| `reason` | Explanation for a skip; `NULL` on success |
| `settings` | Column names, frequency, effective zone, ordering, and diagnostic arguments |
| `result` | Function-specific results; `NULL` for a skip |

Settings include `observation_count`, `observation_count_used`, `ordering`, and
`sorted`. The used count records observations passed to the statistical backend;
it remains zero when the function skips before that call. `sorted` records whether
the function reordered its temporary copy.

Missing optional packages produce skips. Backend errors or numerical warnings
also produce skips and retain the original message in `reason`. Invalid arguments
raise errors instead. For example, a negative lag raises an error, while missing
observations produce a skip.

### `plot_dependence()`

Inspect how values relate to earlier observations with autocorrelation (ACF)
and partial autocorrelation (PACF).

```r
plot_dependence(
  data, time_col, value_col, expected_frequency, lag_max = NULL, tz = NULL
)
```

This function needs ggplot2, at least three observations, and nonzero variance.
`lag_max` counts observations, not calendar units. Its default is
`min(40L, n - 1L)` for `n` observations; an explicit value must be an integer from
1 through n−1.

It calls `stats::acf()` and `stats::pacf()` with plotting disabled, demeaning enabled,
and `na.fail`. Settings record the effective `lag_max`, `demean`, and `na_action`.

`result` contains:

| Element | Contents |
| --- | --- |
| `acf` | Table with `lag` and `correlation`, including lag 0 |
| `pacf` | Table with `lag` and `partial_correlation`, starting at lag 1 |
| `acf_reference_bounds` | Approximate 95% white-noise bounds: ±`qnorm(.975) / sqrt(n)` |
| `plot` | ACF and PACF panels; dashed lines show the ACF bounds |

Use the bounds for exploration. The function does not recommend model orders.

### `test_stationarity()`

Run ADF and KPSS tests with lag choices you supply.

```r
test_stationarity(
  data, time_col, value_col, expected_frequency,
  adf_lags, adf_deterministic = "drift",
  kpss_null = "level", kpss_lags, tz = NULL
)
```

This function needs urca. Supply both lag arguments as nonnegative integers.
It skips constant series or samples too short for the requested terms and lags.

| Argument | Choices and backend mapping |
| --- | --- |
| `adf_lags` | Passed to `urca::ur.df(lags = ...)` with `selectlags = "Fixed"` |
| `adf_deterministic` | `"none"`, `"drift"`, or `"trend"`, passed as ADF `type` |
| `kpss_lags` | Passed to `urca::ur.kpss(use.lag = ...)` |
| `kpss_null` | `"level"` maps to KPSS type `"mu"`; `"trend"` maps to `"tau"` |

See the [ADF](https://search.r-project.org/CRAN/refmans/urca/html/ur.df.html)
and [KPSS](https://search.r-project.org/CRAN/refmans/urca/html/ur.kpss.html)
backend references for these arguments. The wrapper requires positive residual
degrees of freedom for ADF. For KPSS, it requires lags below the observation count
and enough observations to estimate the chosen constant or trend.

`result$tests` contains `test`, `statistic_name`, `statistic`, `critical_1pct`,
`critical_5pct`, and `critical_10pct`. ADF uses tau1 for `none`, tau2 for `drift`,
and tau3 for `trend`; it excludes auxiliary phi statistics. The backend supplies
critical values, not p-values.

The result also keeps the raw `adf` and `kpss` objects and `null_hypotheses`.
Settings record the arguments, `adf_selectlags`, `kpss_type`, and `backend_version`.

Interpret the tests with their different null hypotheses in mind:

| Test | Null hypothesis |
| --- | --- |
| ADF | The series has a unit root. |
| KPSS | The series is stationary around a level or trend, as you configured. |

Failure to reject a null does not establish it. The profiler does not label the
series stationary or recommend differencing.

### `decompose_series()`

Separate the original values into an additive trend, one seasonal cycle, and a
remainder using STL.

```r
decompose_series(
  data, time_col, value_col, expected_frequency,
  seasonal_period, s_window = "periodic", tz = NULL
)
```

This function needs ggplot2. Set `seasonal_period` to an integer of at least 2,
counting observations per cycle. For monthly data, 12 represents an annual cycle.
For hourly data, 24 represents a daily cycle. This is separate from the sampling
frequency.

STL requires more than two complete cycles. `s_window` accepts `"periodic"` or
an odd integer of at least 7. Invalid settings raise errors; too few observations
produce a skip.

`result$components` contains `timestamp`, `observed`, `trend`, `seasonal`, and
`remainder`. The result also includes a component `plot` and the raw `stl` object.
The table and plot retain the original timestamps.

The function calls `stats::stl()` on a temporary `ts` object without transforming
the values. It uses `robust = FALSE`, `inner = 2`, `outer = 0`, and `na.fail`.
Settings record those choices, `seasonal_period`, `s_window`, `transformation`,
and `decomposition`. The `backend` settings contain effective windows (`win`),
polynomial degrees (`deg`), smoothing steps (`jump`), iteration counts (`inner`,
`outer`), `ts_start = c(1, 1)`, and `frequency`.

STL here captures one nominated cycle. Hourly data can contain daily, weekly,
and yearly cycles that a single decomposition does not fully represent.
