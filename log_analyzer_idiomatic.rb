# Log Analyzer -- Idiomatic Ruby
# Parses Combined Log Format access logs and prints a statistical report.
# Usage: ruby log_analyzer_idiomatic.rb [logfile]
#
# Combined Log Format:
#   host ident user [date] "method path proto" status bytes "ref" "ua"

LOG_PATTERN = %r{
  ^
  (\S+)               \s+   # host
  \S+                 \s+   # ident
  \S+                 \s+   # user
  \[([^\]]+)\]        \s+   # date
  "(\S+)\s+(\S+)\s+(\S+)" \s+  # method path proto
  (\d{3})             \s+   # status
  (\d+)               \s*   # bytes
}x

Line = Struct.new(:host, :http_verb, :url, :code, :size, :timestamp)

def parse_line(line)
  m = line.match(LOG_PATTERN)
  return nil unless m

  Line.new(m[1], m[3], m[4], m[6].to_i, m[7].to_i, m[2])
end

def format_bytes(b)
  case b
  when ->(x) { x >= 1_073_741_824 } then "#{b / 1_073_741_824} GB"
  when ->(x) { x >= 1_048_576 }     then "#{b / 1_048_576} MB"
  when ->(x) { x >= 1_024 }         then "#{b / 1_024} KB"
  else                                    "#{b} B"
  end
end

def pct(part, whole)
  return "0.0%" if whole.zero?
  val = part * 1000 / whole
  "#{val / 10}.#{val % 10}%"
end

def top_n(hash, n)
  hash.sort_by { |_, v| -v }.first(n)
end

def generate_synthetic(n)
  verbs = ["GET", "GET", "GET", "GET", "POST", "PUT", "DELETE", "HEAD"]
  urls = ["/", "/index.html", "/api/users", "/api/posts", "/static/app.js",
          "/static/style.css", "/login", "/api/search", "/favicon.ico",
          "/api/health", "/dashboard", "/api/orders", "/robots.txt"]
  codes = [200, 200, 200, 200, 200, 200, 301, 302, 304, 404, 500]
  hosts = ["10.0.0.1", "10.0.0.2", "192.168.1.1", "172.16.0.5",
           "10.0.0.3", "10.0.0.1", "10.0.0.1", "192.168.1.2"]
  uas = ["Mozilla/5.0", "curl/8.1", "bot/2.1"]

  seed = 12345
  n.times.map do |i|
    seed = (seed * 1103515245 + 12345) % 2_147_483_648
    h = hosts[seed % hosts.length]
    seed = (seed * 1103515245 + 12345) % 2_147_483_648
    v = verbs[seed % verbs.length]
    seed = (seed * 1103515245 + 12345) % 2_147_483_648
    u = urls[seed % urls.length]
    seed = (seed * 1103515245 + 12345) % 2_147_483_648
    c = codes[seed % codes.length]
    seed = (seed * 1103515245 + 12345) % 2_147_483_648
    b = 200 + seed % 50000
    seed = (seed * 1103515245 + 12345) % 2_147_483_648
    hour = seed % 24
    seed = (seed * 1103515245 + 12345) % 2_147_483_648
    ua = uas[seed % uas.length]

    day_s = format("%02d", 1 + i % 28)
    hour_s = format("%02d", hour)

    "#{h} - - [#{day_s}/May/2025:#{hour_s}:30:00 +0000] \"#{v} #{u} HTTP/1.1\" #{c} #{b} \"-\" \"#{ua}\""
  end
end

def report(status_counts, verb_counts, url_counts, url_bytes, hour_counts, host_counts, total, errors, redirects, total_bytes)
  puts "========================================"
  puts "  ACCESS LOG REPORT"
  puts "========================================"
  puts ""
  puts "Total requests:  #{total}"
  puts "Total bytes:     #{format_bytes(total_bytes)}"
  puts "Errors (5xx):    #{errors} (#{pct(errors, total)})"
  puts "Redirects (3xx): #{redirects} (#{pct(redirects, total)})"
  puts ""

  puts "--- Status Codes ---"
  top_n(status_counts, 10).each { |k, v| puts "  #{k}: #{v} (#{pct(v, total)})" }
  puts ""

  puts "--- HTTP Methods ---"
  top_n(verb_counts, 5).each { |k, v| puts "  #{k}: #{v} (#{pct(v, total)})" }
  puts ""

  puts "--- Top 15 URLs by Hits ---"
  top_n(url_counts, 15).each { |k, v| puts "  #{v}  #{k}" }
  puts ""

  puts "--- Top 10 URLs by Bandwidth ---"
  top_n(url_bytes, 10).each { |k, v| puts "  #{format_bytes(v)}  #{k}" }
  puts ""

  puts "--- Requests by Hour ---"
  max_h = hour_counts.values.max.to_f
  hour_counts.keys.sort_by(&:to_i).each do |hk|
    c = hour_counts[hk]
    bar_len = max_h > 0 ? (c * 40 / max_h).to_i : 0
    bar = "#" * bar_len
    label = hk.length == 1 ? "0#{hk}:00" : "#{hk}:00"
    puts "  #{label} |#{bar}| #{c}"
  end
  puts ""

  puts "--- Top 10 Hosts ---"
  top_n(host_counts, 10).each { |k, v| puts "  #{v}  #{k}" }
  puts ""
  puts "========================================"
end

# --- Main ---

lines = if ARGV.length > 0
  File.readlines(ARGV[0]).map(&:chomp)
else
  puts "(No log file provided -- analyzing 10000 synthetic entries)"
  puts ""
  generate_synthetic(10_000)
end

status_counts = Hash.new(0)
verb_counts = Hash.new(0)
url_counts = Hash.new(0)
url_bytes = Hash.new(0)
hour_counts = Hash.new(0)
host_counts = Hash.new(0)
total = 0
errors = 0
redirects = 0
total_bytes = 0

lines.each do |line|
  entry = parse_line(line)
  next unless entry

  total += 1
  errors += 1 if entry.code >= 500
  redirects += 1 if entry.code >= 300 && entry.code < 400

  status_counts[entry.code.to_s] += 1
  verb_counts[entry.http_verb] += 1 unless entry.http_verb.empty?
  url_counts[entry.url] += 1 unless entry.url.empty?
  url_bytes[entry.url] += entry.size unless entry.url.empty?

  total_bytes += entry.size

  if (colon = entry.timestamp.index(":")) && colon + 3 <= entry.timestamp.length
    hour = entry.timestamp[colon + 1, 2]
    hour_counts[hour] += 1
  end

  host_counts[entry.host] += 1
end

report(status_counts, verb_counts, url_counts, url_bytes, hour_counts, host_counts, total, errors, redirects, total_bytes)
