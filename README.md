# Log Analyzer -- Spinel AOT Demo

A Combined Log Format access log analyzer, written in two Ruby variants to demonstrate Spinel's AOT compilation and benchmark the results.

## Files

| File | Description |
|------|-------------|
| `log_analyzer.rb` | Spinel-compilable version (while-loops, character-by-character parsing) |
| `log_analyzer_idiomatic.rb` | Idiomatic Ruby version (regex, `Hash.new(0)`, `sort_by`, `each`) |
| `log_analyzer` | Pre-compiled Spinel native binary |
| `benchmark_log_analyzer.rb` | Benchmark harness comparing all variants |

## Usage

### Spinel native binary

```bash
# From the spinel project root, compile:
./spinel log_analyzer.rb -o spinel_nedim/log_analyzer

# Run on a real log file:
./log_analyzer /var/log/nginx/access.log

# Run with synthetic data (no file needed):
./log_analyzer
```

### CRuby (either version)

```bash
ruby spinel_nedim/log_analyzer.rb /var/log/nginx/access.log
ruby spinel_nedim/log_analyzer_idiomatic.rb /var/log/nginx/access.log
```

Both Ruby files produce byte-identical output for the same input.

## Benchmark

```bash
ruby spinel_nedim/benchmark_log_analyzer.rb
```

This generates a 100K-line synthetic log file and benchmarks five variants: Spinel native, CRuby (both versions), and CRuby + YJIT (both versions). 15 runs, 5 warmup, median reported.

### Results (100K entries, Ruby 4.0.1)

| Variant | Median | vs Idiomatic CRuby |
|----------|--------|---------------------|
| Spinel native binary | 122ms | **3.2x faster** |
| CRuby + YJIT (idiomatic) | 335ms | 1.2x |
| CRuby (idiomatic Ruby) | 386ms | baseline |
| CRuby + YJIT (while-loop subset) | 1,293ms | 0.3x |
| CRuby (while-loop subset) | 1,804ms | 0.2x |

Same algorithm (while-loop subset): Spinel is **14.8x faster** than CRuby, **10.6x faster** than CRuby + YJIT.

## What the analyzer reports

- Total requests, bandwidth, error/redirect rates
- Status code distribution (top 10)
- HTTP method breakdown (top 5)
- Top 15 URLs by hits
- Top 10 URLs by bandwidth
- Hourly traffic histogram (ASCII bars)
- Top 10 requesting hosts

## Why two versions

The while-loop version compiles through Spinel's type inference engine. The idiomatic version doesn't -- it uses features (regex, `Hash.new(0)`, polymorphic `sort_by`, nil returns) that Spinel's static type system can't resolve.

In CRuby, the idiomatic version is 4.7x faster than the while-loop version because regex and builtins are implemented in C. After Spinel compilation, the while-loop version is 3.2x faster than the idiomatic version because the entire program -- including the character-by-character parsing -- compiles to native C with no interpreter overhead.

The code that was slowest in the interpreter became fastest after compilation.
