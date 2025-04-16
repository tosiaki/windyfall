defmodule WindyfallWeb.DateTimeHelpers do
  def format_datetime(nil), do: ""
  def format_datetime(datetime) do
    Timex.format!(datetime, "%b %d, %Y at %H:%M", :strftime)
  end

  def format_date(datetime) do
    Timex.format!(datetime, "%B %d, %Y", :strftime)
  end

  def format_time(datetime) do
    Timex.format!(datetime, "%H:%M", :strftime)
  end

  def time_ago(nil), do: "Never"
  def time_ago(datetime) do
    Timex.format!(datetime, "{relative}", :relative)
  end
end
