# CampusMart – Campus Retail Database

Implementation of **SRS-CM-DB-1.0** for **Microsoft SQL Server 2019+**, executed in **SSMS**.

## Folder layout (deliverables D-01 … D-08)

| ID | File | Purpose |
|---|---|---|
| D-01 | `sql/01_schema.sql` | Database, 8 tables, keys, constraints, 4 indexes, 6 `updated_at` triggers |
| D-02 | `sql/02_seed.sql` | 10 categories, 7 suppliers, 33 products, 20 customers, 60 orders, 150 order lines |
| D-03 | `sql/03_queries.sql` | Reports R-01 … R-23, each with a business-purpose comment |
| D-04 | `sql/04_validation.sql` | Exercises every Appendix A item + constraint tests + acceptance assertions |
| D-05 | `sql/05_teardown.sql` | Guarded `DROP TABLE` / `DROP DATABASE` |
| D-06 | `docs/erd.mmd` | Mermaid ER diagram (render at mermaid.live or in VS Code) |
| D-07 | `docs/data_dictionary.md` | Column-level specification |
| D-08 | `README.md` | This file |
| – | `tools/check_coverage.py` | Static checker for Appendix A/B coverage and design rules (no database needed) |

## How to run

1. Open SSMS, connect to your SQL Server 2019+ instance with rights to create a database.
2. Open and execute, **in this order**, each file in full (F5): `01_schema.sql` → `02_seed.sql` → `03_queries.sql` → `04_validation.sql`.
3. `04_validation.sql` ends with a PASS/FAIL result grid. Any failure raises error 50010.
4. To remove everything, run `05_teardown.sql`.

From the command line: `sqlcmd -S . -E -i sql\01_schema.sql` (repeat per file; add `-f 65001` for UTF-8).

**Encoding:** the `.sql` files are saved as UTF-8 **with BOM** so SSMS reads the Arabic customer names (`N'…'` literals) correctly. Keep the BOM if you re-save them.

## Re-running

| Script | Behaviour when run again |
|---|---|
| 01 | Drops and recreates all tables (**destroys data**) |
| 02 | Resets the staging table; loads business data only into an empty schema, otherwise prints a message and stops |
| 03 | Safe: R-20 rebuilds its snapshot, R-21/R-22 are idempotent, R-23 always rolls back |
| 04 | Safe: places one new order per run (stock decreases, then one line is cancelled and restored); all other tests roll back |
| 05 | Safe even when the database is already gone |

## Design decisions and deviations (please read)

- **`[order]`** – `order` is a reserved word, so the table is always written `dbo.[order]`. The name itself is still singular snake_case.
- **Columns added beyond the "key fields" in 4.1:** `is_active` on category, supplier, product, customer and order (C-06 soft delete); `customer.registered_at` (needed by R-02 / A4.2, distinct from `created_at`).
- **`order_item.line_total`** is a persisted computed column (`quantity * unit_price`), so it cannot disagree with its inputs (NFR-004). `unit_price` is the documented price snapshot (Appendix C).
- **`updated_at` triggers** keep the timestamp truthful on every UPDATE (FR-004).
- **Staging tables** `product_stage` (truncated, A1.4) and `customer_stage` (emptied with `DELETE FROM` without `WHERE`, A2.5) are the only tables touched by those commands (Appendix C). Both follow the C-02/C-03 column rules. `monthly_sales_snapshot` (created by `SELECT … INTO`) gets `id`, `created_at`, `updated_at`, a primary key and defaults added afterwards.
- **C-06 vs A2.4:** business records are soft-deleted; the only hard delete of a business row is the *cancelled order line* the SRS itself requires (A2.4 / R-21). The delete restores stock and recomputes the order total so FR-013 / FR-014 stay true.
- **FR-011** (an order has ≥ 1 line) cannot be a declarative constraint; it is enforced by the order-placement transaction in `04_validation.sql` (A5.1) and checked by an assertion.
- **FULLTEXT index** (optional in 4.4) is not created because Full-Text Search may not be installed; a normal nonclustered index on `product(name)` is.
- **Collation** `Arabic_CI_AS` is case-insensitive, so `LIKE '%M%'` also matches lowercase `m`, and `'A%'`/`'%a'` ignore case.
- **Dates** in the seed data are relative to the day you run `02_seed.sql`, so "last 180 days" reports are never empty.

## Verification against Section 6 (Acceptance Criteria)

| # | Criterion | How it is verified |
|---|---|---|
| 1 | DDL runs cleanly, schema matches Section 4 | `tools/check_coverage.py` checks C-01/02/03/04/07/10, DR-01…09 and the 4 indexes in the DDL text; a clean run of `01_schema.sql` in SSMS confirms execution |
| 2 | Every constraint in 4.3 is enforced | `04_validation.sql` section 6 – 13 tests (DR-01 … DR-09): 12 invalid statements that must be rejected plus the CASCADE behaviour test, each inside a transaction that is rolled back |
| 3 | Seed data loads and meets 4.5 volumes | `04_validation.sql` section 7 – counts, price range 5–500, ≥ 4 cities, ≥ 6 calendar months, example.com only |
| 4 | Every Appendix A statement appears | `tools/check_coverage.py` – tag + statement present (matrix below) |
| 5 | Appendix B reports return correct, non-empty results | R-01 … R-19 non-empty assertions in section 7; R-20 table existence check; R-21 … R-23 print before/after evidence |
| 6 | Data dictionary complete and consistent with DDL | `docs/data_dictionary.md` |
| 7 | ERD matches the schema | `docs/erd.mmd` |

## Appendix A coverage matrix (tag `[A…]` in each comment)

| Item | Statement | Where |
|---|---|---|
| A1.1 | CREATE TABLE | `01_schema.sql` (all 8 tables), `04_validation.sql` (scratch) |
| A1.2 | DROP TABLE (guarded) | `05_teardown.sql`, `04_validation.sql` §8 |
| A1.3 | DROP DATABASE (guarded) | `05_teardown.sql` |
| A1.4 | TRUNCATE TABLE | `02_seed.sql`, `04_validation.sql` |
| A2.1 | INSERT INTO | `02_seed.sql`, `04_validation.sql` |
| A2.2 | SELECT … INTO | `03_queries.sql` R-20, `04_validation.sql` |
| A2.3 | UPDATE … WHERE | `02_seed.sql`, `03_queries.sql` R-22, `04_validation.sql` |
| A2.4 | DELETE FROM … WHERE | `03_queries.sql` R-21, `04_validation.sql` §3 |
| A2.5 | DELETE FROM (no WHERE) | `04_validation.sql` §3 (`customer_stage`) |
| A2.6 | ROLLBACK of multi-row insert | `03_queries.sql` R-23, `04_validation.sql` §3 |
| A3.1 – A3.9 | SELECT *, WHERE, GROUP BY/HAVING, ASC+DESC, TOP + OFFSET/FETCH, 5 aggregates, AND/OR/NOT, BETWEEN, IN | `04_validation.sql` §4 |
| A3.10 | LIKE `S%`, `%M%`, `A%`, `%a`, `%mo%`, `_h%` | `04_validation.sql` §4 (and R-11 … R-15 in `03_queries.sql`) |
| A4.1 – A4.6 | `>`, `>=`, `<`, `<=`, `=`, `<>` | `04_validation.sql` §5 |
| A5.1 | BEGIN / COMMIT TRANSACTION (order placement + stock decrement) | `04_validation.sql` §3 |
| A5.2 | ROLLBACK TRANSACTION | `03_queries.sql` R-23, `04_validation.sql` §3 |

Run `python3 tools/check_coverage.py` to re-check this matrix mechanically.
