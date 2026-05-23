#!/usr/bin/env ruby
# Rigorous benchmark: Spinel native vs CRuby variants
# Uses 100K entries to make computation dominate startup

require 'benchmark'

N = 15
WARMUP = 5

bin = "./log_analyzer"
spinel_rb = "examples/log_analyzer.rb"
idiomatic_rb = "examples/log_analyzer_idiomatic.rb"

unless File.exist?(bin)
  puts "ERROR: #{bin} not found. Run ./spinel #{spinel_rb} -o log_analyzer first"
  exit 1
end

def calc_median(times)
  sorted = times.sort
  mid = sorted.length / 2
  sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
end

def bench(cmd, n, warmup)
  warmup.times { system("#{cmd} > /dev/null 2>&1") }
  times = []
  n.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    system("#{cmd} > /dev/null 2>&1")
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    times << (t1 - t0) * 1000.0
  end
  times
end

# Generate a large synthetic log file so all variants read the same data
puts "Generating 100K synthetic log entries..."
log_gen_script = "/tmp/spinel_gen_log.rb"
File.write(log_gen_script, <<~'RUBY')
  verbs = ["GET", "GET", "GET", "GET", "POST", "PUT", "DELETE", "HEAD"]
  urls = ["/", "/index.html", "/api/users", "/api/posts", "/static/app.js",
          "/static/style.css", "/login", "/api/search", "/favicon.ico",
          "/api/health", "/dashboard", "/api/orders", "/robots.txt"]
  codes = [200, 200, 200, 200, 200, 200, 301, 302, 304, 404, 500]
  hosts = ["10.0.0.1", "10.0.0.2", "192.168.1.1", "172.16.0.5",
           "10.0.0.3", "10.0.0.1", "10.0.0.1", "192.168.1.2"]
  uas = ["Mozilla/5.0", "curl/8.1", "bot/2.1"]
  seed = 12345
  n = 100_000
  File.open("/tmp/spinel_bench_log.txt", "w") do |f|
    n.times do |i|
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
      day_s = format("%02d", 1 + i % 28)
      hour_s = format("%02d", hour)
      f.puts "#{h} - - [#{day_s}/May/2025:#{hour_s}:30:00 +0000] \"#{v} #{u} HTTP/1.1\" #{c} #{b} \"-\" \"#{ua}\""
    end
  end
RUBY
system("ruby #{log_gen_script}")

puts "Log file: #{File.size('/tmp/spinel_bench_log.txt') / 1024}KB"
puts ""

results = {}

puts "1/5  Spinel native binary (100K entries from file)..."
results[:spinel] = bench("#{bin} /tmp/spinel_bench_log.txt", N, WARMUP)

puts "2/5  CRuby (Spinel subset, 100K entries from file)..."
results[:cruby] = bench("ruby #{spinel_rb} /tmp/spinel_bench_log.txt", N, WARMUP)

puts "3/5  CRuby + YJIT (Spinel subset, 100K entries from file)..."
results[:cruby_yjit] = bench("ruby --yjit #{spinel_rb} /tmp/spinel_bench_log.txt", N, WARMUP)

puts "4/5  CRuby idiomatic (100K entries from file)..."
results[:idiomatic] = bench("ruby #{idiomatic_rb} /tmp/spinel_bench_log.txt", N, WARMUP)

puts "5/5  CRuby + YJIT idiomatic (100K entries from file)..."
results[:idiomatic_yjit] = bench("ruby --yjit #{idiomatic_rb} /tmp/spinel_bench_log.txt", N, WARMUP)

puts ""
puts "=" * 78
puts "  LOG ANALYZER BENCHMARK (100K entries, #{N} runs, #{WARMUP} warmup)"
puts "=" * 78
puts ""

ruby_version = `ruby --version`.strip
puts "Ruby: #{ruby_version}"
puts ""

# Base is idiomatic CRuby since that's what a normal Ruby dev would write
base_idiomatic = calc_median(results[:idiomatic])
base_spinel_subset = calc_median(results[:cruby])

printf "  %-32s %8s %10s %10s\n", "Variant", "Best", "Median", "Speedup"
printf "  %-32s %8s %10s %10s\n", "-" * 32, "-" * 8, "-" * 10, "-" * 10

results.each do |name, times|
  best = times.min
  med = calc_median(times)
  speedup = base_idiomatic / med
  label = case name
    when :spinel         then "Spinel native binary"
    when :cruby          then "CRuby (while-loop subset)"
    when :cruby_yjit    then "CRuby + YJIT (while-loop subset)"
    when :idiomatic      then "CRuby (idiomatic Ruby)"
    when :idiomatic_yjit then "CRuby + YJIT (idiomatic Ruby)"
    end
  printf "  %-32s %5.1fms %7.1fms %8.1fx\n", label, best, med, speedup
end

puts ""
puts "Speedup vs idiomatic CRuby (median):"
spinel_vs_idio = base_idiomatic / calc_median(results[:spinel])
spinel_vs_yjit = calc_median(results[:idiomatic_yjit]) / calc_median(results[:spinel])
printf "  Spinel vs idiomatic CRuby:      %.1fx faster\n", spinel_vs_idio
printf "  Spinel vs idiomatic CRuby+YJIT: %.1fx faster\n", spinel_vs_yjit

puts ""
puts "Speedup vs same algorithm (Spinel subset):"
spinel_vs_cruby = calc_median(results[:cruby]) / calc_median(results[:spinel])
spinel_vs_yjit2 = calc_median(results[:cruby_yjit]) / calc_median(results[:spinel])
printf "  Spinel vs CRuby (same code):        %.1fx faster\n", spinel_vs_cruby
printf "  Spinel vs CRuby+YJIT (same code):   %.1fx faster\n", spinel_vs_yjit2

puts ""
puts "Raw times (ms):"
printf "  %-20s  %6s  %6s  %6s  %6s\n", "Variant", "min", "med", "max", "stdev"
results.each do |name, times|
  label = name.to_s.ljust(20)
  mn = times.min
  med = calc_median(times)
  mx = times.max
  mean = times.sum / times.length
  variance = times.map { |t| (t - mean) ** 2 }.sum / times.length
  stdev = Math.sqrt(variance)
  printf "  %-20s  %6.1f  %6.1f  %6.1f  %6.1f\n", label, mn, med, mx, stdev
end
