# Raw data

**Open e-commerce 1.0: Five years of crowdsourced U.S. Amazon purchase histories with user demographics**
Berke, A., Calacci, D., Mahari, R., Yabe, T., Larson, K., & Pentland, S. (2023). Harvard Dataverse, V1.
https://doi.org/10.7910/DVN/YGLYDY · Paper: *Scientific Data* 11, 491 (2024), https://doi.org/10.1038/s41597-024-03329-6

License: **CC0 1.0** (public domain). The authors ask that the data not be used to re-identify participants.
This project only reports aggregates and does not use the survey's health, substance-use, race or sexual-orientation questions.

| File | Source file | Notes |
|---|---|---|
| `amazon_purchases.parquet` | `amazon-purchases.csv` (298.6 MB) | Lossless Parquet copy: all columns kept as text, original names and order. Built with `scripts/convert_purchases_to_parquet.py` |
| `survey.csv` | `survey.csv` (original CSV format) | Unchanged |
| `fields.csv` | `fields.csv` | Unchanged; maps survey column names to questions |

**Provenance check**
- MD5 of the downloaded `amazon-purchases.csv`: `3549d72735b1211ab009ff0177b94bd9`, which matches the checksum listed on Dataverse.
- The Parquet file has the same 1,850,717 rows and the same per-column hash totals as that CSV. The conversion script asserts this.
