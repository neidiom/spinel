# Log Analyzer -- Spinel AOT Demo

A Combined Log Format access log analyzer, written in three Ruby variants to demonstrate Spinel's AOT compilation and benchmark the results.

## Files

| File | Description |
|------|-------------|
| `log_analyzer.rb` | V1: Spinel-compilable version (C-style, single-char vars) |
| `log_analyzer_improved.rb` | V2: Better structure, extracted helpers, descriptive names |
| `log_analyzer_v3.rb` | **V3: Maximum idiomatic** (constants, OO, encapsulation) |
| `log_analyzer_idiomatic.rb` | Idiomatic Ruby (regex, `Hash.new(0)`) - **doesn't compile** |
| `log_analyzer`, `log_analyzer_improved`, `log_analyzer_v3` | Pre-compiled Spinel binaries |
| `benchmark_log_analyzer.rb` | Benchmark harness comparing all variants |
| `DEEP_DIVE.md` | Comprehensive comparison and Spinel compatibility guide |

## Usage

### Spinel native binary

```bash
# From the spinel project root, compile:
./spinel spinel_nedim/log_analyzer.rb -o spinel_nedim/log_analyzer
./spinel spinel_nedim/log_analyzer_improved.rb -o spinel_nedim/log_analyzer_improved

# Run on a real log file:
./spinel_nedim/log_analyzer /var/log/nginx/access.log
./spinel_nedim/log_analyzer_improved /var/log/nginx/access.log

# Run with synthetic data (no file needed):
./spinel_nedim/log_analyzer
./spinel_nedim/log_analyzer_improved
```

### CRuby (all versions)

```bash
ruby spinel_nedim/log_analyzer.rb /var/log/nginx/access.log
ruby spinel_nedim/log_analyzer_improved.rb /var/log/nginx/access.log
ruby spinel_nedim/log_analyzer_idiomatic.rb /var/log/nginx/access.log
```

All Ruby files produce byte-identical output for the same input.

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

## Improvements in `log_analyzer_improved.rb`

The improved version maintains Spinel compatibility while adopting better Ruby practices:

- **Extracted helper methods**: `increment_hash`, `format_hour_label`, `build_bar` reduce duplication
- **Better naming**: `space_pos` instead of `sp`, `date_start` instead of `dstart`
- **Logical grouping**: `parse_request` extracted as private method
- **Structured reporting**: `print_section` consolidates repeated output patterns
- **Clearer separation**: `classify_status`, `record_verb`, `record_url`, `record_hour`
- **Consistent style**: All formatting methods in one place (`percent`, `format_bytes`, `format_hour_label`)

These changes make the code more maintainable without sacrificing Spinel compilability or performance.
