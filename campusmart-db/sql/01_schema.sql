/* =============================================================================
   CampusMart - 01_schema.sql                       SRS-CM-DB-1.0 / Deliverable D-01
   Target : Microsoft SQL Server 2019+ (SSMS)
   Purpose: DDL - database, tables, keys, constraints, indexes, audit triggers.
   Re-runnable (C-08): existing CampusMart tables are dropped and recreated,
   so re-running this script DESTROYS any data. Use 05_teardown.sql to remove all.
   Note   : "order" is a reserved word in T-SQL; the table is always written
            as dbo.[order] (the name itself stays singular snake_case, C-01).
   ============================================================================= */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

USE master;
GO

-- Create the database only if it does not exist yet (Arabic_CI_AS per section 2.4).
IF DB_ID(N'CampusMart') IS NULL
BEGIN
    CREATE DATABASE CampusMart COLLATE Arabic_CI_AS;
    PRINT N'Database CampusMart created.';
END
GO

USE CampusMart;
GO

-- [C-08] Make the script re-runnable: drop children before parents.
IF OBJECT_ID(N'dbo.order_item', N'U')              IS NOT NULL DROP TABLE dbo.order_item;
IF OBJECT_ID(N'dbo.[order]', N'U')                 IS NOT NULL DROP TABLE dbo.[order];
IF OBJECT_ID(N'dbo.product', N'U')                 IS NOT NULL DROP TABLE dbo.product;
IF OBJECT_ID(N'dbo.customer', N'U')                IS NOT NULL DROP TABLE dbo.customer;
IF OBJECT_ID(N'dbo.supplier', N'U')                IS NOT NULL DROP TABLE dbo.supplier;
IF OBJECT_ID(N'dbo.category', N'U')                IS NOT NULL DROP TABLE dbo.category;
IF OBJECT_ID(N'dbo.product_stage', N'U')           IS NOT NULL DROP TABLE dbo.product_stage;
IF OBJECT_ID(N'dbo.customer_stage', N'U')          IS NOT NULL DROP TABLE dbo.customer_stage;
IF OBJECT_ID(N'dbo.monthly_sales_snapshot', N'U')  IS NOT NULL DROP TABLE dbo.monthly_sales_snapshot;
GO

/* ---------------------------------------------------------------------------
   Business tables (section 4.1)
   --------------------------------------------------------------------------- */

-- [A1.1] CREATE TABLE dbo.category - product taxonomy; parent_id gives single-level nesting (FR-002).
CREATE TABLE dbo.category (
    id          INT           IDENTITY(1,1) NOT NULL,
    name        NVARCHAR(100) NOT NULL,
    parent_id   INT           NULL,
    is_active   BIT           NOT NULL CONSTRAINT df_category_is_active  DEFAULT (1),
    created_at  DATETIME2     NOT NULL CONSTRAINT df_category_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at  DATETIME2     NOT NULL CONSTRAINT df_category_updated_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_category        PRIMARY KEY (id),
    CONSTRAINT uq_category_name   UNIQUE (name),
    CONSTRAINT ck_category_parent CHECK (parent_id IS NULL OR parent_id <> id),
    CONSTRAINT fk_category_parent FOREIGN KEY (parent_id) REFERENCES dbo.category (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION
);
GO

-- [A1.1] CREATE TABLE dbo.supplier - where products are sourced from (FR-005).
CREATE TABLE dbo.supplier (
    id             INT           IDENTITY(1,1) NOT NULL,
    name           NVARCHAR(150) NOT NULL,
    contact_person NVARCHAR(100) NOT NULL,
    phone          NVARCHAR(30)  NOT NULL,
    city           NVARCHAR(80)  NOT NULL,
    is_active      BIT           NOT NULL CONSTRAINT df_supplier_is_active  DEFAULT (1),
    created_at     DATETIME2     NOT NULL CONSTRAINT df_supplier_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at     DATETIME2     NOT NULL CONSTRAINT df_supplier_updated_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_supplier      PRIMARY KEY (id),
    CONSTRAINT uq_supplier_name UNIQUE (name)
);
GO

-- [A1.1] CREATE TABLE dbo.product - sellable item with price and stock (FR-001, FR-003, FR-004, FR-006).
CREATE TABLE dbo.product (
    id          INT           IDENTITY(1,1) NOT NULL,
    sku         NVARCHAR(30)  NOT NULL,
    name        NVARCHAR(150) NOT NULL,
    price       DECIMAL(10,2) NOT NULL,
    stock_qty   INT           NOT NULL CONSTRAINT df_product_stock_qty  DEFAULT (0),
    category_id INT           NOT NULL,
    supplier_id INT           NULL,
    is_active   BIT           NOT NULL CONSTRAINT df_product_is_active  DEFAULT (1),
    created_at  DATETIME2     NOT NULL CONSTRAINT df_product_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at  DATETIME2     NOT NULL CONSTRAINT df_product_updated_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_product          PRIMARY KEY (id),
    CONSTRAINT uq_product_sku      UNIQUE (sku),                                   -- DR-01
    CONSTRAINT ck_product_price    CHECK (price >= 0),                             -- DR-05
    CONSTRAINT ck_product_stock    CHECK (stock_qty >= 0),                         -- DR-05
    CONSTRAINT fk_product_category FOREIGN KEY (category_id) REFERENCES dbo.category (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION,                                   -- DR-09
    CONSTRAINT fk_product_supplier FOREIGN KEY (supplier_id) REFERENCES dbo.supplier (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION                                    -- DR-09
);
GO

-- [A1.1] CREATE TABLE dbo.customer - buyer; email is unique, city feeds geographic reports (FR-007..FR-009).
-- registered_at is an explicit business date (when the customer signed up); it is distinct from created_at.
CREATE TABLE dbo.customer (
    id            INT           IDENTITY(1,1) NOT NULL,
    full_name     NVARCHAR(150) NOT NULL,
    email         NVARCHAR(254) NOT NULL,
    city          NVARCHAR(80)  NOT NULL,
    registered_at DATETIME2     NOT NULL CONSTRAINT df_customer_registered_at DEFAULT (SYSUTCDATETIME()),
    is_active     BIT           NOT NULL CONSTRAINT df_customer_is_active     DEFAULT (1),
    created_at    DATETIME2     NOT NULL CONSTRAINT df_customer_created_at    DEFAULT (SYSUTCDATETIME()),
    updated_at    DATETIME2     NOT NULL CONSTRAINT df_customer_updated_at    DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_customer       PRIMARY KEY (id),
    CONSTRAINT uq_customer_email UNIQUE (email)                                    -- DR-02
);
GO

-- [A1.1] CREATE TABLE dbo.[order] - sales header (FR-010, FR-014).
CREATE TABLE dbo.[order] (
    id           INT           IDENTITY(1,1) NOT NULL,
    order_no     NVARCHAR(20)  NOT NULL,
    customer_id  INT           NOT NULL,
    order_date   DATETIME2     NOT NULL CONSTRAINT df_order_order_date  DEFAULT (SYSUTCDATETIME()),
    total_amount DECIMAL(10,2) NOT NULL CONSTRAINT df_order_total      DEFAULT (0),
    is_active    BIT           NOT NULL CONSTRAINT df_order_is_active   DEFAULT (1),
    created_at   DATETIME2     NOT NULL CONSTRAINT df_order_created_at  DEFAULT (SYSUTCDATETIME()),
    updated_at   DATETIME2     NOT NULL CONSTRAINT df_order_updated_at  DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_order          PRIMARY KEY (id),
    CONSTRAINT uq_order_order_no UNIQUE (order_no),                                -- DR-03
    CONSTRAINT ck_order_order_no CHECK (order_no LIKE
        N'ORD-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9]'),         -- DR-03 format ORD-YYYYMMDD-NNN
    CONSTRAINT ck_order_total    CHECK (total_amount >= 0),                        -- DR-08
    CONSTRAINT fk_order_customer FOREIGN KEY (customer_id) REFERENCES dbo.customer (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION                                    -- DR-09
);
GO

-- [A1.1] CREATE TABLE dbo.order_item - sales line (FR-012). unit_price is a deliberate price snapshot (Appendix C).
-- line_total is a PERSISTED computed column so it can never disagree with quantity * unit_price (NFR-004).
CREATE TABLE dbo.order_item (
    id          INT           IDENTITY(1,1) NOT NULL,
    order_id    INT           NOT NULL,
    product_id  INT           NOT NULL,
    quantity    INT           NOT NULL,
    unit_price  DECIMAL(10,2) NOT NULL,
    line_total  AS (CONVERT(DECIMAL(10,2), quantity * unit_price)) PERSISTED,
    created_at  DATETIME2     NOT NULL CONSTRAINT df_order_item_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at  DATETIME2     NOT NULL CONSTRAINT df_order_item_updated_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_order_item         PRIMARY KEY (id),
    CONSTRAINT uq_order_item_pair    UNIQUE (order_id, product_id),                -- DR-04
    CONSTRAINT ck_order_item_qty     CHECK (quantity > 0),                         -- DR-06
    CONSTRAINT ck_order_item_price   CHECK (unit_price >= 0),                      -- DR-07
    CONSTRAINT fk_order_item_order   FOREIGN KEY (order_id) REFERENCES dbo.[order] (id)
        ON DELETE CASCADE ON UPDATE NO ACTION,                                     -- DR-09: only CASCADE in the schema
    CONSTRAINT fk_order_item_product FOREIGN KEY (product_id) REFERENCES dbo.product (id)
        ON DELETE NO ACTION ON UPDATE NO ACTION                                    -- DR-09
);
GO

/* ---------------------------------------------------------------------------
   Staging tables - the only tables on which TRUNCATE / DELETE-all are used (Appendix C).
   They follow the same C-02 / C-03 column conventions as every other table.
   --------------------------------------------------------------------------- */

-- [A1.1] CREATE TABLE dbo.product_stage - staging area for product imports; reset with TRUNCATE (A1.4).
CREATE TABLE dbo.product_stage (
    id         INT           IDENTITY(1,1) NOT NULL,
    sku        NVARCHAR(30)  NOT NULL,
    name       NVARCHAR(150) NOT NULL,
    price      DECIMAL(10,2) NOT NULL,
    created_at DATETIME2     NOT NULL CONSTRAINT df_product_stage_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at DATETIME2     NOT NULL CONSTRAINT df_product_stage_updated_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_product_stage PRIMARY KEY (id)
);
GO

-- [A1.1] CREATE TABLE dbo.customer_stage - staging area for customer imports; cleared with DELETE FROM (A2.5).
CREATE TABLE dbo.customer_stage (
    id         INT           IDENTITY(1,1) NOT NULL,
    full_name  NVARCHAR(150) NOT NULL,
    email      NVARCHAR(254) NOT NULL,
    city       NVARCHAR(80)  NOT NULL,
    created_at DATETIME2     NOT NULL CONSTRAINT df_customer_stage_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at DATETIME2     NOT NULL CONSTRAINT df_customer_stage_updated_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_customer_stage PRIMARY KEY (id)
);
GO

/* ---------------------------------------------------------------------------
   Required indexes (section 4.4)
   --------------------------------------------------------------------------- */
-- Speeds up "products in a category" lookups and the category -> product join.
CREATE NONCLUSTERED INDEX ix_product_category_id ON dbo.product (category_id);
-- Speeds up a customer's order history, newest first.
CREATE NONCLUSTERED INDEX ix_order_customer_id_order_date ON dbo.[order] (customer_id, order_date);
-- Speeds up fetching all lines of an order (also used by the cascade delete).
CREATE NONCLUSTERED INDEX ix_order_item_order_id ON dbo.order_item (order_id);
-- Speeds up name searches / prefix LIKE patterns. A FULLTEXT index is optional (section 4.4) and
-- is not created because the Full-Text Search feature may not be installed on a student instance.
CREATE NONCLUSTERED INDEX ix_product_name ON dbo.product (name);
GO

/* ---------------------------------------------------------------------------
   Audit triggers - keep updated_at truthful on every UPDATE (FR-004, C-03).
   --------------------------------------------------------------------------- */
CREATE TRIGGER dbo.trg_category_touch_updated_at ON dbo.category AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE t SET updated_at = SYSUTCDATETIME() FROM dbo.category AS t INNER JOIN inserted AS i ON i.id = t.id;
END;
GO
CREATE TRIGGER dbo.trg_supplier_touch_updated_at ON dbo.supplier AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE t SET updated_at = SYSUTCDATETIME() FROM dbo.supplier AS t INNER JOIN inserted AS i ON i.id = t.id;
END;
GO
CREATE TRIGGER dbo.trg_product_touch_updated_at ON dbo.product AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE t SET updated_at = SYSUTCDATETIME() FROM dbo.product AS t INNER JOIN inserted AS i ON i.id = t.id;
END;
GO
CREATE TRIGGER dbo.trg_customer_touch_updated_at ON dbo.customer AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE t SET updated_at = SYSUTCDATETIME() FROM dbo.customer AS t INNER JOIN inserted AS i ON i.id = t.id;
END;
GO
CREATE TRIGGER dbo.trg_order_touch_updated_at ON dbo.[order] AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE t SET updated_at = SYSUTCDATETIME() FROM dbo.[order] AS t INNER JOIN inserted AS i ON i.id = t.id;
END;
GO
CREATE TRIGGER dbo.trg_order_item_touch_updated_at ON dbo.order_item AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE t SET updated_at = SYSUTCDATETIME() FROM dbo.order_item AS t INNER JOIN inserted AS i ON i.id = t.id;
END;
GO

PRINT N'01_schema.sql completed: 8 tables, 4 indexes, 6 triggers created in CampusMart.';
GO
