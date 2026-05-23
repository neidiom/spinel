# Log Analyzer v3 -- Spinel AOT (Maximum Idiomatic Within Constraints)
# Parses Combined Log Format access logs and prints a statistical report.
# Usage: ./log_analyzer_v3 [logfile]
#
# Combined Log Format:
#   host ident user [date] "method path proto" status bytes "ref" "ua"
#
# This version demonstrates the most Ruby-like code possible while
# remaining compilable by Spinel's static type system.

# --- Constants ---

SYNTHETIC_VERBS = ["GET", "GET", "GET", "GET", "POST", "PUT", "DELETE", "HEAD"]
SYNTHETIC_URLS = [
  "/", "/index.html", "/api/users", "/api/posts", "/static/app.js",
  "/static/style.css", "/login", "/api/search", "/favicon.ico",
  "/api/health", "/dashboard", "/api/orders", "/robots.txt"
]
SYNTHETIC_CODES = [200, 200, 200, 200, 200, 200, 301, 302, 304, 404, 500]
SYNTHETIC_HOSTS = [
  "10.0.0.1", "10.0.0.2", "192.168.1.1", "172.16.0.5",
  "10.0.0.3", "10.0.0.1", "10.0.0.1", "192.168.1.2"
]
SYNTHETIC_USER_AGENTS = ["Mozilla/5.0", "curl/8.1", "bot/2.1"]

SYNTHETIC_COUNT = 10000
RANDOM_SEED = 12345
RANDOM_MULT = 1103515245
RANDOM_ADD = 12345
RANDOM_MOD = 2147483648

BYTES_PER_KB = 1024
BYTES_PER_MB = 1048576
BYTES_PER_GB = 1073741824

# --- Line Parser ---

class LineParser
  def initialize
    @host = ""
    @http_verb = ""
    @url = ""
    @code = 0
    @size = 0
    @timestamp = ""
    @valid = 0
  end

  attr_reader :host, :http_verb, :url, :code, :size, :timestamp, :valid

  # Parse a Combined Log Format line into component fields
  def parse(line)
    @valid = 0

    # Reject lines that are obviously too short
    if line.length < 20
      return
    end

    # Extract host (first token before space)
    host_end = find_char(line, " ", 0)
    if host_end == 0
      return
    end
    @host = line[0, host_end]

    # Extract timestamp (between [ and ])
    bracket_open = find_char(line, "[", host_end)
    if bracket_open >= line.length
      return
    end

    bracket_close = find_char(line, "]", bracket_open + 1)
    if bracket_close >= line.length
      return
    end

    @timestamp = line[bracket_open + 1, bracket_close - bracket_open - 1]

    # Extract request (between first pair of quotes after timestamp)
    quote_open = find_char(line, "\"", bracket_close + 1)
    if quote_open >= line.length
      return
    end

    quote_close = find_char(line, "\"", quote_open + 1)
    if quote_close >= line.length
      return
    end

    request = line[quote_open + 1, quote_close - quote_open - 1]
    parse_request(request)

    # Extract status code and bytes (after closing quote)
    parse_status_and_bytes(line, quote_close + 1)

    @valid = 1
  end

  private

  # Find position of character starting from given index
  def find_char(str, ch, start_pos)
    pos = start_pos
    while pos < str.length && str[pos] != ch
      pos = pos + 1
    end
    pos
  end

  # Parse the request string: "VERB URL PROTOCOL"
  def parse_request(request)
    # Find first space (separates verb from rest)
    first_space = find_char(request, " ", 0)

    if first_space > 0 && first_space < request.length
      @http_verb = request[0, first_space]
      rest = request[first_space + 1, request.length - first_space - 1]

      # Find second space (separates URL from protocol)
      second_space = find_char(rest, " ", 0)

      if second_space > 0
        @url = rest[0, second_space]
      else
        @url = rest
      end
    end
  end

  # Extract status code and bytes from remainder of line
  def parse_status_and_bytes(line, start_pos)
    # Skip leading spaces
    pos = start_pos
    while pos < line.length && line[pos] == " "
      pos = pos + 1
    end

    # Read status code (digits)
    num_start = pos
    while pos < line.length && is_digit?(line[pos])
      pos = pos + 1
    end

    if pos > num_start
      @code = line[num_start, pos - num_start].to_i
    end

    # Skip spaces before bytes
    while pos < line.length && line[pos] == " "
      pos = pos + 1
    end

    # Read bytes (digits)
    num_start = pos
    while pos < line.length && is_digit?(line[pos])
      pos = pos + 1
    end

    if pos > num_start
      @size = line[num_start, pos - num_start].to_i
    end
  end

  # Check if character is a digit
  def is_digit?(ch)
    ch >= "0" && ch <= "9"
  end
end

# --- Statistics Collector ---

class Stats
  def initialize
    @total = 0
    @errors = 0
    @redirects = 0
    @total_bytes = 0
    @status_counts = {}
    @verb_counts = {}
    @url_counts = {}
    @url_bytes = {}
    @hour_counts = {}
    @host_counts = {}
  end

  # Record a parsed log entry
  def record(parser)
    @total = @total + 1

    track_status(parser.code)
    track_verb(parser.http_verb)
    track_url(parser.url, parser.size)
    track_hour(parser.timestamp)
    track_host(parser.host)

    @total_bytes = @total_bytes + parser.size
  end

  # Generate and print the full report
  def report
    print_header
    print_summary
    print_status_codes
    print_http_methods
    print_top_urls
    print_top_bandwidth
    print_hourly_distribution
    print_top_hosts
    print_footer
  end

  private

  # --- Tracking methods ---

  def track_status(code)
    if code >= 500
      @errors = @errors + 1
    elsif code >= 300 && code < 400
      @redirects = @redirects + 1
    end

    increment_hash(@status_counts, code.to_s)
  end

  def track_verb(verb)
    if verb.length > 0
      increment_hash(@verb_counts, verb)
    end
  end

  def track_url(url, size)
    if url.length > 0
      increment_hash(@url_counts, url)
      add_to_hash(@url_bytes, url, size)
    end
  end

  def track_hour(timestamp)
    # Extract hour from: 10/Oct/2000:13:55:36 -0700
    colon_pos = find_char(timestamp, ":", 0)
    if colon_pos + 3 <= timestamp.length
      hour = timestamp[colon_pos + 1, 2]
      increment_hash(@hour_counts, hour)
    end
  end

  def track_host(host)
    increment_hash(@host_counts, host)
  end

  # --- Hash helpers ---

  def increment_hash(hash, key)
    if hash.has_key?(key)
      hash[key] = hash[key] + 1
    else
      hash[key] = 1
    end
  end

  def add_to_hash(hash, key, value)
    if hash.has_key?(key)
      hash[key] = hash[key] + value
    else
      hash[key] = value
    end
  end

  # --- Formatting helpers ---

  def percent(part, whole)
    if whole == 0
      return "0.0%"
    end

    val = part * 1000 / whole
    (val / 10).to_s + "." + (val % 10).to_s + "%"
  end

  def format_bytes(bytes)
    if bytes >= BYTES_PER_GB
      (bytes / BYTES_PER_GB).to_s + " GB"
    elsif bytes >= BYTES_PER_MB
      (bytes / BYTES_PER_MB).to_s + " MB"
    elsif bytes >= BYTES_PER_KB
      (bytes / BYTES_PER_KB).to_s + " KB"
    else
      bytes.to_s + " B"
    end
  end

  # --- Sorting ---

  def top_keys(hash, count)
    keys = hash.keys
    selection_sort_descending(keys, hash, count)

    result = []
    idx = 0
    while idx < count && idx < keys.length
      result.push(keys[idx])
      idx = idx + 1
    end
    result
  end

  def selection_sort_descending(keys, hash, limit)
    idx = 0
    while idx < keys.length && idx < limit
      best = idx
      other = idx + 1

      while other < keys.length
        if hash[keys[other]] > hash[keys[best]]
          best = other
        end
        other = other + 1
      end

      if best != idx
        tmp = keys[idx]
        keys[idx] = keys[best]
        keys[best] = tmp
      end

      idx = idx + 1
    end
  end

  # --- Output sections ---

  def print_header
    puts "========================================"
    puts "  ACCESS LOG REPORT"
    puts "========================================"
    puts ""
  end

  def print_footer
    puts "========================================"
  end

  def print_summary
    puts "Total requests:  " + @total.to_s
    puts "Total bytes:     " + format_bytes(@total_bytes)
    puts "Errors (5xx):    " + @errors.to_s + " (" + percent(@errors, @total) + ")"
    puts "Redirects (3xx): " + @redirects.to_s + " (" + percent(@redirects, @total) + ")"
    puts ""
  end

  def print_status_codes
    print_key_value_section("Status Codes", @status_counts, 10, true, false)
  end

  def print_http_methods
    print_key_value_section("HTTP Methods", @verb_counts, 5, true, false)
  end

  def print_top_urls
    print_key_value_section("Top 15 URLs by Hits", @url_counts, 15, false, false)
  end

  def print_top_bandwidth
    print_key_value_section("Top 10 URLs by Bandwidth", @url_bytes, 10, false, true)
  end

  def print_top_hosts
    print_key_value_section("Top 10 Hosts", @host_counts, 10, false, false)
  end

  # Generic section printer for key-value data
  def print_key_value_section(title, hash, limit, show_percent, use_bytes)
    puts "--- " + title + " ---"
    top = top_keys(hash, limit)

    idx = 0
    while idx < top.length
      key = top[idx]
      value = hash[key]

      value_str = use_bytes ? format_bytes(value) : value.to_s

      if show_percent
        puts "  " + key + ": " + value_str + " (" + percent(value, @total) + ")"
      else
        puts "  " + value_str + "  " + key
      end

      idx = idx + 1
    end
    puts ""
  end

  def print_hourly_distribution
    puts "--- Requests by Hour ---"

    hours = @hour_counts.keys
    sort_hours_numerically(hours)

    max_count = find_maximum_count(hours)

    hours.each do |hour|
      count = @hour_counts[hour]
      bar = build_bar(count, max_count)
      label = format_hour_label(hour)
      puts "  " + label + " |" + bar + "| " + count.to_s
    end
    puts ""
  end

  def sort_hours_numerically(hours)
    idx = 0
    while idx < hours.length
      other = idx + 1
      while other < hours.length
        if hours[other].to_i < hours[idx].to_i
          tmp = hours[idx]
          hours[idx] = hours[other]
          hours[other] = tmp
        end
        other = other + 1
      end
      idx = idx + 1
    end
  end

  def find_maximum_count(hours)
    max = 0
    hours.each do |hour|
      count = @hour_counts[hour]
      if count > max
        max = count
      end
    end
    max
  end

  def build_bar(count, max_count)
    if max_count == 0
      return ""
    end

    bar_len = count * 40 / max_count
    bar = ""
    idx = 0
    while idx < bar_len
      bar = bar + "#"
      idx = idx + 1
    end
    bar
  end

  def format_hour_label(hour)
    if hour.length == 1
      "0" + hour + ":00"
    else
      hour + ":00"
    end
  end

  def find_char(str, ch, start_pos)
    pos = start_pos
    while pos < str.length && str[pos] != ch
      pos = pos + 1
    end
    pos
  end
end

# --- Synthetic Data Generator ---

class SyntheticLogGenerator
  def initialize
    @seed = RANDOM_SEED
  end

  def generate(count)
    lines = []
    idx = 0
    while idx < count
      lines.push(generate_line(idx))
      idx = idx + 1
    end
    lines
  end

  private

  def generate_line(idx)
    advance_seed
    host = SYNTHETIC_HOSTS[@seed % SYNTHETIC_HOSTS.length]

    advance_seed
    verb = SYNTHETIC_VERBS[@seed % SYNTHETIC_VERBS.length]

    advance_seed
    url = SYNTHETIC_URLS[@seed % SYNTHETIC_URLS.length]

    advance_seed
    code = SYNTHETIC_CODES[@seed % SYNTHETIC_CODES.length]

    advance_seed
    bytes = 200 + @seed % 50000

    advance_seed
    hour = @seed % 24

    advance_seed
    user_agent = SYNTHETIC_USER_AGENTS[@seed % SYNTHETIC_USER_AGENTS.length]

    day = 1 + idx % 28
    format_log_line(host, verb, url, code, bytes, hour, user_agent, day)
  end

  def advance_seed
    @seed = (@seed * RANDOM_MULT + RANDOM_ADD) % RANDOM_MOD
  end

  def format_log_line(host, verb, url, code, bytes, hour, user_agent, day)
    hour_str = pad_number(hour)
    day_str = pad_number(day)

    host + " - - [" + day_str + "/May/2025:" + hour_str + ":30:00 +0000] \"" +
      verb + " " + url + " HTTP/1.1\" " + code.to_s + " " + bytes.to_s +
      " \"-\" \"" + user_agent + "\""
  end

  def pad_number(num)
    if num < 10
      "0" + num.to_s
    else
      num.to_s
    end
  end
end

# --- Main ---

parser = LineParser.new
stats = Stats.new

if ARGV.length > 0
  filename = ARGV[0]
  File.open(filename, "r") do |f|
    f.each_line do |line|
      parser.parse(line.chomp)
      if parser.valid == 1
        stats.record(parser)
      end
    end
  end
else
  puts "(No log file provided -- analyzing " + SYNTHETIC_COUNT.to_s + " synthetic entries)"
  puts ""

  generator = SyntheticLogGenerator.new
  lines = generator.generate(SYNTHETIC_COUNT)

  idx = 0
  while idx < lines.length
    parser.parse(lines[idx])
    if parser.valid == 1
      stats.record(parser)
    end
    idx = idx + 1
  end
end

stats.report
