# Log Analyzer -- Spinel AOT (Improved)
# Parses Combined Log Format access logs and prints a statistical report.
# Usage: ./log_analyzer_improved [logfile]   (generates synthetic data if no file given)
#
# Combined Log Format:
#   host ident user [date] "method path proto" status bytes "ref" "ua"

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

  def parse(line)
    @valid = 0
    return if line.length < 20

    # Extract host (first space-delimited token)
    space_pos = 0
    while space_pos < line.length && line[space_pos] != " "
      space_pos = space_pos + 1
    end
    return if space_pos == 0
    @host = line[0, space_pos]

    # Extract timestamp (between [ and ])
    i = space_pos + 1
    while i < line.length && line[i] != "["
      i = i + 1
    end
    return if i >= line.length

    date_start = i + 1
    i = date_start
    while i < line.length && line[i] != "]"
      i = i + 1
    end
    return if i >= line.length
    @timestamp = line[date_start, i - date_start]

    # Extract request (between first pair of quotes after timestamp)
    i = i + 1
    while i < line.length && line[i] != "\""
      i = i + 1
    end
    return if i >= line.length

    request_start = i + 1
    i = request_start
    while i < line.length && line[i] != "\""
      i = i + 1
    end
    return if i >= line.length
    request = line[request_start, i - request_start]

    # Parse request: "VERB URL PROTOCOL"
    parse_request(request)

    # Extract status code (first number after closing quote)
    i = i + 1
    while i < line.length && line[i] == " "
      i = i + 1
    end
    num_start = i
    while i < line.length && line[i] >= "0" && line[i] <= "9"
      i = i + 1
    end
    if i > num_start
      @code = line[num_start, i - num_start].to_i
    end

    # Extract bytes (next number after status)
    while i < line.length && line[i] == " "
      i = i + 1
    end
    num_start = i
    while i < line.length && line[i] >= "0" && line[i] <= "9"
      i = i + 1
    end
    if i > num_start
      @size = line[num_start, i - num_start].to_i
    end

    @valid = 1
  end

  private

  def parse_request(request)
    # Find first space (separates verb from URL)
    space_pos = 0
    while space_pos < request.length && request[space_pos] != " "
      space_pos = space_pos + 1
    end

    if space_pos > 0 && space_pos < request.length
      @http_verb = request[0, space_pos]
      rest = request[space_pos + 1, request.length - space_pos - 1]

      # Find second space (separates URL from protocol)
      proto_pos = 0
      while proto_pos < rest.length && rest[proto_pos] != " "
        proto_pos = proto_pos + 1
      end

      if proto_pos > 0
        @url = rest[0, proto_pos]
      else
        @url = rest
      end
    end
  end
end

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

  def record(lp)
    @total = @total + 1

    classify_status(lp.code)
    increment_hash(@status_counts, lp.code.to_s)

    record_verb(lp.http_verb)
    record_url(lp.url, lp.size)

    @total_bytes = @total_bytes + lp.size
    record_hour(lp.timestamp)
    increment_hash(@host_counts, lp.host)
  end

  def report
    puts "========================================"
    puts "  ACCESS LOG REPORT"
    puts "========================================"
    puts ""
    puts "Total requests:  " + @total.to_s
    puts "Total bytes:     " + format_bytes(@total_bytes)
    puts "Errors (5xx):    " + @errors.to_s + " (" + percent(@errors, @total) + ")"
    puts "Redirects (3xx): " + @redirects.to_s + " (" + percent(@redirects, @total) + ")"
    puts ""

    print_section("Status Codes", @status_counts, 10, true)
    print_section("HTTP Methods", @verb_counts, 5, true)
    print_section("Top 15 URLs by Hits", @url_counts, 15, false)
    print_section("Top 10 URLs by Bandwidth", @url_bytes, 10, false, true)
    print_hourly_stats
    print_section("Top 10 Hosts", @host_counts, 10, false)
    puts "========================================"
  end

  private

  def classify_status(code)
    if code >= 500
      @errors = @errors + 1
    elsif code >= 300 && code < 400
      @redirects = @redirects + 1
    end
  end

  def increment_hash(hash, key)
    if hash.has_key?(key)
      hash[key] = hash[key] + 1
    else
      hash[key] = 1
    end
  end

  def record_verb(verb)
    if verb.length > 0
      increment_hash(@verb_counts, verb)
    end
  end

  def record_url(url, size)
    if url.length > 0
      increment_hash(@url_counts, url)
      if @url_bytes.has_key?(url)
        @url_bytes[url] = @url_bytes[url] + size
      else
        @url_bytes[url] = size
      end
    end
  end

  def record_hour(timestamp)
    # Extract hour from: 10/Oct/2000:13:55:36 -0700
    colon_pos = 0
    while colon_pos < timestamp.length && timestamp[colon_pos] != ":"
      colon_pos = colon_pos + 1
    end

    if colon_pos + 3 <= timestamp.length
      hour = timestamp[colon_pos + 1, 2]
      increment_hash(@hour_counts, hour)
    end
  end

  def percent(part, whole)
    if whole == 0
      "0.0%"
    else
      val = part * 1000 / whole
      (val / 10).to_s + "." + (val % 10).to_s + "%"
    end
  end

  def format_bytes(bytes)
    if bytes >= 1073741824
      (bytes / 1073741824).to_s + " GB"
    elsif bytes >= 1048576
      (bytes / 1048576).to_s + " MB"
    elsif bytes >= 1024
      (bytes / 1024).to_s + " KB"
    else
      bytes.to_s + " B"
    end
  end

  # Sort hash by value descending, return top n keys
  def top_keys(hash, n)
    keys = hash.keys
    selection_sort_descending(keys, hash, n)
    result = []
    i = 0
    while i < n && i < keys.length
      result.push(keys[i])
      i = i + 1
    end
    result
  end

  def selection_sort_descending(keys, hash, limit)
    i = 0
    while i < keys.length && i < limit
      best = i
      j = i + 1
      while j < keys.length
        if hash[keys[j]] > hash[keys[best]]
          best = j
        end
        j = j + 1
      end
      if best != i
        tmp = keys[i]
        keys[i] = keys[best]
        keys[best] = tmp
      end
      i = i + 1
    end
  end

  def print_section(title, hash, limit, show_percent, use_bytes_format = false)
    puts "--- " + title + " ---"
    top = top_keys(hash, limit)
    i = 0
    while i < top.length
      key = top[i]
      value = hash[key]
      if use_bytes_format
        value_str = format_bytes(value)
      else
        value_str = value.to_s
      end

      if show_percent
        puts "  " + key + ": " + value_str + " (" + percent(value, @total) + ")"
      else
        puts "  " + value_str + "  " + key
      end
      i = i + 1
    end
    puts ""
  end

  def print_hourly_stats
    puts "--- Requests by Hour ---"
    hours = @hour_counts.keys
    sort_hours_numerically(hours)

    max_count = find_max_count(hours)

    hours.each do |hour|
      count = @hour_counts[hour]
      bar = build_bar(count, max_count)
      label = format_hour_label(hour)
      puts "  " + label + " |" + bar + "| " + count.to_s
    end
    puts ""
  end

  def sort_hours_numerically(hours)
    i = 0
    while i < hours.length
      j = i + 1
      while j < hours.length
        if hours[j].to_i < hours[i].to_i
          tmp = hours[i]
          hours[i] = hours[j]
          hours[j] = tmp
        end
        j = j + 1
      end
      i = i + 1
    end
  end

  def find_max_count(hours)
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
    bar_len = 0
    if max_count > 0
      bar_len = count * 40 / max_count
    end
    bar = ""
    i = 0
    while i < bar_len
      bar = bar + "#"
      i = i + 1
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
  # Generate synthetic log data
  verbs = ["GET", "GET", "GET", "GET", "POST", "PUT", "DELETE", "HEAD"]
  urls = ["/", "/index.html", "/api/users", "/api/posts", "/static/app.js",
          "/static/style.css", "/login", "/api/search", "/favicon.ico",
          "/api/health", "/dashboard", "/api/orders", "/robots.txt"]
  codes = [200, 200, 200, 200, 200, 200, 301, 302, 304, 404, 500]
  hosts = ["10.0.0.1", "10.0.0.2", "192.168.1.1", "172.16.0.5",
           "10.0.0.3", "10.0.0.1", "10.0.0.1", "192.168.1.2"]
  uas = ["Mozilla/5.0", "curl/8.1", "bot/2.1"]

  puts "(No log file provided -- analyzing 10000 synthetic entries)"
  puts ""

  seed = 12345
  n = 0
  while n < 10000
    seed = (seed * 1103515245 + 12345) % 2147483648
    h = hosts[seed % hosts.length]
    seed = (seed * 1103515245 + 12345) % 2147483648
    v = verbs[seed % verbs.length]
    seed = (seed * 1103515245 + 12345) % 2147483648
    u = urls[seed % urls.length]
    seed = (seed * 1103515245 + 12345) % 2147483648
    c = codes[seed % codes.length]
    seed = (seed * 1103515245 + 12345) % 2147483648
    b = 200 + seed % 50000
    seed = (seed * 1103515245 + 12345) % 2147483648
    hour = seed % 24
    seed = (seed * 1103515245 + 12345) % 2147483648
    ua = uas[seed % uas.length]

    hour_s = hour.to_s
    if hour < 10
      hour_s = "0" + hour.to_s
    end
    day = 1 + n % 28
    day_s = day.to_s
    if day < 10
      day_s = "0" + day.to_s
    end

    line = h + " - - [" + day_s + "/May/2025:" + hour_s + ":30:00 +0000] \"" + v + " " + u + " HTTP/1.1\" " + c.to_s + " " + b.to_s + " \"-\" \"" + ua + "\""

    parser.parse(line)
    if parser.valid == 1
      stats.record(parser)
    end
    n = n + 1
  end
end

stats.report
