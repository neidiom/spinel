# Log Analyzer -- Spinel AOT
# Parses Combined Log Format access logs and prints a statistical report.
# Usage: ./log_analyzer [logfile]   (generates synthetic data if no file given)
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

    # Extract host
    sp = 0
    while sp < line.length && line[sp] != " "
      sp = sp + 1
    end
    return if sp == 0
    @host = line[0, sp]

    # Skip to [ for date
    i = sp + 1
    while i < line.length && line[i] != "["
      i = i + 1
    end
    return if i >= line.length

    dstart = i + 1
    i = dstart
    while i < line.length && line[i] != "]"
      i = i + 1
    end
    return if i >= line.length
    @timestamp = line[dstart, i - dstart]

    # Skip to first " for request
    i = i + 1
    while i < line.length && line[i] != "\""
      i = i + 1
    end
    return if i >= line.length

    rstart = i + 1
    i = rstart
    while i < line.length && line[i] != "\""
      i = i + 1
    end
    return if i >= line.length
    request = line[rstart, i - rstart]

    # Split request: verb URL proto
    msp = 0
    while msp < request.length && request[msp] != " "
      msp = msp + 1
    end
    if msp > 0 && msp < request.length
      @http_verb = request[0, msp]
      rest = request[msp + 1, request.length - msp - 1]
      psp = 0
      while psp < rest.length && rest[psp] != " "
        psp = psp + 1
      end
      if psp > 0
        @url = rest[0, psp]
      else
        @url = rest
      end
    end

    # After closing quote, find status
    i = i + 1
    while i < line.length && line[i] == " "
      i = i + 1
    end
    nstart = i
    while i < line.length && line[i] >= "0" && line[i] <= "9"
      i = i + 1
    end
    if i > nstart
      @code = line[nstart, i - nstart].to_i
    end

    # Skip space, read bytes
    while i < line.length && line[i] == " "
      i = i + 1
    end
    bstart = i
    while i < line.length && line[i] >= "0" && line[i] <= "9"
      i = i + 1
    end
    if i > bstart
      @size = line[bstart, i - bstart].to_i
    end

    @valid = 1
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

    s = lp.code
    if s >= 500
      @errors = @errors + 1
    elsif s >= 300 && s < 400
      @redirects = @redirects + 1
    end

    sk = s.to_s
    if @status_counts.has_key?(sk)
      @status_counts[sk] = @status_counts[sk] + 1
    else
      @status_counts[sk] = 1
    end

    v = lp.http_verb
    if v.length > 0
      if @verb_counts.has_key?(v)
        @verb_counts[v] = @verb_counts[v] + 1
      else
        @verb_counts[v] = 1
      end
    end

    u = lp.url
    if u.length > 0
      if @url_counts.has_key?(u)
        @url_counts[u] = @url_counts[u] + 1
      else
        @url_counts[u] = 1
      end
      if @url_bytes.has_key?(u)
        @url_bytes[u] = @url_bytes[u] + lp.size
      else
        @url_bytes[u] = lp.size
      end
    end

    @total_bytes = @total_bytes + lp.size

    # Extract hour from timestamp: 10/Oct/2000:13:55:36 -0700
    ts = lp.timestamp
    cpos = 0
    while cpos < ts.length && ts[cpos] != ":"
      cpos = cpos + 1
    end
    if cpos + 3 <= ts.length
      hour_str = ts[cpos + 1, 2]
      hk = hour_str
      if @hour_counts.has_key?(hk)
        @hour_counts[hk] = @hour_counts[hk] + 1
      else
        @hour_counts[hk] = 1
      end
    end

    h = lp.host
    if @host_counts.has_key?(h)
      @host_counts[h] = @host_counts[h] + 1
    else
      @host_counts[h] = 1
    end
  end

  def pct(part, whole)
    if whole == 0
      "0.0%"
    else
      val = part * 1000 / whole
      int_part = val / 10
      dec_part = val - int_part * 10
      int_part.to_s + "." + dec_part.to_s + "%"
    end
  end

  def fmt_bytes(b)
    if b >= 1073741824
      (b / 1073741824).to_s + " GB"
    elsif b >= 1048576
      (b / 1048576).to_s + " MB"
    elsif b >= 1024
      (b / 1024).to_s + " KB"
    else
      b.to_s + " B"
    end
  end

  # Sort a hash by value descending, return top n keys as array
  def sorted_top(hash, n)
    keys = hash.keys
    # Selection sort descending
    i = 0
    while i < keys.length && i < n
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
    result = []
    i = 0
    while i < n && i < keys.length
      result.push(keys[i])
      i = i + 1
    end
    result
  end

  def report
    puts "========================================"
    puts "  ACCESS LOG REPORT"
    puts "========================================"
    puts ""
    puts "Total requests:  " + @total.to_s
    puts "Total bytes:     " + fmt_bytes(@total_bytes)
    puts "Errors (5xx):    " + @errors.to_s + " (" + pct(@errors, @total) + ")"
    puts "Redirects (3xx): " + @redirects.to_s + " (" + pct(@redirects, @total) + ")"
    puts ""

    puts "--- Status Codes ---"
    top = sorted_top(@status_counts, 10)
    i = 0
    while i < top.length
      k = top[i]
      puts "  " + k + ": " + @status_counts[k].to_s + " (" + pct(@status_counts[k], @total) + ")"
      i = i + 1
    end
    puts ""

    puts "--- HTTP Methods ---"
    top = sorted_top(@verb_counts, 5)
    i = 0
    while i < top.length
      k = top[i]
      puts "  " + k + ": " + @verb_counts[k].to_s + " (" + pct(@verb_counts[k], @total) + ")"
      i = i + 1
    end
    puts ""

    puts "--- Top 15 URLs by Hits ---"
    top = sorted_top(@url_counts, 15)
    i = 0
    while i < top.length
      k = top[i]
      puts "  " + @url_counts[k].to_s + "  " + k
      i = i + 1
    end
    puts ""

    puts "--- Top 10 URLs by Bandwidth ---"
    top = sorted_top(@url_bytes, 10)
    i = 0
    while i < top.length
      k = top[i]
      puts "  " + fmt_bytes(@url_bytes[k]) + "  " + k
      i = i + 1
    end
    puts ""

    puts "--- Requests by Hour ---"
    hours = @hour_counts.keys
    # Sort hours numerically
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
    max_h = 0
    i = 0
    while i < hours.length
      c = @hour_counts[hours[i]]
      if c > max_h
        max_h = c
      end
      i = i + 1
    end
    i = 0
    while i < hours.length
      c = @hour_counts[hours[i]]
      bar_len = 0
      if max_h > 0
        bar_len = c * 40 / max_h
      end
      bar = ""
      j = 0
      while j < bar_len
        bar = bar + "#"
        j = j + 1
      end
      label = hours[i] + ":00"
      if hours[i].length == 1
        label = "0" + hours[i] + ":00"
      end
      puts "  " + label + " |" + bar + "| " + c.to_s
      i = i + 1
    end
    puts ""

    puts "--- Top 10 Hosts ---"
    top = sorted_top(@host_counts, 10)
    i = 0
    while i < top.length
      k = top[i]
      puts "  " + @host_counts[k].to_s + "  " + k
      i = i + 1
    end
    puts ""
    puts "========================================"
  end
end

# --- Main ---

lp = LineParser.new
st = Stats.new

if ARGV.length > 0
  filename = ARGV[0]
  File.open(filename, "r") do |f|
    f.each_line do |line|
      lp.parse(line.chomp)
      if lp.valid == 1
        st.record(lp)
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

    lp.parse(line)
    if lp.valid == 1
      st.record(lp)
    end
    n = n + 1
  end
end

st.report
