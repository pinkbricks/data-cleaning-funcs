# Run from the repository root: Rscript tests/test_time_series_profiler.R
if (!requireNamespace("testthat", quietly = TRUE)) {
  stop('Install testthat first: install.packages("testthat")', call. = FALSE)
}

# Support both Rscript from the root and testthat::test_file() from tests/.
profiler_path <- normalizePath(if (file.exists("time_series_profiler.R")) {
  "time_series_profiler.R"
} else {
  file.path("..", "time_series_profiler.R")
}, mustWork = TRUE)

source(profiler_path, local = TRUE)

fixture <- function() {
  data.frame(time = as.Date(c("2024-01-04", "2024-01-01", "2024-01-01",
    NA, "2024-01-03", "2024-01-06", "2024-01-07", "2024-01-08")),
    value = c(4, 0, -2, 10, NA, Inf, -Inf, NaN), ignored = letters[1:8])
}

regular_fixture <- function(n = 60L) {
  i <- seq_len(n)
  data.frame(time = if (n) seq(as.Date("2020-01-01"), by = "month", length.out = n) else as.Date(character()),
    value = sin(i * .71) + cos(i * 1.9) + (i %% 7) * .13 + i * .02)
}

all_calls <- function(data) {
  list(
    overview = function() series_overview(data, "time", "value"),
    index = function() check_time_index(data, "time"),
    gaps = function() find_time_gaps(data, "time", "monthly"),
    values = function() summarise_values(data, "value"),
    calendar = function() summarise_calendar(data, "time", "value"),
    profile = function() profile_time_series(data, "time", "value", "monthly"),
    plot = function() plot_series(data, "time", "value", "monthly"),
    dependence = function() plot_dependence(data, "time", "value", "monthly"),
    stationarity = function() test_stationarity(data, "time", "value", "monthly",
                                               adf_lags = 1, kpss_lags = 2),
    stl = function() decompose_series(data, "time", "value", "monthly", 12)
  )
}

testthat::test_that("hand-calculated core summaries distinguish time slots and values", {
  d <- fixture()
  overview <- series_overview(d, "time", "value")
  testthat::expect_equal(overview$row_count, 8)
  testthat::expect_equal(overview$valid_time_count, 7)
  testthat::expect_equal(overview$missing_time_count, 1)
  testthat::expect_equal(overview$start, as.Date("2024-01-01"))
  testthat::expect_equal(overview$end, as.Date("2024-01-08"))
  testthat::expect_identical(overview$time_class, "Date")
  testthat::expect_null(overview$time_zone)
  testthat::expect_equal(overview$value_non_missing_count, 6)
  testthat::expect_equal(overview$value_missing_pct, 25)
  testthat::expect_equal(overview$finite_value_count, 4)
  testthat::expect_equal(overview$positive_inf_count, 1)
  testthat::expect_equal(overview$negative_inf_count, 1)
  index <- check_time_index(d, "time")
  testthat::expect_equal(index$summary, list(missing_time_count = 1, unique_time_count = 6,
    duplicate_rows_after_first = 1, rows_in_duplicate_time_groups = 2,
    is_nondecreasing = FALSE, is_strictly_increasing = FALSE))
  testthat::expect_equal(index$duplicate_times,
    data.frame(timestamp = as.Date("2024-01-01"), count = 2L))
  testthat::expect_equal(index$intervals,
    data.frame(interval = c(1, 2), unit = c("days", "days"), count = c(3L, 2L)))
  gaps <- find_time_gaps(d, "time", "daily")
  testthat::expect_named(gaps, c("status", "reason", "summary", "missing_times", "off_grid_rows"))
  testthat::expect_identical(gaps$status, "ok")
  testthat::expect_null(gaps$reason)
  testthat::expect_equal(gaps$missing_times$timestamp, as.Date(c("2024-01-02", "2024-01-05")))
  testthat::expect_equal(gaps$summary$expected_slot_count, 8)
  testthat::expect_equal(gaps$summary$observed_slot_count, 6)
  testthat::expect_equal(gaps$summary$missing_slot_count, 2)
  testthat::expect_equal(gaps$summary$missing_slot_pct, 25)
  testthat::expect_type(gaps$off_grid_rows$reason, "character")
  values <- summarise_values(d, "value")
  testthat::expect_equal(values$missing_count, 2)
  testthat::expect_equal(values$finite_count, 4)
  testthat::expect_equal(values$mean, 3)
  testthat::expect_equal(values$sd, sqrt(28))
  testthat::expect_equal(unname(unlist(values[c("min", "q25", "median", "q75", "max")])),
                         c(-2, -0.5, 2, 5.5, 10))
  testthat::expect_equal(values$zero_count, 1)
  testthat::expect_equal(values$negative_count, 1)
  calendar <- summarise_calendar(d, "time", "value")
  testthat::expect_equal(calendar$month$label, "January")
  testthat::expect_equal(calendar$month$row_count, 7)
  testthat::expect_equal(calendar$month$finite_value_count, 3)
  testthat::expect_equal(calendar$month$missing_value_count, 2)
  testthat::expect_equal(calendar$month$infinite_value_count, 2)
  testthat::expect_equal(calendar$month$mean, 2 / 3)
  testthat::expect_equal(calendar$weekday$group, c(1L, 3L, 4L, 6L, 7L))
  testthat::expect_equal(calendar$weekday$label, c("Monday", "Wednesday", "Thursday", "Saturday", "Sunday"))
  testthat::expect_true(is.na(calendar$weekday$mean[2]))
})

testthat::test_that("empty, missing, and singleton inputs retain schemas and typed times", {
  for (time in list(as.Date(character()), as.Date(c(NA, NA)),
                    as.POSIXct(character(), tz = "UTC"), as.POSIXct(c(NA, NA), tz = "UTC"))) {
    d <- data.frame(time = time, value = rep(NA_real_, length(time)))
    frequency <- if (inherits(time, "Date")) "daily" else "hourly"
    report <- profile_time_series(d, "time", "value", frequency)
    testthat::expect_identical(class(report$overview$start), class(time))
    testthat::expect_true(is.na(report$overview$start))
    testthat::expect_true(is.na(report$time_index$summary$is_nondecreasing))
    testthat::expect_equal(report$time_index$summary$duplicate_rows_after_first, 0)
    testthat::expect_identical(report$gaps$status, "unavailable")
    testthat::expect_identical(class(report$gaps$missing_times$timestamp), class(time))
    testthat::expect_identical(class(report$gaps$off_grid_rows$timestamp), class(time))
    testthat::expect_equal(report$values$finite_count, 0)
    testthat::expect_true(is.na(report$values$mean))
    testthat::expect_true(is.na(report$values$sd))
    testthat::expect_named(report$calendar$month, c("group", "label", "row_count", "finite_value_count",
      "missing_value_count", "infinite_value_count", "mean", "median", "sd"))
    testthat::expect_equal(nrow(report$calendar$month), 0)
    if (!length(time)) testthat::expect_true(is.na(report$overview$value_missing_pct))
  }
  d <- data.frame(time = as.Date("2024-01-01"), value = 0)
  testthat::expect_equal(find_time_gaps(d, "time", "daily")$summary$expected_slot_count, 1)
  testthat::expect_true(is.na(summarise_values(d, "value")$sd))
  testthat::expect_true(is.na(check_time_index(d, "time")$summary$is_strictly_increasing))
  absent <- data.frame(time = as.Date(character()), value = numeric())
  gaps <- find_time_gaps(absent, "time", "daily", as.Date("2024-01-01"), as.Date("2024-01-03"))
  testthat::expect_identical(gaps$status, "ok")
  testthat::expect_equal(gaps$summary$missing_slot_count, 3)
  testthat::expect_equal(gaps$summary$missing_slot_pct, 100)
  testthat::expect_identical(find_time_gaps(absent, "time", "daily", as.Date("2024-01-01"))$status, "unavailable")
})

testthat::test_that("calendar grids handle leap days, weeks, months, and non-January anchors", {
  dates <- function(x) data.frame(time = as.Date(x))
  testthat::expect_equal(find_time_gaps(dates(c("2024-02-28", "2024-03-01")), "time", "daily")$missing_times$timestamp,
                         as.Date("2024-02-29"))
  weekly <- find_time_gaps(dates(c("2024-01-03", "2024-01-17", "2024-01-18")), "time", "weekly")
  testthat::expect_equal(weekly$missing_times$timestamp, as.Date("2024-01-10"))
  testthat::expect_equal(weekly$off_grid_rows$row_number, 3L)
  monthly <- find_time_gaps(dates(c("2024-01-01", "2024-03-01")), "time", "monthly")
  testthat::expect_equal(monthly$missing_times$timestamp, as.Date("2024-02-01"))
  quarterly <- find_time_gaps(dates(c("2023-02-01", "2023-08-01")), "time", "quarterly")
  testthat::expect_equal(quarterly$missing_times$timestamp, as.Date("2023-05-01"))
  yearly <- find_time_gaps(dates(c("2022-07-01", "2024-07-01")), "time", "yearly")
  testthat::expect_equal(yearly$missing_times$timestamp, as.Date("2023-07-01"))
  complete <- dates(c("2024-01-01", "2024-02-01", "2024-03-01"))
  testthat::expect_equal(check_time_index(complete, "time")$intervals$interval, c(29, 31))
  testthat::expect_equal(find_time_gaps(complete, "time", "monthly")$summary$missing_slot_count, 0)
  testthat::expect_error(find_time_gaps(dates("2024-01-31"), "time", "monthly"), "first day")
})

testthat::test_that("boundaries enforce alignment and distinguish outside and off-grid rows", {
  d <- data.frame(time = as.Date(c("2024-01-01", "2024-01-03", "2024-01-04", "2024-01-17", NA)))
  gaps <- find_time_gaps(d, "time", "weekly", as.Date("2024-01-03"), as.Date("2024-01-10"))
  testthat::expect_equal(gaps$off_grid_rows$row_number, c(1L, 3L, 4L))
  testthat::expect_equal(gaps$off_grid_rows$reason, c("outside_range", "off_grid", "outside_range"))
  testthat::expect_equal(gaps$summary$off_grid_row_count, 1)
  testthat::expect_equal(gaps$summary$outside_range_row_count, 2)
  testthat::expect_equal(gaps$summary$observed_slot_count, 1)
  testthat::expect_error(find_time_gaps(d, "time", "weekly", as.Date("2024-01-03"), as.Date("2024-01-11")), "align")
  testthat::expect_error(find_time_gaps(d, "time", "daily", as.Date("2024-02-01"), as.Date("2024-01-01")), "no later")
  testthat::expect_error(find_time_gaps(d, "time", "daily", "2024-01-01"), "same time class")
  testthat::expect_error(find_time_gaps(d, "time", "daily", max_grid_size = 2), "max_grid_size")
  for (limit in list(0, -1, TRUE, 1.2, NA_real_, Inf)) {
    testthat::expect_error(find_time_gaps(d, "time", "daily", max_grid_size = limit), "max_grid_size")
  }
  monthly <- data.frame(time = as.Date(c("2024-01-15", "2024-03-01")))
  gaps <- find_time_gaps(monthly, "time", "monthly", grid_start = as.Date("2024-01-01"))
  testthat::expect_equal(gaps$off_grid_rows$row_number, 1L)
  testthat::expect_equal(gaps$summary$expected_slot_count, 3)
  testthat::expect_error(find_time_gaps(monthly, "time", "monthly", grid_end = as.Date("2024-03-15")), "first day")
})

testthat::test_that("hourly grids preserve exact instants across DST transitions", {
  zone <- "America/New_York"
  for (start in c("2024-03-10 00:00:00", "2024-11-03 00:00:00")) {
    time <- seq(as.POSIXct(start, tz = zone), by = "hour", length.out = 6)
    d <- data.frame(time = time, value = seq_along(time))
    full <- find_time_gaps(d, "time", "hourly")
    testthat::expect_equal(full$summary$missing_slot_count, 0)
    testthat::expect_equal(check_time_index(d, "time")$intervals$interval, 3600)
    gapped <- find_time_gaps(d[-3, ], "time", "hourly")
    testthat::expect_identical(gapped$missing_times$timestamp, time[3])
    if (grepl("11-03", start)) {
      testthat::expect_equal(format(time[2:3], "%H", tz = zone), c("01", "01"))
      testthat::expect_equal(check_time_index(d, "time")$summary$duplicate_rows_after_first, 0)
      testthat::expect_equal(summarise_calendar(d, "time", "value", "hour")$hour$row_count[2], 2)
    } else testthat::expect_false("02" %in% format(time, "%H", tz = zone))
  }
  time <- as.POSIXct("2024-01-01 00:00:00", tz = "UTC") + c(0, 3600, 3600.25, 7200)
  d <- data.frame(time = time)
  testthat::expect_equal(find_time_gaps(d, "time", "hourly")$off_grid_rows$row_number, 3L)
  testthat::expect_error(find_time_gaps(d, "time", "hourly", grid_end = time[3]), "align")
})

testthat::test_that("time zone overrides change grouping without changing instants", {
  d <- data.frame(time = as.POSIXct("2024-01-01 00:30:00", tz = "UTC"), value = 2)
  original <- d
  calendar <- summarise_calendar(d, "time", "value", c("hour", "year"), "America/New_York")
  testthat::expect_equal(calendar$hour$group, 19)
  testthat::expect_equal(calendar$year$group, 2023)
  profile <- profile_time_series(d, "time", "value", "hourly", tz = "America/New_York")
  testthat::expect_equal(as.numeric(profile$overview$start), as.numeric(d$time))
  testthat::expect_identical(profile$settings$time_zone, "America/New_York")
  attr(d$time, "tzone") <- NULL
  testthat::expect_error(series_overview(d, "time", "value"), "time zone")
  testthat::expect_error(check_time_index(d, "time"), "time zone")
  testthat::expect_no_error(profile_time_series(d, "time", "value", "hourly", tz = "UTC"))
  for (zone in list("", "not/a/zone", NA_character_, c("UTC", "GMT"))) {
    testthat::expect_error(summarise_calendar(original, "time", "value", tz = zone), "time zone")
  }
  testthat::expect_identical(original$time, as.POSIXct("2024-01-01 00:30:00", tz = "UTC"))
})

testthat::test_that("input validation rejects unsupported types and invalid selections", {
  d <- regular_fixture()
  testthat::expect_error(series_overview(list(), "time", "value"), "data.frame")
  for (names in list(c("x", "x"), c("", "value"), c(NA_character_, "value"))) {
    bad <- d
    names(bad) <- names
    testthat::expect_error(summarise_values(bad, "value"), "column names")
  }
  testthat::expect_error(series_overview(d, "time", "time"), "different")
  testthat::expect_error(series_overview(d, c("time", "value"), "value"), "single")
  testthat::expect_error(series_overview(d, "absent", "value"), "not found")
  for (time in list("2024-01-01", factor("2024-01-01"), 0, as.POSIXlt("2024-01-01", tz = "UTC"),
                    structure(as.Date("2024-01-01"), class = c("custom", "Date")))) {
    bad <- list(time = time, value = 1)
    class(bad) <- "data.frame"
    attr(bad, "row.names") <- 1L
    testthat::expect_error(series_overview(bad, "time", "value"), "Date or POSIXct")
  }
  for (value in list("1", factor("1"), TRUE, 1i, as.Date("2024-01-01"), list(1))) {
    bad <- data.frame(time = as.Date("2024-01-01"))
    bad$value <- value
    testthat::expect_error(summarise_values(bad, "value"), "integer or double")
  }
  d$time[1] <- Inf
  testthat::expect_error(check_time_index(d, "time"), "infinite")
  d <- regular_fixture()
  testthat::expect_error(find_time_gaps(d, "time", "hourly"), "POSIXct")
  testthat::expect_error(find_time_gaps(d, "time", "business-day"), "expected_frequency")
  testthat::expect_error(find_time_gaps(d, "time", "monthly", tz = "UTC"), "Date columns")
  testthat::expect_error(summarise_calendar(d, "time", "value", "hour"), "POSIXct")
  testthat::expect_error(summarise_calendar(d, "time", "value", "week"), "groups")
  testthat::expect_error(summarise_calendar(d, "time", "value", c("month", "month")), "groups")
  testthat::expect_identical(summarise_calendar(d, "time", "value", character()), setNames(list(), character()))
  d$time <- as.POSIXct(d$time, tz = "UTC")
  attr(d$time, "tzone") <- "UTC"
  testthat::expect_error(find_time_gaps(d, "time", "daily"), "convert intraday")
})

testthat::test_that("combined core results match standalone functions", {
  for (d in list(fixture(), regular_fixture(), regular_fixture(0))) {
    report <- profile_time_series(d, "time", "value", "daily")
    testthat::expect_named(report, c("overview", "time_index", "gaps", "values", "calendar", "settings"))
    testthat::expect_identical(report$overview, series_overview(d, "time", "value"))
    testthat::expect_identical(report$time_index, check_time_index(d, "time"))
    testthat::expect_identical(report$gaps, find_time_gaps(d, "time", "daily"))
    testthat::expect_identical(report$values, summarise_values(d, "value"))
    testthat::expect_identical(report$calendar, summarise_calendar(d, "time", "value"))
    unspecified <- profile_time_series(d, "time", "value")
    testthat::expect_identical(unspecified$gaps$status, "unavailable")
    testthat::expect_identical(unspecified$gaps$reason, "expected_frequency_not_supplied")
    testthat::expect_named(unspecified$gaps, names(report$gaps))
  }
})

testthat::test_that("all functions preserve inputs, row names, and global settings", {
  testthat::skip_if_not_installed("ggplot2")
  d <- regular_fixture()
  # data.frame's standard setter rejects these, but existing frames can contain them.
  attr(d, "row.names") <- rep("row", nrow(d))
  before <- serialize(d, NULL)
  before_search <- search()
  before_options <- options()
  before_tz <- Sys.getenv("TZ")
  for (call in all_calls(d)) {
    testthat::expect_no_error(call())
    testthat::expect_identical(serialize(d, NULL), before)
  }
  testthat::expect_identical(search(), before_search)
  testthat::expect_identical(options(), before_options)
  testthat::expect_identical(Sys.getenv("TZ"), before_tz)
  if (requireNamespace("tibble", quietly = TRUE)) {
    tb <- tibble::as_tibble(regular_fixture())
    before <- serialize(tb, NULL)
    testthat::expect_identical(profile_time_series(tb, "time", "value", "monthly"),
                               profile_time_series(regular_fixture(), "time", "value", "monthly"))
    testthat::expect_identical(serialize(tb, NULL), before)
  }
})

testthat::test_that("sourcing has no runtime side effects", {
  env <- new.env(parent = baseenv())
  before_search <- search()
  before_options <- options()
  before_devices <- grDevices::dev.list()
  testthat::expect_output(sys.source(profiler_path, env), NA)
  testthat::expect_true(all(vapply(as.list(env, all.names = TRUE), is.function, logical(1))))
  testthat::expect_identical(search(), before_search)
  testthat::expect_identical(options(), before_options)
  testthat::expect_identical(grDevices::dev.list(), before_devices)
})

testthat::test_that("diagnostics skip ineligible data without compressing the series", {
  complete <- regular_fixture()
  cases <- list(missing_slots = complete[-5, ], duplicate_times = rbind(complete, complete[1, ]),
                missing_times = complete, nonfinite_values = complete, off_grid_times = complete)
  cases$missing_times$time[5] <- NA
  cases$nonfinite_values$value[5] <- Inf
  cases$off_grid_times$time[5] <- cases$off_grid_times$time[5] + 1
  for (reason in names(cases)) {
    d <- cases[[reason]]
    results <- list(plot_dependence(d, "time", "value", "monthly"),
      test_stationarity(d, "time", "value", "monthly", adf_lags = 1, kpss_lags = 1),
      decompose_series(d, "time", "value", "monthly", 12))
    for (result in results) {
      testthat::expect_named(result, c("status", "reason", "settings", "result"))
      testthat::expect_identical(result$status, "skipped")
      testthat::expect_identical(result$reason, reason)
      testthat::expect_null(result$result)
      testthat::expect_equal(result$settings$observation_count_used, 0)
    }
  }
  d <- complete
  d$time <- d$time + 1
  testthat::expect_identical(plot_dependence(d, "time", "value", "monthly")$reason, "off_grid_times")
  d <- complete
  d$value[4] <- NA
  testthat::expect_identical(plot_dependence(d, "time", "value", "monthly")$reason, "nonfinite_values")
  d$value <- rep(2, nrow(d))
  testthat::expect_identical(plot_dependence(d, "time", "value", "monthly")$reason, "zero_variance")
  testthat::expect_identical(test_stationarity(d, "time", "value", "monthly", 1, kpss_lags = 1)$reason, "zero_variance")
  testthat::expect_identical(plot_dependence(complete[1:2, ], "time", "value", "monthly")$status, "skipped")
  testthat::expect_identical(decompose_series(complete[1:24, ], "time", "value", "monthly", 12)$status, "skipped")
})

testthat::test_that("invalid diagnostic settings raise errors and sample limits skip", {
  d <- regular_fixture()
  for (lag in list(TRUE, -1, 1.5, NA_real_)) {
    testthat::expect_error(plot_dependence(d, "time", "value", "monthly", lag), "lag_max")
    testthat::expect_error(test_stationarity(d, "time", "value", "monthly", lag, kpss_lags = 1), "adf_lags")
    testthat::expect_error(test_stationarity(d, "time", "value", "monthly", 1, kpss_lags = lag), "kpss_lags")
  }
  testthat::expect_error(plot_dependence(d, "time", "value", "monthly", 60), "n - 1")
  testthat::expect_error(plot_dependence(d, "time", "value", "monthly", 0), "lag_max")
  testthat::expect_error(test_stationarity(d, "time", "value", "monthly"), "explicitly")
  testthat::expect_error(test_stationarity(d, "time", "value", "monthly", 1, "bad", kpss_lags = 1), "adf_deterministic")
  testthat::expect_error(test_stationarity(d, "time", "value", "monthly", 1, kpss_null = "bad", kpss_lags = 1), "kpss_null")
  testthat::expect_identical(test_stationarity(d, "time", "value", "monthly", 40, kpss_lags = 1)$status, "skipped")
  testthat::expect_identical(test_stationarity(d, "time", "value", "monthly", 1, kpss_lags = 60)$status, "skipped")
  testthat::expect_error(decompose_series(d, "time", "value", "monthly", 1), "seasonal_period")
  for (window in list(6, 8, "automatic", TRUE)) {
    testthat::expect_error(decompose_series(d, "time", "value", "monthly", 12, window), "s_window")
  }
})

testthat::test_that("dependence agrees with stats and records sorting", {
  testthat::skip_if_not_installed("ggplot2")
  d <- regular_fixture()
  result <- plot_dependence(d[nrow(d):1, ], "time", "value", "monthly", lag_max = 8)
  testthat::expect_identical(result$status, "ok")
  testthat::expect_true(result$settings$sorted)
  testthat::expect_equal(result$settings$lag_max, 8)
  testthat::expect_equal(result$settings$observation_count_used, nrow(d))
  testthat::expect_equal(result$result$acf$correlation, as.numeric(stats::acf(d$value, lag.max = 8, plot = FALSE)$acf))
  testthat::expect_equal(result$result$pacf$partial_correlation, as.numeric(stats::pacf(d$value, lag.max = 8, plot = FALSE)$acf))
  testthat::expect_equal(result$result$acf$lag, 0:8)
  testthat::expect_equal(result$result$pacf$lag, 1:8)
  testthat::expect_match(result$result$plot$labels$caption, "exploration")
  testthat::expect_no_error(ggplot2::ggplot_build(result$result$plot))
  testthat::expect_equal(plot_dependence(d, "time", "value", "monthly")$settings$lag_max, 40)
})

testthat::test_that("ADF tau and KPSS statistics match explicit backend settings", {
  testthat::skip_if_not_installed("urca")
  d <- regular_fixture()
  for (deterministic in c("none", "drift", "trend")) {
    for (null in c("level", "trend")) {
      for (lag in c(0L, 2L)) {
        result <- test_stationarity(d, "time", "value", "monthly", lag,
                                    deterministic, null, lag)
        testthat::expect_identical(result$status, "ok")
        adf <- urca::ur.df(d$value, type = deterministic, lags = lag, selectlags = "Fixed")
        kpss <- urca::ur.kpss(d$value, type = if (null == "level") "mu" else "tau", use.lag = lag)
        tau <- switch(deterministic, none = "tau1", drift = "tau2", trend = "tau3")
        testthat::expect_equal(result$result$tests$statistic, c(adf@teststat[1, tau], kpss@teststat))
        testthat::expect_equal(result$result$tests$critical_1pct, c(adf@cval[tau, "1pct"], kpss@cval[1, "1pct"]))
        testthat::expect_equal(result$result$tests$critical_5pct, c(adf@cval[tau, "5pct"], kpss@cval[1, "5pct"]))
        testthat::expect_equal(result$result$tests$critical_10pct, c(adf@cval[tau, "10pct"], kpss@cval[1, "10pct"]))
        testthat::expect_identical(result$settings$adf_selectlags, "Fixed")
        testthat::expect_equal(result$result$adf@lags, lag)
        testthat::expect_equal(result$result$kpss@lag, lag)
        testthat::expect_false("p_value" %in% names(result$result$tests))
      }
    }
  }
})

testthat::test_that("STL agrees with stats and retains original timestamps", {
  testthat::skip_if_not_installed("ggplot2")
  d <- regular_fixture()
  for (window in list("periodic", 7L)) {
    result <- decompose_series(d[nrow(d):1, ], "time", "value", "monthly", 12, window)
    testthat::expect_identical(result$status, "ok")
    testthat::expect_true(result$settings$sorted)
    direct <- stats::stl(stats::ts(d$value, frequency = 12), s.window = window)
    table <- result$result$components
    testthat::expect_identical(table$timestamp, d$time)
    testthat::expect_identical(table$observed, d$value)
    testthat::expect_equal(table$trend, as.numeric(direct$time.series[, "trend"]))
    testthat::expect_equal(table$seasonal, as.numeric(direct$time.series[, "seasonal"]))
    testthat::expect_equal(table$remainder, as.numeric(direct$time.series[, "remainder"]))
    testthat::expect_identical(result$settings$backend$win, direct$win)
    testthat::expect_identical(result$settings$backend$deg, direct$deg)
    testthat::expect_identical(result$settings$backend$jump, direct$jump)
    testthat::expect_no_error(ggplot2::ggplot_build(result$result$plot))
  }
})

testthat::test_that("series plots break lines at missing slots and nonfinite values", {
  testthat::skip_if_not_installed("ggplot2")
  d <- data.frame(time = as.Date("2024-01-01") + c(0, 1, 3, 4, 5, 6, 7, NA),
                  value = c(1, 2, 3, 4, NA, 6, 7, 8))
  plot <- plot_series(d, "time", "value", "daily")
  testthat::expect_s3_class(plot, "ggplot")
  testthat::expect_match(plot$labels$caption, "Omitted 2 rows: 1 with missing times; 1")
  built <- ggplot2::ggplot_build(plot)
  lines <- built$data[[2]]
  testthat::expect_equal(length(unique(lines$group)), 3)
  testthat::expect_true(all(vapply(split(lines$x, lines$group), function(x) all(diff(x) == 1), logical(1))))
  testthat::expect_equal(length(plot_series(d, "time", "value")$layers), 1)
  duplicate <- rbind(d, d[1, ])
  testthat::expect_equal(length(plot_series(duplicate, "time", "value", "daily")$layers), 1)
  irregular <- data.frame(time = as.Date(c("2024-01-01", "2024-02-15")), value = 1:2)
  testthat::expect_equal(length(plot_series(irregular, "time", "value", "monthly")$layers), 1)
  empty <- data.frame(time = as.Date(character()), value = numeric())
  testthat::expect_no_error(ggplot2::ggplot_build(plot_series(empty, "time", "value", "daily")))
})

testthat::test_that("missing optional dependencies skip diagnostics and explain plot installation", {
  # Use an isolated source environment to simulate missing dependencies.
  env <- new.env(parent = globalenv())
  sys.source(profiler_path, env)
  env$.tsp_has_package <- function(package) FALSE
  d <- regular_fixture()
  testthat::expect_error(env$plot_series(d, "time", "value"), "install.packages")
  testthat::expect_match(env$plot_dependence(d, "time", "value", "monthly")$reason, "ggplot2")
  testthat::expect_match(env$decompose_series(d, "time", "value", "monthly", 12)$reason, "ggplot2")
  testthat::expect_match(env$test_stationarity(d, "time", "value", "monthly", 1, kpss_lags = 1)$reason, "urca")
  testthat::expect_no_error(env$profile_time_series(d, "time", "value", "monthly"))
})

testthat::test_that("backend errors and numerical warnings retain original messages", {
  settings <- list(observation_count = 10L, observation_count_used = 0L)
  for (compute in list(function() stop("original backend error"),
                        function() warning("original backend warning"))) {
    result <- .tsp_backend(settings, compute)
    testthat::expect_identical(result$status, "skipped")
    testthat::expect_match(result$reason, "backend_failure: original backend")
    testthat::expect_null(result$result)
  }
})


testthat::test_that("monthly alignment never hides fractional Date values", {
  d <- data.frame(time = as.Date(c("2024-01-01", "2024-02-01")) + c(0, .5), value = 1:2)
  testthat::expect_equal(find_time_gaps(d, "time", "monthly")$off_grid_rows$row_number, 2L)
  testthat::expect_error(find_time_gaps(d, "time", "monthly", grid_end = d$time[2]), "first day")
  testthat::expect_identical(plot_dependence(d, "time", "value", "monthly")$reason, "off_grid_times")
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    testthat::expect_equal(length(plot_series(d, "time", "value", "monthly")$layers), 1)
  }
})
