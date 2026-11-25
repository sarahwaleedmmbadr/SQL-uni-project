/* =============================================================================
   CampusMart - 04_validation.sql                   SRS-CM-DB-1.0 / Deliverable D-04
   Purpose: Exercises EVERY required operation of Appendix A and verifies the
            acceptance criteria of section 6 (constraints, seed volumes, reports).
   Layout : 1 DDL | 2 DML | 3 TCL (order placement) | 4 DQL | 5 WHERE operators |
            6 constraint tests (DR-01..DR-09) | 7 acceptance assertions | 8 cleanup.
   Tags   : every demonstration carries a "[Ax.y]" tag + a comment with its store purpose.
   Notes  : A1.3 (DROP DATABASE) cannot run while connected to CampusMart, so it lives in
            05_teardown.sql. All destructive tests run inside transactions that are rolled back.
   Prereq : 01_schema.sql, 02_seed.sql (03_queries.sql optional).
   ============================================================================= */
USE CampusMart;
GO
SET NOCOUNT ON;
GO

/* =============================== 1. DDL ================================== */
PRINT N'=== 1. DDL ===';

IF OBJECT_ID(N'dbo.validation_scratch', N'U')      IS NOT NULL DROP TABLE dbo.validation_scratch;
IF OBJECT_ID(N'dbo.validation_product_copy', N'U') IS NOT NULL DROP TABLE dbo.validation_product_copy;
GO

-- [A1.1] CREATE TABLE - a scratch table used only by this script (same C-02/C-03 column conventions); dropped in section 8.
CREATE TABLE dbo.validation_scratch (
    id         INT           IDENTITY(1,1) NOT NULL,
    label      NVARCHAR(100) NOT NULL,
    created_at DATETIME2     NOT NULL CONSTRAINT df_validation_scratch_created_at DEFAULT (SYSUTCDATETIME()),
    updated_at DATETIME2     NOT NULL CONSTRAINT df_validation_scratch_updated_at DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT pk_validation_scratch PRIMARY KEY (id)
);
GO

/* =============================== 2. DML ================================== */
PRINT N'=== 2. DML ===';

-- [A2.1] INSERT INTO - add two labelled rows to the scratch table (store context: a throw-away work list).
INSERT INTO dbo.validation_scratch (label) VALUES (N'first scratch row'), (N'second scratch row');
GO

-- [A2.2] SELECT ... INTO - make a physical copy of all premium products (price > 100) as a new table (FR-017).
SELECT p.id AS product_id, p.sku, p.name, p.price, SYSUTCDATETIME() AS copied_at
INTO   dbo.validation_product_copy
FROM   dbo.product AS p
WHERE  p.price > 100;
SELECT COUNT(*) AS copied_rows FROM dbo.validation_product_copy;
GO

-- [A2.3] UPDATE ... WHERE - lower the price of the 64GB USB drive (idempotent fixed value; trigger stamps updated_at).
UPDATE dbo.product SET price = 135.00 WHERE sku = N'CA-002';
-- [A2.3] UPDATE ... WHERE - a customer moved: change one customer's city (idempotent fixed value).
UPDATE dbo.customer SET city = N'Giza' WHERE email = N'rana.jamal@example.com';
SELECT sku, price, updated_at FROM dbo.product  WHERE sku   = N'CA-002';
SELECT email, city, updated_at FROM dbo.customer WHERE email = N'rana.jamal@example.com';
GO

/* ====================== 3. TCL - order placement ========================= */
PRINT N'=== 3. TCL: order placement (A5.1) and line cancellation (A2.4) ===';
GO

-- [A5.1] BEGIN TRANSACTION / COMMIT TRANSACTION - place a real order: header + lines + stock decrement + total,
--        all in ONE transaction (FR-010..FR-014, NFR-005). Any failure (unknown SKU, not enough stock) rolls everything back.
SET XACT_ABORT ON;
DECLARE @customer_id INT = (SELECT id FROM dbo.customer WHERE email = N'ahmed.hassan@example.com' AND is_active = 1);
DECLARE @day  NCHAR(8)     = CONVERT(NCHAR(8), SYSUTCDATETIME(), 112);
DECLARE @seq  INT;
DECLARE @no   NVARCHAR(20);
DECLARE @oid  INT;
DECLARE @lines TABLE (sku NVARCHAR(30) NOT NULL, qty INT NOT NULL);
INSERT INTO @lines (sku, qty) VALUES (N'WT-001', 3), (N'CA-002', 1), (N'SN-002', 5);

BEGIN TRY
    IF @customer_id IS NULL THROW 50001, N'Unknown or inactive customer.', 1;
    IF NOT EXISTS (SELECT 1 FROM @lines) THROW 50002, N'An order needs at least one line (FR-011).', 1;

    BEGIN TRANSACTION;

    SELECT @seq = ISNULL(MAX(CAST(RIGHT(order_no, 3) AS INT)), 0) + 1
    FROM   dbo.[order] WITH (UPDLOCK, HOLDLOCK)
    WHERE  order_no LIKE N'ORD-' + @day + N'-%';
    SET @no = N'ORD-' + @day + N'-' + RIGHT(N'00' + CAST(@seq AS NVARCHAR(3)), 3);

    INSERT INTO dbo.[order] (order_no, customer_id, order_date, total_amount)
    VALUES (@no, @customer_id, SYSUTCDATETIME(), 0);
    SET @oid = SCOPE_IDENTITY();

    INSERT INTO dbo.order_item (order_id, product_id, quantity, unit_price)
    SELECT @oid, p.id, l.qty, p.price
    FROM   @lines AS l
    INNER JOIN dbo.product AS p ON p.sku = l.sku AND p.is_active = 1;

    IF @@ROWCOUNT <> (SELECT COUNT(*) FROM @lines) THROW 50003, N'A product on the order is unknown or inactive.', 1;

    -- FR-013: decrement stock in the same transaction (ck_product_stock rejects negative stock).
    UPDATE p SET p.stock_qty = p.stock_qty - l.qty
    FROM   dbo.product AS p INNER JOIN @lines AS l ON l.sku = p.sku;

    -- FR-014: order total = sum of line totals.
    UPDATE dbo.[order]
    SET    total_amount = (SELECT SUM(line_total) FROM dbo.order_item WHERE order_id = @oid)
    WHERE  id = @oid;

    COMMIT TRANSACTION;
    SELECT o.order_no, o.total_amount, COUNT(oi.id) AS line_count
    FROM   dbo.[order] AS o INNER JOIN dbo.order_item AS oi ON oi.order_id = o.id
    WHERE  o.id = @oid GROUP BY o.order_no, o.total_amount;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- [A2.4] DELETE FROM ... WHERE - the customer cancels one line of the order placed above (today's newest order):
--        delete the line, return the units to stock and recompute the total. Skipped if that order has < 2 lines.
SET XACT_ABORT ON;
DECLARE @oid2 INT, @line_id INT, @product_id INT, @qty INT;
SELECT TOP (1) @oid2 = id
FROM   dbo.[order]
WHERE  order_no LIKE N'ORD-' + CONVERT(NCHAR(8), SYSUTCDATETIME(), 112) + N'-%'
ORDER BY id DESC;

IF @oid2 IS NULL OR (SELECT COUNT(*) FROM dbo.order_item WHERE order_id = @oid2) < 2
BEGIN
    PRINT N'A2.4 skipped: no suitable order placed today.';
    RETURN;
END;

SELECT TOP (1) @line_id = id, @product_id = product_id, @qty = quantity
FROM   dbo.order_item WHERE order_id = @oid2 ORDER BY id DESC;

BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM dbo.order_item WHERE id = @line_id;
    UPDATE dbo.product SET stock_qty = stock_qty + @qty WHERE id = @product_id;
    UPDATE dbo.[order]
    SET    total_amount = (SELECT SUM(line_total) FROM dbo.order_item WHERE order_id = @oid2)
    WHERE  id = @oid2;
    COMMIT TRANSACTION;
    PRINT N'A2.4: cancelled line removed.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- [A2.5] DELETE FROM (no WHERE) - empty the customer staging table completely (staging table only, Appendix C).
INSERT INTO dbo.customer_stage (full_name, email, city)
VALUES (N'Stage One', N'stage.one@example.com', N'Cairo'),
       (N'Stage Two', N'stage.two@example.com', N'Giza'),
       (N'Stage Three', N'stage.three@example.com', N'Aswan');
SELECT COUNT(*) AS staged_rows_before FROM dbo.customer_stage;
DELETE FROM dbo.customer_stage;
SELECT COUNT(*) AS staged_rows_after FROM dbo.customer_stage;
GO

-- [A1.4] TRUNCATE TABLE - reset the product staging table (fast, resets identity; staging only, Appendix C).
SELECT COUNT(*) AS product_stage_rows_before FROM dbo.product_stage;
TRUNCATE TABLE dbo.product_stage;
SELECT COUNT(*) AS product_stage_rows_after FROM dbo.product_stage;
GO

-- [A2.6] [A5.2] Multi-row insert that is rolled back: three trial customers are added, counted, then undone.
BEGIN TRANSACTION;
-- [A2.6] INSERT INTO (multi-row) - bulk-add three customers inside an open transaction.
INSERT INTO dbo.customer (full_name, email, city)
VALUES (N'Trial One',   N'trial.one@example.com',   N'Cairo'),
       (N'Trial Two',   N'trial.two@example.com',   N'Giza'),
       (N'Trial Three', N'trial.three@example.com', N'Aswan');
SELECT COUNT(*) AS trial_rows_inside_transaction FROM dbo.customer WHERE email LIKE N'trial.%@example.com';
-- [A2.6] [A5.2] ROLLBACK TRANSACTION - the bulk import is cancelled; no trial customer must remain.
ROLLBACK TRANSACTION;
SELECT COUNT(*) AS trial_rows_after_rollback FROM dbo.customer WHERE email LIKE N'trial.%@example.com';
GO

/* =============================== 4. DQL ================================== */
PRINT N'=== 4. DQL ===';

-- [A3.1] SELECT * - ad-hoc inspection of the whole (small) category table.
SELECT * FROM dbo.category;
GO

-- [A3.2] SELECT <columns> FROM ... WHERE - filtered product list: active snack products only.
SELECT sku, name, price
FROM   dbo.product
WHERE  category_id = (SELECT id FROM dbo.category WHERE name = N'Snacks') AND is_active = 1;
GO

-- [A3.3] GROUP BY with HAVING - categories whose total sales exceed 1000 EGP.
SELECT c.name AS category_name, SUM(oi.line_total) AS total_sales
FROM   dbo.category AS c
INNER JOIN dbo.product    AS p  ON p.category_id = c.id
INNER JOIN dbo.order_item AS oi ON oi.product_id = p.id
GROUP BY c.name
HAVING SUM(oi.line_total) > 1000
ORDER BY total_sales DESC;
GO

-- [A3.4] ORDER BY ... ASC - cheapest products first (price list).
SELECT sku, name, price FROM dbo.product ORDER BY price ASC;
-- [A3.4] ORDER BY ... DESC - most recent orders first (newest activity).
SELECT order_no, order_date, total_amount FROM dbo.[order] ORDER BY order_date DESC;
GO

-- [A3.5] TOP - the three best-selling products by units sold (top-N).
SELECT TOP (3) p.name, SUM(oi.quantity) AS units_sold
FROM   dbo.product AS p INNER JOIN dbo.order_item AS oi ON oi.product_id = p.id
GROUP BY p.name
ORDER BY units_sold DESC;
-- [A3.5] OFFSET ... FETCH - page 2 of the price list, five products per page (LIMIT equivalent).
SELECT sku, name, price
FROM   dbo.product
ORDER BY price DESC, sku
OFFSET 5 ROWS FETCH NEXT 5 ROWS ONLY;
GO

-- [A3.6] COUNT, SUM, AVG, MIN, MAX - all five aggregates over product prices (stock valuation overview).
SELECT COUNT(*) AS product_count, SUM(price * stock_qty) AS stock_value,
       AVG(price) AS average_price, MIN(price) AS cheapest, MAX(price) AS dearest
FROM   dbo.product;
GO

-- [A3.7] AND, OR, NOT - cheap snacks or drinks that are still active and are not out of stock.
SELECT sku, name, price, stock_qty
FROM   dbo.product
WHERE  is_active = 1
  AND  (price < 40 OR stock_qty > 200)
  AND  NOT (stock_qty = 0);
GO

-- [A3.8] BETWEEN - price-range filter used by the "mid-range" shelf (50 to 300 EGP).
SELECT sku, name, price FROM dbo.product WHERE price BETWEEN 50 AND 300;
GO

-- [A3.9] IN - products that belong to a chosen list of categories.
SELECT sku, name FROM dbo.product
WHERE  category_id IN (SELECT id FROM dbo.category WHERE name IN (N'Books', N'Apparel'));
GO

-- [A3.10] LIKE 'S%' - names starting with S.
SELECT name FROM dbo.product WHERE name LIKE N'S%';
-- [A3.10] LIKE '%M%' - names containing M anywhere.
SELECT name FROM dbo.product WHERE name LIKE N'%M%';
-- [A3.10] LIKE 'A%' - names starting with A.
SELECT name FROM dbo.product WHERE name LIKE N'A%';
-- [A3.10] LIKE '%a' - names ending with a.
SELECT name FROM dbo.product WHERE name LIKE N'%a';
-- [A3.10] LIKE '%mo%' - names containing "mo".
SELECT name FROM dbo.product WHERE name LIKE N'%mo%';
-- [A3.10] LIKE '_h%' - names whose second character is h.
SELECT name FROM dbo.product WHERE name LIKE N'_h%';
GO

/* ======================= 5. Operators used with WHERE ===================== */
PRINT N'=== 5. WHERE operators ===';

-- [A4.1] operator > : products above a price threshold.
SELECT sku, name, price FROM dbo.product WHERE price > 300;
-- [A4.2] operator >= : customers registered on or after a date (last 90 days).
SELECT full_name, registered_at FROM dbo.customer WHERE registered_at >= DATEADD(DAY, -90, SYSUTCDATETIME());
-- [A4.3] operator < : products whose stock is below a reorder limit.
SELECT sku, name, stock_qty FROM dbo.product WHERE stock_qty < 10;
-- [A4.4] operator <= : orders at or below a small-basket amount.
SELECT order_no, total_amount FROM dbo.[order] WHERE total_amount <= 300;
-- [A4.5] operator = : exact-match lookup of a product by SKU.
SELECT sku, name, price FROM dbo.product WHERE sku = N'DR-003';
-- [A4.6] operator <> : customers outside Cairo.
SELECT full_name, city FROM dbo.customer WHERE city <> N'Cairo';
GO

/* ================= 6. Constraint tests (acceptance criterion 2) ============ */
PRINT N'=== 6. Constraint tests ===';
-- Every test tries an invalid statement inside a transaction. If the DBMS rejects it the test PASSES; if it
-- is wrongly accepted the transaction is rolled back and the test FAILS. Results are shown in section 7.
IF OBJECT_ID(N'tempdb..#validation_result') IS NOT NULL DROP TABLE #validation_result;
CREATE TABLE #validation_result (
    seq        INT IDENTITY(1,1) PRIMARY KEY,
    check_code NVARCHAR(40)  NOT NULL,
    descr      NVARCHAR(200) NOT NULL,
    passed     BIT           NOT NULL,
    detail     NVARCHAR(400) NULL
);
GO

DECLARE @cid INT = (SELECT TOP (1) id FROM dbo.customer ORDER BY id);
DECLARE @cat INT = (SELECT TOP (1) id FROM dbo.category ORDER BY id);
DECLARE @free_order INT, @free_product INT, @oid INT;
SELECT TOP (1) @free_order = o.id, @free_product = p.id
FROM   dbo.[order] AS o CROSS JOIN dbo.product AS p
WHERE  NOT EXISTS (SELECT 1 FROM dbo.order_item x WHERE x.order_id = o.id AND x.product_id = p.id)
ORDER BY o.id, p.id;

-- [DR-01] product.sku must be UNIQUE.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.product (sku, name, price, stock_qty, category_id)
    SELECT TOP (1) sku, N'Duplicate SKU', 1, 1, category_id FROM dbo.product;
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-01', N'duplicate SKU rejected', 0, N'duplicate was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-01', N'duplicate SKU rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-02] customer.email must be UNIQUE.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.customer (full_name, email, city) SELECT TOP (1) N'Duplicate Mail', email, N'Cairo' FROM dbo.customer;
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-02', N'duplicate e-mail rejected', 0, N'duplicate was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-02', N'duplicate e-mail rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-03] order.order_no must be UNIQUE ...
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.[order] (order_no, customer_id, total_amount) SELECT TOP (1) order_no, @cid, 0 FROM dbo.[order];
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-03a', N'duplicate order_no rejected', 0, N'duplicate was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-03a', N'duplicate order_no rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-03] ... and must follow the format ORD-YYYYMMDD-NNN.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.[order] (order_no, customer_id, total_amount) VALUES (N'BAD-FORMAT-1', @cid, 0);
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-03b', N'malformed order_no rejected', 0, N'bad format was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-03b', N'malformed order_no rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-04] order_item (order_id, product_id) must be UNIQUE.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.order_item (order_id, product_id, quantity, unit_price)
    SELECT TOP (1) order_id, product_id, 1, unit_price FROM dbo.order_item;
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-04', N'same product twice on one order rejected', 0, N'duplicate was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-04', N'same product twice on one order rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-05] product.price >= 0.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.product (sku, name, price, stock_qty, category_id) VALUES (N'NEG-PRICE', N'Negative price', -1, 1, @cat);
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-05a', N'negative price rejected', 0, N'negative price was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-05a', N'negative price rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-05] product.stock_qty >= 0.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.product (sku, name, price, stock_qty, category_id) VALUES (N'NEG-STOCK', N'Negative stock', 1, -1, @cat);
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-05b', N'negative stock rejected', 0, N'negative stock was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-05b', N'negative stock rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-06] order_item.quantity > 0.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.order_item (order_id, product_id, quantity, unit_price) VALUES (@free_order, @free_product, 0, 1);
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-06', N'zero quantity rejected', 0, N'zero quantity was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-06', N'zero quantity rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-07] order_item.unit_price >= 0.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.order_item (order_id, product_id, quantity, unit_price) VALUES (@free_order, @free_product, 1, -1);
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-07', N'negative unit_price rejected', 0, N'negative price was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-07', N'negative unit_price rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-08] order.total_amount >= 0.
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO dbo.[order] (order_no, customer_id, total_amount) VALUES (N'ORD-19990101-001', @cid, -5);
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-08', N'negative order total rejected', 0, N'negative total was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-08', N'negative order total rejected', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-09] ON DELETE NO ACTION: a product that appears on order lines cannot be hard-deleted.
BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM dbo.product WHERE id = (SELECT TOP (1) product_id FROM dbo.order_item);
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-09a', N'delete of a sold product blocked (NO ACTION)', 0, N'delete was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-09a', N'delete of a sold product blocked (NO ACTION)', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-09] ON DELETE NO ACTION: a customer with orders cannot be hard-deleted.
BEGIN TRY
    BEGIN TRANSACTION;
    DELETE FROM dbo.customer WHERE id = (SELECT TOP (1) customer_id FROM dbo.[order]);
    ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-09b', N'delete of a customer with orders blocked (NO ACTION)', 0, N'delete was ACCEPTED');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-09b', N'delete of a customer with orders blocked (NO ACTION)', 1, ERROR_MESSAGE());
END CATCH;

-- [DR-09] ON DELETE CASCADE (order_item only): deleting an order removes its lines. Rolled back afterwards.
BEGIN TRY
    BEGIN TRANSACTION;
    SET @oid = (SELECT TOP (1) order_id FROM dbo.order_item ORDER BY order_id);
    DELETE FROM dbo.[order] WHERE id = @oid;
    INSERT INTO #validation_result (check_code, descr, passed, detail)
    VALUES (N'DR-09c', N'deleting an order cascades to its lines',
            CASE WHEN NOT EXISTS (SELECT 1 FROM dbo.order_item WHERE order_id = @oid) THEN 1 ELSE 0 END,
            N'order_item rows left for the deleted order: ' + CAST((SELECT COUNT(*) FROM dbo.order_item WHERE order_id = @oid) AS NVARCHAR(20)));
    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    INSERT INTO #validation_result (check_code, descr, passed, detail) VALUES (N'DR-09c', N'deleting an order cascades to its lines', 0, ERROR_MESSAGE());
END CATCH;
GO

/* ============ 7. Acceptance assertions (section 6) and report checks ====== */
PRINT N'=== 7. Acceptance assertions ===';

-- Seed volumes (section 4.5) - acceptance criterion 3.
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'AC-3 categories', N'>= 8 categories, some with a parent', CASE WHEN COUNT(*) >= 8 AND COUNT(parent_id) >= 1 THEN 1 ELSE 0 END, CAST(COUNT(*) AS NVARCHAR(20)) + N' rows' FROM dbo.category;
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'AC-3 suppliers', N'>= 6 suppliers', CASE WHEN COUNT(*) >= 6 THEN 1 ELSE 0 END, CAST(COUNT(*) AS NVARCHAR(20)) + N' rows' FROM dbo.supplier;
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'AC-3 products', N'>= 30 products, prices within 5..500 EGP and varied', CASE WHEN COUNT(*) >= 30 AND MIN(price) >= 5 AND MAX(price) <= 500 AND COUNT(DISTINCT price) >= 10 THEN 1 ELSE 0 END,
       CAST(COUNT(*) AS NVARCHAR(20)) + N' rows, price ' + CAST(MIN(price) AS NVARCHAR(20)) + N'..' + CAST(MAX(price) AS NVARCHAR(20)) FROM dbo.product;
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'AC-3 customers', N'>= 20 customers in >= 4 cities', CASE WHEN COUNT(*) >= 20 AND COUNT(DISTINCT city) >= 4 THEN 1 ELSE 0 END,
       CAST(COUNT(*) AS NVARCHAR(20)) + N' rows, ' + CAST(COUNT(DISTINCT city) AS NVARCHAR(20)) + N' cities' FROM dbo.customer;
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'AC-3 orders', N'>= 50 orders spread over >= 6 calendar months', CASE WHEN COUNT(*) >= 50 AND COUNT(DISTINCT YEAR(order_date) * 100 + MONTH(order_date)) >= 6 THEN 1 ELSE 0 END,
       CAST(COUNT(*) AS NVARCHAR(20)) + N' rows, ' + CAST(COUNT(DISTINCT YEAR(order_date) * 100 + MONTH(order_date)) AS NVARCHAR(20)) + N' months' FROM dbo.[order];
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'AC-3 order_items', N'>= 120 order items', CASE WHEN COUNT(*) >= 120 THEN 1 ELSE 0 END, CAST(COUNT(*) AS NVARCHAR(20)) + N' rows' FROM dbo.order_item;
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'AC-3 e-mail domain', N'all customer e-mails use example.com', CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END, CAST(COUNT(*) AS NVARCHAR(20)) + N' offending rows' FROM dbo.customer WHERE email NOT LIKE N'%@example.com';

-- Business rules FR-011 / FR-014 / DR-03.
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'FR-011', N'every order has at least one line', CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END, CAST(COUNT(*) AS NVARCHAR(20)) + N' orders without lines'
FROM dbo.[order] AS o WHERE NOT EXISTS (SELECT 1 FROM dbo.order_item AS x WHERE x.order_id = o.id);
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'FR-014', N'order total = sum of line totals', CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END, CAST(COUNT(*) AS NVARCHAR(20)) + N' orders with a wrong total'
FROM dbo.[order] AS o WHERE o.total_amount <> ISNULL((SELECT SUM(x.line_total) FROM dbo.order_item AS x WHERE x.order_id = o.id), 0);
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'NFR-004', N'line_total = quantity * unit_price to 2 decimals', CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END, CAST(COUNT(*) AS NVARCHAR(20)) + N' mismatching lines'
FROM dbo.order_item WHERE line_total <> CONVERT(DECIMAL(10,2), quantity * unit_price);

-- Appendix B reports R-01..R-19 return rows against the seed data (acceptance criterion 5).
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT r.code, r.descr, CASE WHEN r.cnt > 0 THEN 1 ELSE 0 END, CAST(r.cnt AS NVARCHAR(20)) + N' row(s)'
FROM (
    SELECT N'R-01' AS code, N'price > 100' AS descr, COUNT(*) AS cnt FROM dbo.product WHERE price > 100
    UNION ALL SELECT N'R-02', N'registered in last 180 days', COUNT(*) FROM dbo.customer WHERE registered_at >= DATEADD(DAY, -180, SYSUTCDATETIME())
    UNION ALL SELECT N'R-03', N'stock < 10', COUNT(*) FROM dbo.product WHERE stock_qty < 10
    UNION ALL SELECT N'R-04', N'order total <= 500', COUNT(*) FROM dbo.[order] WHERE total_amount <= 500
    UNION ALL SELECT N'R-05', N'history of one customer', COUNT(*) FROM dbo.[order] o JOIN dbo.customer c ON c.id = o.customer_id WHERE c.email = N'ahmed.hassan@example.com'
    UNION ALL SELECT N'R-06', N'customers outside Cairo', COUNT(*) FROM dbo.customer WHERE city <> N'Cairo'
    UNION ALL SELECT N'R-07', N'price list ASC', COUNT(*) FROM dbo.product
    UNION ALL SELECT N'R-08', N'top 5 by price', COUNT(*) FROM (SELECT TOP (5) id FROM dbo.product ORDER BY price DESC) t
    UNION ALL SELECT N'R-09', N'order aggregates', COUNT(*) FROM dbo.[order]
    UNION ALL SELECT N'R-10', N'categories with > 3 products', COUNT(*) FROM (SELECT category_id FROM dbo.product GROUP BY category_id HAVING COUNT(*) > 3) t
    UNION ALL SELECT N'R-11', N'LIKE S%', COUNT(*) FROM dbo.product WHERE name LIKE N'S%'
    UNION ALL SELECT N'R-12', N'LIKE %M%', COUNT(*) FROM dbo.product WHERE name LIKE N'%M%'
    UNION ALL SELECT N'R-13', N'LIKE A% and %a', COUNT(*) FROM dbo.product WHERE name LIKE N'A%' AND name LIKE N'%a'
    UNION ALL SELECT N'R-14', N'LIKE %mo%', COUNT(*) FROM dbo.product WHERE name LIKE N'%mo%'
    UNION ALL SELECT N'R-15', N'LIKE _h%', COUNT(*) FROM dbo.product WHERE name LIKE N'_h%'
    UNION ALL SELECT N'R-16', N'IN category list', COUNT(*) FROM dbo.product WHERE category_id IN (SELECT id FROM dbo.category WHERE name IN (N'Notebooks', N'Writing Tools', N'Snacks'))
    UNION ALL SELECT N'R-17', N'BETWEEN 50 AND 300', COUNT(*) FROM dbo.product WHERE price BETWEEN 50 AND 300
    UNION ALL SELECT N'R-18', N'active Cairo/Alexandria', COUNT(*) FROM dbo.customer WHERE is_active = 1 AND (city = N'Cairo' OR city = N'Alexandria') AND NOT (registered_at > DATEADD(DAY, -30, SYSUTCDATETIME()))
    UNION ALL SELECT N'R-19', N'monthly revenue', COUNT(*) FROM (SELECT YEAR(order_date) y, MONTH(order_date) m FROM dbo.[order] GROUP BY YEAR(order_date), MONTH(order_date)) t
) AS r;

-- R-20: the snapshot table exists and is populated (run 03_queries.sql first).
INSERT INTO #validation_result (check_code, descr, passed, detail)
SELECT N'R-20', N'monthly_sales_snapshot exists (03_queries.sql was run)', CASE WHEN OBJECT_ID(N'dbo.monthly_sales_snapshot', N'U') IS NOT NULL THEN 1 ELSE 0 END,
       CASE WHEN OBJECT_ID(N'dbo.monthly_sales_snapshot', N'U') IS NOT NULL THEN N'table present' ELSE N'table missing - run 03_queries.sql' END;
GO

-- Result grid: one row per check. Any FAIL raises an error so the script cannot pass silently.
SELECT check_code, descr AS description, CASE passed WHEN 1 THEN N'PASS' ELSE N'FAIL' END AS result, detail
FROM   #validation_result ORDER BY seq;

SELECT SUM(CASE WHEN passed = 1 THEN 1 ELSE 0 END) AS checks_passed,
       SUM(CASE WHEN passed = 0 THEN 1 ELSE 0 END) AS checks_failed
FROM   #validation_result;

IF EXISTS (SELECT 1 FROM #validation_result WHERE passed = 0)
    THROW 50010, N'04_validation.sql: one or more checks FAILED - see the result grid.', 1;
GO

/* ============================== 8. Cleanup =============================== */
PRINT N'=== 8. Cleanup ===';

-- [A1.2] DROP TABLE (guarded by IF OBJECT_ID) - remove the scratch and copy tables created in sections 1-2.
IF OBJECT_ID(N'dbo.validation_scratch', N'U')      IS NOT NULL DROP TABLE dbo.validation_scratch;
IF OBJECT_ID(N'dbo.validation_product_copy', N'U') IS NOT NULL DROP TABLE dbo.validation_product_copy;
IF OBJECT_ID(N'tempdb..#validation_result') IS NOT NULL DROP TABLE #validation_result;

-- [A1.3] DROP DATABASE is demonstrated in 05_teardown.sql (it cannot run while connected to CampusMart).
PRINT N'04_validation.sql completed.';
GO
