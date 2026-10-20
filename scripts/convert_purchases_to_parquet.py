"""Convert the published amazon-purchases.csv to Parquet without altering it.

Every column is kept as text with its original name and row order, so the
Parquet file is a lossless, ~5x smaller copy of the Harvard Dataverse file.
Typing and renaming happen in dbt staging, not here.

Usage: python scripts/convert_purchases_to_parquet.py amazon-purchases.csv data/raw/amazon_purchases.parquet
"""
import sys

import duckdb

src, out = sys.argv[1], sys.argv[2]
con = duckdb.connect()
con.sql(f"""
    copy (select * from read_csv('{src}', header = true, all_varchar = true))
    to '{out}' (format parquet, compression zstd, compression_level 19, row_group_size 200000)
""")

# Verify: same row count and the same per-column hash totals as the CSV
check = "select count(*), sum(hash(columns(*))) from {}"
csv_stats = con.sql(check.format(f"read_csv('{src}', header = true, all_varchar = true)")).fetchall()
parquet_stats = con.sql(check.format(f"read_parquet('{out}')")).fetchall()
assert csv_stats == parquet_stats, "Parquet does not match the source CSV"
print(f"OK: {csv_stats[0][0]:,} rows written to {out}, identical to {src}")
