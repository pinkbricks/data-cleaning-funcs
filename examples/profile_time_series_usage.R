# Run from the repository root: Rscript examples/basic_usage.R
source("time_series_profiler.R")

# One series with a missing day, a repeated timestamp, and a missing value.
visits <- data.frame(
  date = as.Date(c("2024-01-01", "2024-01-02", "2024-01-04", "2024-01-04", "2024-01-05")),
  visits = c(12, NA, 18, 20, 16)
)
report <- profile_time_series(visits, "date", "visits", expected_frequency = "daily")
print(report$time_index$summary)
print(report$gaps$missing_times)
print(report$values)

# Diagnostics explain why they cannot use this incomplete series.
dependence <- plot_dependence(visits, "date", "visits", expected_frequency = "daily")
print(dependence[c("status", "reason")])

# Create a separate complete synthetic series for the optional diagnostics.
i <- seq_len(72)
monthly <- data.frame(
  month = seq(as.Date("2019-01-01"), by = "month", length.out = length(i)),
  value = 30 + i * .15 + 4 * sin(2 * pi * i / 12) + cos(i * 1.7)
)
dependence <- plot_dependence(monthly, "month", "value", "monthly", lag_max = 18)
stationarity <- test_stationarity(
  monthly, "month", "value", "monthly",
  adf_lags = 2, adf_deterministic = "trend", kpss_null = "trend", kpss_lags = 3
)
decomposition <- decompose_series(monthly, "month", "value", "monthly", seasonal_period = 12)
print(stationarity[c("status", "reason")])
if (stationarity$status == "ok") print(stationarity$result$tests)

# In an interactive session, choose which plots to display yourself:
# print(plot_series(visits, "date", "visits", "daily"))
# if (dependence$status == "ok") print(dependence$result$plot)
# if (decomposition$status == "ok") print(decomposition$result$plot)
