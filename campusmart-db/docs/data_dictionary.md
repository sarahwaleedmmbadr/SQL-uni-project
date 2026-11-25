# CampusMart – Data Dictionary

Schema `dbo`, database `CampusMart` (collation `Arabic_CI_AS`). Every table has the surrogate key
`id INT IDENTITY(1,1)` plus `created_at` / `updated_at` (`DATETIME2`, default `SYSUTCDATETIME()`, C-02/C-03).
`updated_at` is refreshed by an `AFTER UPDATE` trigger on each business table.
Money is `DECIMAL(10,2)` (C-04). Every foreign key states `ON DELETE` and `ON UPDATE` explicitly (C-07).

## dbo.category – product taxonomy
| Column | Type | Null | Default / Constraint | Description |
|---|---|---|---|---|
| id | INT IDENTITY | NO | PK `pk_category` | Surrogate key |
| name | NVARCHAR(100) | NO | UNIQUE `uq_category_name` | Category name |
| parent_id | INT | YES | FK → category.id, NO ACTION / NO ACTION; CHECK `<> id` | Parent category (single-level nesting, FR-002) |
| is_active | BIT | NO | DEFAULT 1 | Soft-delete flag (C-06) |
| created_at, updated_at | DATETIME2 | NO | DEFAULT SYSUTCDATETIME() | Audit timestamps (UTC) |

## dbo.supplier – product source
| Column | Type | Null | Default / Constraint | Description |
|---|---|---|---|---|
| id | INT IDENTITY | NO | PK `pk_supplier` | Surrogate key |
| name | NVARCHAR(150) | NO | UNIQUE `uq_supplier_name` | Supplier name (FR-005) |
| contact_person | NVARCHAR(100) | NO | | Contact person |
| phone | NVARCHAR(30) | NO | | Phone number |
| city | NVARCHAR(80) | NO | | City |
| is_active | BIT | NO | DEFAULT 1 | Soft-delete flag |
| created_at, updated_at | DATETIME2 | NO | DEFAULT SYSUTCDATETIME() | Audit timestamps |

## dbo.product – sellable item
| Column | Type | Null | Default / Constraint | Description |
|---|---|---|---|---|
| id | INT IDENTITY | NO | PK `pk_product` | Surrogate key |
| sku | NVARCHAR(30) | NO | UNIQUE `uq_product_sku` (DR-01) | Stock Keeping Unit |
| name | NVARCHAR(150) | NO | Index `ix_product_name` | Product name |
| price | DECIMAL(10,2) | NO | CHECK `>= 0` (DR-05) | Current unit price, EGP |
| stock_qty | INT | NO | DEFAULT 0; CHECK `>= 0` (DR-05) | Units on hand |
| category_id | INT | NO | FK → category.id, NO ACTION / NO ACTION; Index `ix_product_category_id` | Exactly one category |
| supplier_id | INT | YES | FK → supplier.id, NO ACTION / NO ACTION | Optional supplier (FR-006) |
| is_active | BIT | NO | DEFAULT 1 | Soft-delete flag (FR-003) |
| created_at, updated_at | DATETIME2 | NO | DEFAULT SYSUTCDATETIME() | Audit timestamps |

## dbo.customer – buyer
| Column | Type | Null | Default / Constraint | Description |
|---|---|---|---|---|
| id | INT IDENTITY | NO | PK `pk_customer` | Surrogate key |
| full_name | NVARCHAR(150) | NO | | Full name (Unicode, Arabic supported) |
| email | NVARCHAR(254) | NO | UNIQUE `uq_customer_email` (DR-02) | E-mail (example.com in seed data) |
| city | NVARCHAR(80) | NO | | City for geographic reporting (FR-009) |
| registered_at | DATETIME2 | NO | DEFAULT SYSUTCDATETIME() | Sign-up date used by "registered since" reports |
| is_active | BIT | NO | DEFAULT 1 | Soft-delete flag (FR-008) |
| created_at, updated_at | DATETIME2 | NO | DEFAULT SYSUTCDATETIME() | Audit timestamps |

## dbo.[order] – sales header (`order` is reserved, always bracketed)
| Column | Type | Null | Default / Constraint | Description |
|---|---|---|---|---|
| id | INT IDENTITY | NO | PK `pk_order` | Surrogate key |
| order_no | NVARCHAR(20) | NO | UNIQUE (DR-03); CHECK `LIKE 'ORD-[0-9]{8}-[0-9]{3}'` | Business order number `ORD-YYYYMMDD-NNN` |
| customer_id | INT | NO | FK → customer.id, NO ACTION / NO ACTION; Index `ix_order_customer_id_order_date` (customer_id, order_date) | Buyer (FR-010) |
| order_date | DATETIME2 | NO | DEFAULT SYSUTCDATETIME() | When the order was placed (UTC) |
| total_amount | DECIMAL(10,2) | NO | DEFAULT 0; CHECK `>= 0` (DR-08) | Sum of line totals (FR-014) |
| is_active | BIT | NO | DEFAULT 1 | Soft-delete flag |
| created_at, updated_at | DATETIME2 | NO | DEFAULT SYSUTCDATETIME() | Audit timestamps |

## dbo.order_item – sales line
| Column | Type | Null | Default / Constraint | Description |
|---|---|---|---|---|
| id | INT IDENTITY | NO | PK `pk_order_item` | Surrogate key |
| order_id | INT | NO | FK → [order].id, **ON DELETE CASCADE** / NO ACTION; Index `ix_order_item_order_id`; UNIQUE (order_id, product_id) (DR-04) | Parent order |
| product_id | INT | NO | FK → product.id, NO ACTION / NO ACTION | Product sold |
| quantity | INT | NO | CHECK `> 0` (DR-06) | Units sold |
| unit_price | DECIMAL(10,2) | NO | CHECK `>= 0` (DR-07) | Price at time of sale (snapshot, Appendix C) |
| line_total | DECIMAL(10,2) | NO | PERSISTED computed `quantity * unit_price` | Line total (FR-012) |
| created_at, updated_at | DATETIME2 | NO | DEFAULT SYSUTCDATETIME() | Audit timestamps |

## Helper tables (not business entities)
| Table | Created by | Purpose |
|---|---|---|
| dbo.product_stage | 01_schema.sql | Staging area; the only table reset with `TRUNCATE TABLE` (A1.4). Columns: id, sku, name, price, created_at, updated_at |
| dbo.customer_stage | 01_schema.sql | Staging area; emptied with `DELETE FROM` without `WHERE` (A2.5). Columns: id, full_name, email, city, created_at, updated_at |
| dbo.monthly_sales_snapshot | 03_queries.sql (R-20, `SELECT … INTO`) | Materialised monthly sales: id, sales_year, sales_month, order_count, units_sold, revenue, created_at, updated_at |
| dbo.validation_scratch, dbo.validation_product_copy | 04_validation.sql | Temporary; created and dropped by the validation script |

## Triggers
`trg_<table>_touch_updated_at` (AFTER UPDATE) on category, supplier, product, customer, [order], order_item – sets `updated_at = SYSUTCDATETIME()`.
