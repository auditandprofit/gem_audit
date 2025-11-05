# CodeQL Exec Primitive Baseline

This directory stores the baseline CodeQL query and results used to identify Ruby code execution primitives within the `gems/` tree.

## Files

- `ExecPrimitives.ql` – custom query that selects calls to Ruby execution primitives such as `Kernel.exec`, `Open3.capture3`, and metaprogramming helpers (`class_eval`, `instance_eval`, etc.).
- `qlpack.yml` – local pack manifest so the query can be compiled with the Ruby standard libraries.
- `ExecPrimitives.bqrs` – raw CodeQL results (binary) captured from the latest run against the current repository snapshot.
- `ExecPrimitives.csv` – decoded, human-readable summary of the results.

## Running the query

```bash
codeql query run analysis/codeql/ExecPrimitives.ql \
  --database <ruby-database> \
  --output analysis/codeql/ExecPrimitives.bqrs

codeql bqrs decode analysis/codeql/ExecPrimitives.bqrs \
  --format=csv \
  --output analysis/codeql/ExecPrimitives.csv
```

The query assumes the database was created with the Ruby extractor pointing at the `gems/` directory (for example: `codeql database create <db> --language=ruby --source-root gems`).
