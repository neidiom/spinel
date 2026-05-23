# Log Analyzer -- Spinel AOT Demo

A Combined Log Format access log analyzer, written in four Ruby variants to demonstrate Spinel's AOT compilation capabilities and benchmark the results.

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
./spinel ./log_analyzer.rb -o spinel_nedim/log_analyzer
./spinel ./log_analyzer_improved.rb -o spinel_nedim/log_analyzer_improved
./spinel ./log_analyzer_v3.rb -o spinel_nedim/log_analyzer_v3

# Run on a real log file:
./log_analyzer /var/log/nginx/access.log
./log_analyzer_improved /var/log/nginx/access.log
./log_analyzer_v3 /var/log/nginx/access.log

# Run with synthetic data (no file needed):
./log_analyzer
./log_analyzer_improved
./log_analyzer_v3
```

### CRuby (all versions)

```bash
ruby ./log_analyzer.rb /var/log/nginx/access.log
ruby ./log_analyzer_improved.rb /var/log/nginx/access.log
ruby ./log_analyzer_v3.rb /var/log/nginx/access.log
ruby ./log_analyzer_idiomatic.rb /var/log/nginx/access.log
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

## Version Evolution

Three Spinel-compatible versions demonstrate progressive improvement while maintaining AOT compilability:

| Version | Performance | Code Quality | Characteristics |
|---------|-------------|--------------|-----------------|
| V1 (`log_analyzer.rb`) | 23ms | Baseline | C-style, single-char vars, inline logic |
| V2 (`log_analyzer_improved.rb`) | 22ms | Good | Extracted helpers, descriptive names, guard clauses |
| V3 (`log_analyzer_v3.rb`) | 37ms | Excellent | Constants, OO design, full encapsulation |

**Trade-off:** V3 is ~60% slower than V2 but significantly more maintainable. Choose based on your needs:
- **V1/V2**: Performance-critical code
- **V3**: Long-term maintenance, team projects, library code

See `DEEP_DIVE.md` for comprehensive comparison and Spinel compatibility guide.

## Why Multiple Versions

The while-loop versions compile through Spinel's type inference engine. The idiomatic version doesn't -- it uses features (regex, `Hash.new(0)`, polymorphic `sort_by`, nil returns) that Spinel's static type system can't resolve.

In CRuby, the idiomatic version is 4.7x faster than the while-loop version because regex and builtins are implemented in C. After Spinel compilation, the while-loop version is 3.2x faster than the idiomatic version because the entire program -- including the character-by-character parsing -- compiles to native C with no interpreter overhead.

The code that was slowest in the interpreter became fastest after compilation.
