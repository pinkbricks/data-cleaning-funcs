# R time series profiler: single-series specification

## Goal

Create `time_series_profiler.R`, a reusable module that users load with `source()`. Its functions describe one numeric series and its time index. They return structured results that users can inspect in an R script or notebook.

The module must not clean data, score data quality, select models, or forecast. Statistical diagnostics provide evidence for investigation; they must not declare a series stationary or seasonal automatically.

## Deliverables and scope

Deliver the R module, documentation in the shared README, a synthetic-data example, and one self-contained R test file. Use the `testthat` library for assertions and keep fixtures and test helpers in that same file. Include core profiling, optional plots, and opt-in statistical diagnostics. Do not build a dashboard, CLI, package publishing workflow, or report renderer.

Support a data.frame or tibble containing one time column and one numeric value column. Ignore extra columns. The caller is responsible for selecting a single series before calling; do not aggregate groups or infer series identifiers.

All functions must leave the input unchanged. Sourcing the file must not attach packages, install dependencies, print output, plot, write files, or run examples. Use explicit namespaces for dependencies. Return plots without displaying them.

## Public interface

Use column names supplied as single strings, rather than nonstandard evaluation.

```r
series_overview(data, time_col, value_col)
check_time_index(data, time_col)
find_time_gaps(data, time_col, expected_frequency,
               grid_start = NULL, grid_end = NULL,
               tz = NULL, max_grid_size = 1000000L)
summarise_values(data, value_col)
summarise_calendar(data, time_col, value_col,
                   groups = c("month", "weekday"), tz = NULL)
plot_series(data, time_col, value_col,
            expected_frequency = NULL, tz = NULL)
plot_dependence(data, time_col, value_col, expected_frequency,
                lag_max = NULL, tz = NULL)
test_stationarity(data, time_col, value_col, expected_frequency,
                   adf_lags, adf_deterministic = "drift",
                   kpss_null = "level", kpss_lags, tz = NULL)
decompose_series(data, time_col, value_col, expected_frequency,
                  seasonal_period, s_window = "periodic", tz = NULL)
profile_time_series(data, time_col, value_col,
                     expected_frequency = NULL,
                     grid_start = NULL, grid_end = NULL,
                     tz = NULL, calendar_groups = c("month", "weekday"),
                     max_grid_size = 1000000L)
```

Statistical diagnostics remain separate opt-in calls. The combined function runs core profiling and calendar summaries only, so a basic profile never launches hypothesis tests implicitly.

## Time input contract

- Accept `Date` or `POSIXct` time columns. Reject strings, factors, numeric epochs, `POSIXlt`, and unsupported date classes with an actionable error. The caller parses dates first.
- Accept integer or double value columns. Reject factors, characters, logicals, complex values, dates, and list columns. Do not convert numeric-looking strings.
- Missing times are `is.na(time)`; reject infinite time values. Treat numeric `NA` and `NaN` as missing values and report positive/negative infinity separately.
- Require unique, nonmissing, nonempty column names. Reject absent columns and identical time/value selections.
- Preserve original row positions in detail outputs using a one-based `row_number`; do not rely on row names as identifiers.
- For POSIXct data, use an explicit `tz` override or a valid nonempty time zone stored on the column. If neither exists, require the caller to provide one; never silently depend on the computer's local zone. A time zone override changes calendar interpretation, not the underlying instants.
- Date columns have no intraday time zone; reject a non-NULL `tz` for Date input.

## Expected frequency and grid semantics

Use `expected_frequency`, not an inferred frequency, for gap checks and statistical eligibility. Supported values in this version are `hourly`, `daily`, `weekly`, `monthly`, `quarterly`, and `yearly`.

- Hourly uses POSIXct and successive elapsed hours. Respect the supplied time zone when displaying labels, including repeated/skipped local clock hours at daylight saving transitions.
- Daily, weekly, monthly, quarterly, and yearly use Date. Require the caller to deliberately convert intraday data to Date before applying these frequencies; never discard time-of-day implicitly.
- Daily means every calendar day; weekly means every seven calendar days from the anchor. Business-day, trading-day, holiday, and custom schedules are out of scope.
- Monthly, quarterly, and yearly dates must use the first day of the represented period. Monthly steps one month; quarterly steps three months; yearly steps twelve months. Require quarterly/yearly anchors on the first day of their starting month, without assuming calendar-quarter or January starts. Reject other day-of-month anchors instead of applying ambiguous month-end arithmetic.
- By default, generate a grid between the minimum and maximum observed nonmissing timestamps, anchored at the minimum. Explicit start/end boundaries override those endpoints and must share the time class, align with the anchor, and have start <= end. If a start is supplied, it becomes the anchor.
- Do not infer coverage outside the chosen boundaries. An observed series cannot reveal unrecorded leading or trailing periods unless the caller supplies boundaries.
- Match timestamps exactly; do not round, truncate, or use fuzzy tolerances. Report off-grid and out-of-range observations separately.
- Refuse grid generation above `max_grid_size` with an informative error. Never silently sample or truncate a gap result.
- With no valid timestamps, return an unavailable grid result unless both boundaries are supplied. With one timestamp, the default grid contains one slot.

## Core output contracts

Use named lists for grouped results and ordinary data.frames for tables. Empty tables retain their documented columns and time classes. Counts are zero for empty inputs; undefined percentages/statistics are `NA_real_`. Percentages use a 0–100 scale. Document every denominator.

### `series_overview()`

Return a named list containing `row_count`, `valid_time_count`, `missing_time_count`, `start`, `end`, `time_class`, `time_zone`, `value_non_missing_count`, `value_missing_count`, `value_missing_pct`, `finite_value_count`, `positive_inf_count`, and `negative_inf_count`.

Start/end use valid times only and retain their class. Value counts describe all supplied rows, including rows with missing times. The missing-value percentage denominator is total rows. For empty/all-missing time input, return typed missing start/end values.

### `check_time_index()`

Return a list with three elements:

- `summary`: `missing_time_count`, `unique_time_count`, `duplicate_rows_after_first`, `rows_in_duplicate_time_groups`, `is_nondecreasing`, and `is_strictly_increasing`. Ordering refers to the nonmissing times in original row order; missing-time counts remain visible. Ordering fields are NA with fewer than two valid times. Duplicate metrics exclude missing times and compare instants for POSIXct.
- `duplicate_times`: `timestamp`, `count`, ordered chronologically, with one row per repeated timestamp.
- `intervals`: `interval`, `unit`, `count`, based on consecutive sorted unique valid times. Use elapsed seconds for POSIXct and calendar days for Date. Do not claim that varying elapsed day counts imply missing monthly observations.

Sorting a temporary copy for interval calculation must not change the input or conceal original ordering.

### `find_time_gaps()`

Return `status`, `reason`, `summary`, `missing_times`, and `off_grid_rows`.

`summary` contains frequency, effective boundaries, `expected_slot_count`, `observed_slot_count`, `missing_slot_count`, `missing_slot_pct`, `off_grid_row_count`, and `outside_range_row_count`. Count observed slots once even when timestamps repeat. Missing-slot percentage uses expected slots as its denominator. A timestamp with a missing target value still occupies a slot.

`missing_times` contains one `timestamp` column, sorted chronologically. `off_grid_rows` contains `row_number`, `timestamp`, and `reason` (`off_grid` or `outside_range`, with outside-range taking precedence). Rows with missing times are counted separately in the index profile, not labelled off-grid.

Use status `ok` for completed calculations, including those that find gaps; `unavailable` for insufficient time information. Invalid configuration raises an error.

### `summarise_values()`

Return a one-row data.frame containing `row_count`, `missing_count`, `finite_count`, `positive_inf_count`, `negative_inf_count`, `mean`, `sd`, `min`, `q25`, `median`, `q75`, `max`, `zero_count`, and `negative_count`.

Compute descriptive statistics and zero/negative counts from finite values only. Use sample standard deviation and R quantile type 7. With no finite values, return NA statistics; with fewer than two finite values, return NA standard deviation. Do not flag outliers or replace values.

### `summarise_calendar()`

Return a named list of tables for the requested groups. Allow `hour` for POSIXct and `weekday`, `month`, and `year` for both supported time classes. Validate group names and reject `hour` for Date input.

Each table contains `group`, `label`, `row_count`, `finite_value_count`, `missing_value_count`, `infinite_value_count`, `mean`, `median`, and `sd`. Exclude rows with missing times from calendar groups. Include all observed groups even when all their values are missing. Use finite values for statistics and calendar order for rows. Weekdays use Monday=1 through Sunday=7; months use 1–12, independent of system language. Labels use English for stable output.

These are descriptive group summaries, not proof of seasonality. Pooling all Mondays or Januaries can mix trends, unequal coverage, and changes over time. State this limitation in the documentation.

### `profile_time_series()`

Return exactly `overview`, `time_index`, `gaps`, `values`, `calendar`, and `settings`. Match standalone function results. Settings record the column names, requested frequency, effective time zone, calendar groups, and grid boundaries.

When expected frequency is NULL, return an unavailable gaps result with reason `expected_frequency_not_supplied`; do not guess. Exclude source-data copies from the report.

## Optional plots and diagnostics

### Series plot

Return a ggplot object. Always allow a point plot for observed finite values with valid times. Add connecting lines only when a supplied frequency establishes a unique, aligned grid; break lines across absent slots and nonfinite values. Do not join repeated timestamps or bridge a data gap. Sort a temporary plotting copy chronologically. Document any rows omitted from the plot through plot caption counts.

### Shared diagnostic requirements

ACF/PACF, stationarity tests, and STL require a supplied frequency, no missing times, unique timestamps, no gaps or off-grid observations, and finite values for every slot. Diagnostics may sort a temporary copy by timestamp, but must record that they did so. Never use `na.omit()`, interpolation, differencing, aggregation, log transforms, or automatic gap filling to make a diagnostic run.

Return a structured result with `status` (`ok` or `skipped`), `reason`, `settings`, and `result`. Data-dependent ineligibility produces a skipped result rather than destroying the rest of a profile. Invalid arguments raise errors. Record the observation count used and chronological ordering. Backend numerical failures become skipped results with the original diagnostic message retained; never fabricate a statistic.

### Dependence

Use `stats::acf()` and `stats::pacf()` with plotting disabled. Return tables and a ggplot object within `result`. Tables contain lag in observations and the correlation/partial correlation, including lag 0 for ACF only. Label approximate ACF reference bounds as exploratory; do not recommend ARIMA orders automatically.

Require at least three observations and nonzero variance. Use effective lag maximum `min(40L, n - 1L)` when NULL; reject explicit values outside 1 through n-1. Expose the actual lag setting.

### Stationarity tests

Use an implementation that exposes deterministic terms and explicit lag settings, such as `urca::ur.df()` and `urca::ur.kpss()`. Verify backend argument mapping against its documentation during implementation.

Require explicit nonnegative integer `adf_lags` and `kpss_lags`; do not select lags silently. Support ADF deterministic settings `none`, `drift`, and `trend`, and KPSS nulls `level` and `trend`. Disable automatic ADF lag selection. Validate backend sample-size requirements and skip with a reason when the requested settings cannot be estimated.

Return a test table containing `test`, `statistic_name`, `statistic`, and the 1%, 5%, and 10% critical values where the backend provides them. Select the ADF unit-root tau statistic appropriate to its deterministic setting; do not confuse it with auxiliary phi statistics. Return p-values only if the selected backend actually provides them. Preserve raw backend objects in `result` for inspection.

Explain that the ADF null is a unit root, while the KPSS null is level or trend stationarity as configured. A large p-value or failure to reject does not establish the null. No automatic stationarity verdict or differencing recommendation.

### STL decomposition

Use `stats::stl()` with a temporary `ts` object and caller-supplied integer `seasonal_period >= 2`. The period counts observations per cycle: e.g., 12 for monthly annual seasonality or 24 for hourly daily seasonality. It is distinct from the calendar sampling frequency.

Require more than two complete seasonal periods. Support `s_window = "periodic"` or a valid odd integer >= 7. Use additive decomposition on original values; no automatic log/Box–Cox transform. Record all effective backend settings.

Return a table with `timestamp`, `observed`, `trend`, `seasonal`, and `remainder`, plus a component plot. Use original timestamps for labels. Explain that single-period STL captures one nominated cycle; hourly data can contain multiple cycles that this decomposition does not fully represent.

## Dependencies and project layout

Use base R and `stats` for core profiling and calendar grids. Use `ggplot2` for optional plots, `urca` for optional stationarity tests, and `testthat` for development tests. Diagnostic wrappers return a clear skipped result when an optional dependency is missing. Standalone plotting calls raise an actionable dependency error. Do not install packages automatically.

Use this project layout:

| File | Purpose |
| --- | --- |
| `time_series_profiler.R` | Define all public functions and shared private helpers. |
| `README.md` | Document both profilers, including R usage, outputs, dependencies, limitations, and test commands. |
| `examples/profile_time_series_usage.R` | Demonstrate core profiling and opt-in diagnostics with synthetic data. |
| `tests/test_time_series_profiler.R` | Hold all R tests, fixtures, helper functions, and the dependency check. |

Keep one test file per profiler, directly inside `tests/`. The R file follows the same layout as Python's `tests/test_data_profiler.py`. Do not create a separate R runner, helper file, or nested test directory. `testthat` names the testing library, not a project directory or runner.

Run the R tests from the repository root:

```sh
Rscript tests/test_time_series_profiler.R
```

The test file must run directly, exit with a nonzero status when an assertion fails, and explain how to install `testthat` if it is missing. Tests that need optional packages may skip when those packages are unavailable. Keep all existing coverage when reorganizing tests.

Run the synthetic example from the repository root:

```sh
Rscript examples/profile_time_series_usage.R
```

Declare the R and package versions actually tested rather than inventing compatibility guarantees. Keep README commands and filenames consistent with this layout.

## Usage example

```r
source("time_series_profiler.R")

# Parse explicitly before profiling.
bike_data$datetime <- as.POSIXct(
  bike_data$datetime, format = "%Y-%m-%d %H:%M:%S", tz = "Asia/Seoul"
)

report <- profile_time_series(
  bike_data,
  time_col = "datetime",
  value_col = "rented_bike_count",
  expected_frequency = "hourly",
  tz = "Asia/Seoul",
  calendar_groups = c("hour", "weekday", "month")
)

report$time_index$summary
report$gaps$missing_times
report$values

# Run diagnostics deliberately after inspecting the time structure.
dependence <- plot_dependence(
  bike_data, "datetime", "rented_bike_count",
  expected_frequency = "hourly", lag_max = 48, tz = "Asia/Seoul"
)
```

## Acceptance criteria

1. Functions source and run independently without changing inputs or global settings.
2. Hand-checkable fixtures verify duplicate metrics, missing slots versus missing values, finite-only statistics, interval counts, and calendar grouping.
3. Tests cover empty input, all-missing values/times, one timestamp, unsorted rows, repeated times, infinities, constant values, invalid types, and nonunique row names where supported.
4. Grid tests cover leap days, missing hours, weekly anchors, missing months, quarterly/yearly anchors, explicit boundaries, off-grid observations, oversized grids, and daylight saving transitions in a suitable named zone.
5. Gapped, duplicated, or incomplete data never silently become a compressed regular series for diagnostics.
6. Optional numerical outputs match direct backend calls on a small eligible fixture. Tests validate settings and eligibility rather than asserting statistical conclusions from random samples.
7. Combined core outputs agree with standalone calls. Empty/unavailable outputs retain consistent schemas.
8. Documentation uses natural language and active voice, defines denominators and time semantics, and avoids repeating information or inventing behaviour.
9. No quality scores, cleaning, forecasting, automatic stationarity labels, or automatic model recommendations appear in the implementation.
10. Keep all R tests and helpers in `tests/test_time_series_profiler.R`. The documented command runs this file directly, with no separate runner or nested test directory.
