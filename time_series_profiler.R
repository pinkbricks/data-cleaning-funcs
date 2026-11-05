# Sourceable, single-series profiling. All dependencies use explicit namespaces.

.tsp_error <- function(message) stop(message, call. = FALSE)

.tsp_choice <- function(value, choices, name) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !value %in% choices) {
    .tsp_error(paste0(name, " must be one of: ", paste(choices, collapse = ", "), "."))
  }
  value
}

.tsp_integer <- function(value, name, minimum = 0) {
  if (!is.numeric(value) || is.object(value) || length(value) != 1L ||
      !is.finite(value) || value != floor(value) || value < minimum ||
      value > .Machine$integer.max) {
    .tsp_error(paste0(name, " must be an integer from ", minimum, " through ",
                      .Machine$integer.max, "."))
  }
  as.integer(value)
}

.tsp_data <- function(data, columns) {
  if (!is.data.frame(data)) .tsp_error("data must be a data.frame or tibble.")
  nm <- names(data)
  if (anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(nm)) {
    .tsp_error("Use unique, nonmissing, nonempty column names.")
  }
  for (column in columns) {
    if (!is.character(column) || length(column) != 1L || is.na(column) ||
        !nzchar(column)) .tsp_error("Supply each column name as a single nonempty string.")
    if (!column %in% nm) .tsp_error(paste0("Column not found: ", column, "."))
  }
}

.tsp_time <- function(data, time_col, tz = NULL) {
  .tsp_data(data, list(time_col))
  time <- data[[time_col]]
  date <- identical(class(time), "Date")
  datetime <- identical(class(time), c("POSIXct", "POSIXt")) ||
    identical(class(time), "POSIXct")
  if ((!date && !datetime) || !is.null(dim(time))) {
    .tsp_error("The time column must be Date or POSIXct; parse dates explicitly before profiling.")
  }
  if (any(is.infinite(as.numeric(time)))) .tsp_error("The time column contains infinite timestamps.")
  if (date) {
    if (!is.null(tz)) .tsp_error("Date columns have no intraday time zone; use tz = NULL.")
  } else {
    if (is.null(tz)) tz <- attr(time, "tzone", exact = TRUE)
    if (!is.character(tz) || length(tz) != 1L || is.na(tz) || !nzchar(tz) ||
        !tz %in% c("UTC", "GMT", OlsonNames())) {
      .tsp_error("Supply a valid nonempty time zone via tz or the POSIXct column's tzone attribute.")
    }
    attr(time, "tzone") <- tz
  }
  list(time = time, tz = tz, time_class = if (date) "Date" else "POSIXct")
}

.tsp_values <- function(data, value_col) {
  .tsp_data(data, list(value_col))
  value <- data[[value_col]]
  if (!(typeof(value) %in% c("integer", "double")) || is.object(value) ||
      !is.null(dim(value))) {
    .tsp_error("The value column must contain plain integer or double values; parse numeric data explicitly.")
  }
  value
}

.tsp_input <- function(data, time_col, value_col, tz = NULL) {
  .tsp_data(data, list(time_col, value_col))
  if (identical(time_col, value_col)) .tsp_error("time_col and value_col must select different columns.")
  input <- .tsp_time(data, time_col, tz)
  input$value <- .tsp_values(data, value_col)
  input
}

.tsp_pct <- function(count, total) if (total > 0) 100 * count / total else NA_real_
.tsp_na_time <- function(time) time[NA_integer_]

.tsp_stats <- function(value) {
  finite <- value[is.finite(value)]
  if (!length(finite)) return(list(mean = NA_real_, sd = NA_real_, min = NA_real_,
                                  q25 = NA_real_, median = NA_real_, q75 = NA_real_, max = NA_real_))
  q <- stats::quantile(finite, c(.25, .5, .75), type = 7, names = FALSE)
  list(mean = mean(finite), sd = if (length(finite) > 1L) stats::sd(finite) else NA_real_,
       min = min(finite), q25 = q[1L], median = q[2L], q75 = q[3L], max = max(finite))
}

# Describe all supplied rows; missing-value percentage uses total row count.
series_overview <- function(data, time_col, value_col) {
  input <- .tsp_input(data, time_col, value_col)
  time <- input$time
  value <- input$value
  valid <- time[!is.na(time)]
  list(row_count = nrow(data), valid_time_count = length(valid),
       missing_time_count = sum(is.na(time)),
       start = if (length(valid)) min(valid) else .tsp_na_time(time),
       end = if (length(valid)) max(valid) else .tsp_na_time(time),
       time_class = input$time_class, time_zone = input$tz,
       value_non_missing_count = sum(!is.na(value)), value_missing_count = sum(is.na(value)),
       value_missing_pct = .tsp_pct(sum(is.na(value)), length(value)),
       finite_value_count = sum(is.finite(value)),
       positive_inf_count = sum(value == Inf, na.rm = TRUE),
       negative_inf_count = sum(value == -Inf, na.rm = TRUE))
}

# Inspect original ordering and repeated instants; calculate intervals on a copy.
check_time_index <- function(data, time_col) {
  time <- .tsp_time(data, time_col)$time
  valid <- time[!is.na(time)]
  unique_times <- sort(unique(valid))
  counts <- tabulate(match(valid, unique_times), nbins = length(unique_times))
  duplicate_times <- data.frame(timestamp = unique_times[counts > 1L], count = counts[counts > 1L])
  deltas <- diff(as.numeric(unique_times))
  intervals <- sort(unique(deltas))
  list(summary = list(missing_time_count = sum(is.na(time)),
       unique_time_count = length(unique_times),
       duplicate_rows_after_first = sum(duplicated(valid)),
       rows_in_duplicate_time_groups = sum(counts[counts > 1L]),
       is_nondecreasing = if (length(valid) < 2L) NA else all(diff(as.numeric(valid)) >= 0),
       is_strictly_increasing = if (length(valid) < 2L) NA else all(diff(as.numeric(valid)) > 0)),
       duplicate_times = duplicate_times,
       intervals = data.frame(interval = intervals,
         unit = rep(if (inherits(time, "Date")) "days" else "seconds", length(intervals)),
         count = tabulate(match(deltas, intervals), nbins = length(intervals))))
}

.tsp_frequency <- function(frequency, time) {
  .tsp_choice(frequency, c("hourly", "daily", "weekly", "monthly", "quarterly", "yearly"),
              "expected_frequency")
  if (frequency == "hourly" && !inherits(time, "POSIXct")) {
    .tsp_error("hourly requires POSIXct timestamps.")
  }
  if (frequency != "hourly" && !inherits(time, "Date")) {
    .tsp_error("daily through yearly frequencies require Date; deliberately convert intraday data first.")
  }
  frequency
}

.tsp_month <- function(time) {
  as.numeric(format(time, "%Y")) * 12 + as.numeric(format(time, "%m")) - 1
}

.tsp_offset <- function(time, anchor, frequency) {
  if (frequency == "hourly") return((as.numeric(time) - as.numeric(anchor)) / 3600)
  if (frequency == "daily") return(as.numeric(time) - as.numeric(anchor))
  if (frequency == "weekly") return((as.numeric(time) - as.numeric(anchor)) / 7)
  step <- switch(frequency, monthly = 1, quarterly = 3, yearly = 12)
  offset <- (.tsp_month(time) - .tsp_month(anchor)) / step
  offset[format(time, "%d") != "01" | as.numeric(time) != floor(as.numeric(time))] <- NA_real_
  offset
}

.tsp_boundary <- function(boundary, name, time, tz) {
  if (is.null(boundary)) return(NULL)
  same <- if (inherits(time, "Date")) identical(class(boundary), "Date") else
    identical(class(boundary), c("POSIXct", "POSIXt")) || identical(class(boundary), "POSIXct")
  if (!same || length(boundary) != 1L || !is.null(dim(boundary)) ||
      is.na(boundary) || !is.finite(as.numeric(boundary))) {
    .tsp_error(paste0(name, " must be one finite timestamp with the same time class as the column."))
  }
  if (inherits(time, "POSIXct")) attr(boundary, "tzone") <- tz
  boundary
}

.tsp_gap_result <- function(time, frequency, start = NULL, end = NULL,
                            reason = "insufficient_time_information") {
  list(status = "unavailable", reason = reason,
       summary = list(expected_frequency = frequency,
         grid_start = if (is.null(start)) .tsp_na_time(time) else start,
         grid_end = if (is.null(end)) .tsp_na_time(time) else end,
         expected_slot_count = 0L, observed_slot_count = 0L, missing_slot_count = 0L,
         missing_slot_pct = NA_real_, off_grid_row_count = 0L, outside_range_row_count = 0L),
       missing_times = data.frame(timestamp = time[FALSE]),
       off_grid_rows = data.frame(row_number = integer(), timestamp = time[FALSE], reason = character()))
}

# Compare exact timestamps with the caller's calendar or elapsed-hour schedule.
find_time_gaps <- function(data, time_col, expected_frequency, grid_start = NULL,
                           grid_end = NULL, tz = NULL, max_grid_size = 1000000L) {
  input <- .tsp_time(data, time_col, tz)
  time <- input$time
  frequency <- .tsp_frequency(expected_frequency, time)
  limit <- .tsp_integer(max_grid_size, "max_grid_size", 1)
  start <- .tsp_boundary(grid_start, "grid_start", time, input$tz)
  end <- .tsp_boundary(grid_end, "grid_end", time, input$tz)
  monthly <- frequency %in% c("monthly", "quarterly", "yearly")
  for (bound in list(start, end)) {
    if (!is.null(bound) && monthly &&
        (format(bound, "%d") != "01" || as.numeric(bound) != floor(as.numeric(bound)))) {
      .tsp_error("Monthly, quarterly, and yearly boundaries must use the first day of a month.")
    }
  }
  valid <- time[!is.na(time)]
  if (is.null(start) && length(valid)) start <- min(valid)
  if (is.null(end) && length(valid)) end <- max(valid)
  output <- .tsp_gap_result(time, frequency, start, end)
  if (is.null(start) || is.null(end)) return(output)
  if (start > end) .tsp_error("grid_start must be no later than grid_end.")
  if (monthly && (format(start, "%d") != "01" || as.numeric(start) != floor(as.numeric(start)))) {
    .tsp_error("Monthly, quarterly, and yearly anchors must use the first day of a month; supply grid_start.")
  }
  end_offset <- .tsp_offset(end, start, frequency)
  if (!is.null(grid_end) && (is.na(end_offset) || end_offset != floor(end_offset))) {
    .tsp_error("grid_end must align exactly with the grid_start anchor and expected_frequency.")
  }
  # A default maximum may be off-grid; include all grid slots up to that instant.
  if (monthly) {
    step <- switch(frequency, monthly = 1, quarterly = 3, yearly = 12)
    end_offset <- (.tsp_month(end) - .tsp_month(start)) / step
  }
  slots <- floor(end_offset) + 1
  if (!is.finite(slots) || slots > limit) {
    .tsp_error(paste0("Expected grid exceeds max_grid_size (", limit,
                     "); narrow the boundaries or explicitly increase the limit."))
  }
  by <- switch(frequency, hourly = "hour", daily = "day", weekly = "week",
               monthly = "month", quarterly = "3 months", yearly = "year")
  grid <- seq(start, by = by, length.out = slots)
  match_slot <- match(time, grid)
  outside <- !is.na(time) & (time < start | time > end)
  off_grid <- !is.na(time) & !outside & is.na(match_slot)
  positions <- which(outside | off_grid)
  observed <- unique(match_slot[!is.na(match_slot) & !outside])
  missing <- grid[!seq_along(grid) %in% observed]
  output$status <- "ok"
  output["reason"] <- list(NULL)
  output$summary$expected_slot_count <- length(grid)
  output$summary$observed_slot_count <- length(observed)
  output$summary$missing_slot_count <- length(missing)
  output$summary$missing_slot_pct <- .tsp_pct(length(missing), length(grid))
  output$summary$off_grid_row_count <- sum(off_grid)
  output$summary$outside_range_row_count <- sum(outside)
  output$missing_times <- data.frame(timestamp = missing)
  output$off_grid_rows <- data.frame(row_number = positions, timestamp = time[positions],
                                    reason = as.character(ifelse(outside[positions], "outside_range", "off_grid")))
  output
}

# Summarize finite values using sample SD and R quantile type 7.
summarise_values <- function(data, value_col) {
  value <- .tsp_values(data, value_col)
  finite <- value[is.finite(value)]
  as.data.frame(c(list(row_count = length(value), missing_count = sum(is.na(value)),
    finite_count = length(finite), positive_inf_count = sum(value == Inf, na.rm = TRUE),
    negative_inf_count = sum(value == -Inf, na.rm = TRUE)), .tsp_stats(value),
    list(zero_count = sum(finite == 0), negative_count = sum(finite < 0))))
}

# Pool observed calendar groups; this describes patterns without testing seasonality.
summarise_calendar <- function(data, time_col, value_col,
                                groups = c("month", "weekday"), tz = NULL) {
  input <- .tsp_input(data, time_col, value_col, tz)
  if (!is.character(groups) || anyNA(groups) || anyDuplicated(groups) ||
      any(!groups %in% c("hour", "weekday", "month", "year"))) {
    .tsp_error("groups must contain unique names from hour, weekday, month, and year.")
  }
  if (input$time_class == "Date" && "hour" %in% groups) .tsp_error("hour grouping requires POSIXct.")
  valid <- !is.na(input$time)
  time <- input$time[valid]
  value <- input$value[valid]
  # Explicit English labels avoid changes with the host's locale.
  months <- c("January", "February", "March", "April", "May", "June", "July", "August",
              "September", "October", "November", "December")
  weekdays <- c("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
  output <- stats::setNames(vector("list", length(groups)), groups)
  for (name in groups) {
    code <- switch(name, hour = "%H", weekday = "%u", month = "%m", year = "%Y")
    group <- as.integer(if (input$time_class == "Date") format(time, code) else
                          format(time, code, tz = input$tz))
    keys <- sort(unique(group))
    table <- data.frame(group = integer(), label = character(), row_count = integer(),
                        finite_value_count = integer(), missing_value_count = integer(),
                        infinite_value_count = integer(), mean = numeric(), median = numeric(), sd = numeric())
    for (key in keys) {
      values <- value[group == key]
      stats <- .tsp_stats(values)
      label <- switch(name, month = months[key], weekday = weekdays[key],
                      hour = sprintf("%02d:00", key), year = as.character(key))
      table <- rbind(table, data.frame(group = key, label = label, row_count = length(values),
        finite_value_count = sum(is.finite(values)), missing_value_count = sum(is.na(values)),
        infinite_value_count = sum(is.infinite(values)), mean = stats$mean,
        median = stats$median, sd = stats$sd))
    }
    output[[name]] <- table
  }
  output
}

# Return core summaries only; diagnostics require separate, explicit calls.
profile_time_series <- function(data, time_col, value_col, expected_frequency = NULL,
                                grid_start = NULL, grid_end = NULL, tz = NULL,
                                calendar_groups = c("month", "weekday"),
                                max_grid_size = 1000000L) {
  input <- .tsp_input(data, time_col, value_col, tz)
  .tsp_integer(max_grid_size, "max_grid_size", 1)
  start <- .tsp_boundary(grid_start, "grid_start", input$time, input$tz)
  end <- .tsp_boundary(grid_end, "grid_end", input$time, input$tz)
  if (!is.null(start) && !is.null(end) && start > end) .tsp_error("grid_start must be no later than grid_end.")
  # Pass a local time-column copy so functions without tz use the effective zone.
  local <- data.frame(time = input$time, value = input$value)
  names(local) <- c(time_col, value_col)
  gaps <- if (is.null(expected_frequency)) {
    .tsp_gap_result(input$time, NULL, start, end, "expected_frequency_not_supplied")
  } else {
    find_time_gaps(local, time_col, expected_frequency, start, end, input$tz, max_grid_size)
  }
  list(overview = series_overview(local, time_col, value_col),
       time_index = check_time_index(local, time_col), gaps = gaps,
       values = summarise_values(local, value_col),
       calendar = summarise_calendar(local, time_col, value_col, calendar_groups, input$tz),
       settings = list(time_col = time_col, value_col = value_col,
         expected_frequency = expected_frequency, time_zone = input$tz,
         calendar_groups = calendar_groups,
         grid_start = gaps$summary$grid_start, grid_end = gaps$summary$grid_end,
         max_grid_size = max_grid_size))
}

.tsp_has_package <- function(package) requireNamespace(package, quietly = TRUE)

.tsp_plot_dependency <- function() {
  if (!.tsp_has_package("ggplot2")) {
    .tsp_error('plot_series requires ggplot2; install it with install.packages("ggplot2").')
  }
}

.tsp_time_scale <- function(time, tz) {
  if (inherits(time, "Date")) ggplot2::scale_x_date() else
    ggplot2::scale_x_datetime(timezone = tz)
}

# Return a plot, without drawing it. Lines never cross absent or nonfinite slots.
plot_series <- function(data, time_col, value_col, expected_frequency = NULL, tz = NULL) {
  input <- .tsp_input(data, time_col, value_col, tz)
  time <- input$time
  value <- input$value
  anchor <- NULL
  aligned <- FALSE
  if (!is.null(expected_frequency)) {
    .tsp_frequency(expected_frequency, time)
    valid_times <- time[!is.na(time)]
    if (length(valid_times)) {
      anchor <- min(valid_times)
      valid_anchor <- !expected_frequency %in% c("monthly", "quarterly", "yearly") ||
        (format(anchor, "%d") == "01" && as.numeric(anchor) == floor(as.numeric(anchor)))
      offsets <- .tsp_offset(valid_times, anchor, expected_frequency)
      aligned <- valid_anchor && all(!is.na(offsets) & offsets == floor(offsets))
    }
  }
  .tsp_plot_dependency()
  keep <- !is.na(time) & is.finite(value)
  points <- data.frame(timestamp = time[keep], value = value[keep])
  points <- points[order(points$timestamp), , drop = FALSE]
  rownames(points) <- NULL
  lines <- aligned && !anyDuplicated(time[!is.na(time)])
  caption <- paste0("Omitted ", sum(!keep), " rows: ", sum(is.na(time)),
    " with missing times; ", sum(!is.na(time) & !is.finite(value)),
    " with valid times and nonfinite values. ",
    if (lines) "Lines stop at absent or nonfinite slots." else
      "Points only: no unique, aligned frequency grid established.")
  plot <- ggplot2::ggplot(points, ggplot2::aes(x = timestamp, y = value)) +
    ggplot2::geom_point() + .tsp_time_scale(time, input$tz) +
    ggplot2::labs(x = time_col, y = value_col, caption = caption)
  if (lines && nrow(points)) {
    slot <- .tsp_offset(points$timestamp, anchor, expected_frequency)
    points$segment <- cumsum(c(TRUE, diff(slot) != 1))
    # Single points need no line and would otherwise cause ggplot warnings.
    sizes <- table(points$segment)
    segments <- points[as.character(points$segment) %in% names(sizes[sizes > 1L]), , drop = FALSE]
    plot <- plot + ggplot2::geom_line(data = segments, ggplot2::aes(group = segment))
  }
  plot
}

.tsp_diagnostic <- function(settings, reason = NULL, result = NULL) {
  list(status = if (is.null(reason)) "ok" else "skipped", reason = reason,
       settings = settings, result = result)
}

.tsp_eligibility <- function(data, time_col, value_col, expected_frequency, tz) {
  input <- .tsp_input(data, time_col, value_col, tz)
  .tsp_frequency(expected_frequency, input$time)
  order <- order(input$time, na.last = TRUE)
  settings <- list(time_col = time_col, value_col = value_col,
    expected_frequency = expected_frequency, time_zone = input$tz,
    observation_count = length(input$value), observation_count_used = 0L,
    ordering = "chronological", sorted = FALSE)
  reason <- NULL
  if (anyNA(input$time)) reason <- "missing_times"
  else if (anyDuplicated(input$time)) reason <- "duplicate_times"
  else if (!length(input$time)) reason <- "no_observations"
  if (is.null(reason)) {
    # A complete unique series cannot need more grid slots than its row count.
    # This guard also avoids allocating a huge grid for a very sparse series.
    gaps <- tryCatch(find_time_gaps(data, time_col, expected_frequency, tz = input$tz,
                                    max_grid_size = max(1L, length(input$time))),
      error = function(e) {
        if (grepl("^Expected grid exceeds max_grid_size", conditionMessage(e))) return(NULL)
        if (grepl("anchors must use the first day", conditionMessage(e))) {
          return(list(summary = list(off_grid_row_count = 1L, outside_range_row_count = 0L)))
        }
        stop(e)
      })
    if (is.null(gaps)) reason <- "missing_slots"
    else if (gaps$summary$off_grid_row_count || gaps$summary$outside_range_row_count) reason <- "off_grid_times"
    else if (gaps$summary$missing_slot_count) reason <- "missing_slots"
    else if (any(!is.finite(input$value))) reason <- "nonfinite_values"
  }
  if (is.null(reason)) {
    settings$sorted <- !identical(order, seq_along(input$time))
    input$time <- input$time[order]
    input$value <- input$value[order]
  }
  list(input = input, settings = settings, reason = reason)
}

.tsp_backend <- function(settings, compute) {
  settings$observation_count_used <- settings$observation_count
  # Warnings commonly indicate singular fits or unstable numerical results.
  tryCatch(withCallingHandlers({
    result <- compute()
    .tsp_diagnostic(settings, result = result)
  }, warning = function(w) stop(conditionMessage(w), call. = FALSE)),
  error = function(e) .tsp_diagnostic(settings, paste0("backend_failure: ", conditionMessage(e))))
}

# Return ACF/PACF tables and an exploratory plot for a complete regular series.
plot_dependence <- function(data, time_col, value_col, expected_frequency,
                            lag_max = NULL, tz = NULL) {
  if (!is.null(lag_max)) lag_max <- .tsp_integer(lag_max, "lag_max", 1)
  eligible <- .tsp_eligibility(data, time_col, value_col, expected_frequency, tz)
  n <- eligible$settings$observation_count
  if (!is.null(lag_max) && lag_max > n - 1L) .tsp_error("lag_max must be between 1 and n - 1.")
  settings <- eligible$settings
  settings$lag_max <- if (is.null(lag_max)) max(0L, min(40L, n - 1L)) else lag_max
  settings$demean <- TRUE
  settings$na_action <- "na.fail"
  if (!is.null(eligible$reason)) return(.tsp_diagnostic(settings, eligible$reason))
  if (n < 3L) return(.tsp_diagnostic(settings, "at_least_three_observations_required"))
  value <- eligible$input$value
  if (length(unique(value)) < 2L) return(.tsp_diagnostic(settings, "zero_variance"))
  if (!.tsp_has_package("ggplot2")) return(.tsp_diagnostic(settings, "missing_optional_dependency: ggplot2"))
  .tsp_backend(settings, function() {
    acf <- stats::acf(value, lag.max = settings$lag_max, plot = FALSE, na.action = stats::na.fail)
    pacf <- stats::pacf(value, lag.max = settings$lag_max, plot = FALSE, na.action = stats::na.fail)
    acf_table <- data.frame(lag = as.numeric(acf$lag), correlation = as.numeric(acf$acf))
    pacf_table <- data.frame(lag = as.numeric(pacf$lag), partial_correlation = as.numeric(pacf$acf))
    if (any(!is.finite(c(acf_table$correlation, pacf_table$partial_correlation)))) {
      stop("ACF/PACF returned nonfinite statistics.")
    }
    table <- rbind(data.frame(lag = acf_table$lag, value = acf_table$correlation, kind = "ACF"),
                   data.frame(lag = pacf_table$lag, value = pacf_table$partial_correlation, kind = "PACF"))
    bound <- stats::qnorm(.975) / sqrt(n)
    bounds <- data.frame(kind = "ACF", bound = c(-bound, bound))
    plot <- ggplot2::ggplot(table, ggplot2::aes(x = lag, y = value)) +
      ggplot2::geom_segment(ggplot2::aes(xend = lag, yend = 0)) +
      ggplot2::geom_hline(yintercept = 0) +
      ggplot2::geom_hline(data = bounds, ggplot2::aes(yintercept = bound), linetype = "dashed") +
      ggplot2::facet_wrap(~kind) + ggplot2::labs(x = "Lag (observations)", y = "Correlation",
        caption = "Dashed ACF bounds: approximate 95% white-noise reference, for exploration only.")
    list(acf = acf_table, pacf = pacf_table, acf_reference_bounds = c(-bound, bound), plot = plot)
  })
}

# Run explicit fixed-lag ADF and KPSS tests without an automatic stationarity verdict.
test_stationarity <- function(data, time_col, value_col, expected_frequency,
                               adf_lags, adf_deterministic = "drift",
                               kpss_null = "level", kpss_lags, tz = NULL) {
  if (missing(adf_lags) || missing(kpss_lags)) .tsp_error("Supply both adf_lags and kpss_lags explicitly.")
  adf_lags <- .tsp_integer(adf_lags, "adf_lags")
  kpss_lags <- .tsp_integer(kpss_lags, "kpss_lags")
  .tsp_choice(adf_deterministic, c("none", "drift", "trend"), "adf_deterministic")
  .tsp_choice(kpss_null, c("level", "trend"), "kpss_null")
  eligible <- .tsp_eligibility(data, time_col, value_col, expected_frequency, tz)
  settings <- c(eligible$settings, list(adf_lags = adf_lags,
    adf_deterministic = adf_deterministic, adf_selectlags = "Fixed",
    kpss_null = kpss_null, kpss_lags = kpss_lags,
    kpss_type = if (kpss_null == "level") "mu" else "tau"))
  if (!is.null(eligible$reason)) return(.tsp_diagnostic(settings, eligible$reason))
  n <- length(eligible$input$value)
  terms <- switch(adf_deterministic, none = 1L, drift = 2L, trend = 3L)
  # ADF loses lags+1 rows and estimates lags+terms coefficients; require residual df.
  if (n - adf_lags - 1 <= adf_lags + terms || kpss_lags >= n ||
      n <= if (kpss_null == "level") 1L else 2L) {
    return(.tsp_diagnostic(settings, "insufficient_observations_for_requested_lags_and_terms"))
  }
  if (length(unique(eligible$input$value)) < 2L) return(.tsp_diagnostic(settings, "zero_variance"))
  if (!.tsp_has_package("urca")) return(.tsp_diagnostic(settings, "missing_optional_dependency: urca"))
  settings$backend_version <- as.character(utils::packageVersion("urca"))
  .tsp_backend(settings, function() {
    # Mapping verified against urca's ur.df and ur.kpss reference documentation.
    adf <- urca::ur.df(eligible$input$value, type = adf_deterministic,
                       lags = adf_lags, selectlags = "Fixed")
    kpss <- urca::ur.kpss(eligible$input$value, type = settings$kpss_type, use.lag = kpss_lags)
    tau <- switch(adf_deterministic, none = "tau1", drift = "tau2", trend = "tau3")
    table <- data.frame(test = c("ADF", "KPSS"),
      statistic_name = c(tau, paste0("KPSS_", kpss_null)),
      statistic = c(adf@teststat[1L, tau], kpss@teststat),
      critical_1pct = c(adf@cval[tau, "1pct"], kpss@cval[1L, "1pct"]),
      critical_5pct = c(adf@cval[tau, "5pct"], kpss@cval[1L, "5pct"]),
      critical_10pct = c(adf@cval[tau, "10pct"], kpss@cval[1L, "10pct"]))
    if (any(!is.finite(table$statistic))) stop("Stationarity backend returned nonfinite statistics.")
    list(tests = table, adf = adf, kpss = kpss,
      null_hypotheses = c(ADF = "unit root", KPSS = paste(kpss_null, "stationarity")))
  })
}

# Decompose one nominated cycle additively, using unmodified finite observations.
decompose_series <- function(data, time_col, value_col, expected_frequency,
                              seasonal_period, s_window = "periodic", tz = NULL) {
  if (missing(seasonal_period)) .tsp_error("Supply seasonal_period explicitly as observations per cycle.")
  seasonal_period <- .tsp_integer(seasonal_period, "seasonal_period", 2)
  if (!identical(s_window, "periodic")) {
    s_window <- .tsp_integer(s_window, "s_window", 7)
    if (s_window %% 2L == 0L) .tsp_error("s_window must be periodic or an odd integer >= 7.")
  }
  eligible <- .tsp_eligibility(data, time_col, value_col, expected_frequency, tz)
  settings <- c(eligible$settings, list(seasonal_period = seasonal_period,
    s_window = s_window, transformation = "none", decomposition = "additive",
    robust = FALSE, inner = 2L, outer = 0L, na_action = "na.fail"))
  if (!is.null(eligible$reason)) return(.tsp_diagnostic(settings, eligible$reason))
  if (length(eligible$input$value) <= 2 * as.double(seasonal_period)) {
    return(.tsp_diagnostic(settings, "more_than_two_seasonal_periods_required"))
  }
  if (!.tsp_has_package("ggplot2")) return(.tsp_diagnostic(settings, "missing_optional_dependency: ggplot2"))
  output <- .tsp_backend(settings, function() {
    raw <- stats::stl(stats::ts(eligible$input$value, frequency = seasonal_period),
      s.window = s_window, robust = FALSE, inner = 2L, outer = 0L, na.action = stats::na.fail)
    table <- data.frame(timestamp = eligible$input$time, observed = eligible$input$value,
      trend = as.numeric(raw$time.series[, "trend"]),
      seasonal = as.numeric(raw$time.series[, "seasonal"]),
      remainder = as.numeric(raw$time.series[, "remainder"]))
    if (any(!is.finite(as.matrix(table[-1L])))) stop("STL returned nonfinite components.")
    components <- c("observed", "trend", "seasonal", "remainder")
    long <- do.call(rbind, lapply(components, function(name) data.frame(
      timestamp = table$timestamp, value = table[[name]],
      component = factor(name, levels = components))))
    plot <- ggplot2::ggplot(long, ggplot2::aes(x = timestamp, y = value)) +
      ggplot2::geom_line() + ggplot2::facet_wrap(~component, ncol = 1, scales = "free_y") +
      .tsp_time_scale(eligible$input$time, eligible$input$tz) +
      ggplot2::labs(x = time_col, y = NULL,
        caption = paste0("Additive STL: one cycle of ", seasonal_period, " observations; no transformation."))
    list(components = table, plot = plot, stl = raw)
  })
  if (output$status == "ok") {
    output$settings$backend <- list(win = output$result$stl$win,
      deg = output$result$stl$deg, jump = output$result$stl$jump,
      inner = output$result$stl$inner, outer = output$result$stl$outer,
      ts_start = c(1, 1), frequency = seasonal_period)
  }
  output
}
