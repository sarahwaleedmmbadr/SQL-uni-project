/* =============================================================================
   CampusMart - 03_queries.sql                      SRS-CM-DB-1.0 / Deliverable D-03
   Purpose: Required reports R-01 .. R-23 (Appendix B). Each report is preceded by a
            comment stating its business purpose (NFR-003).
   Order  : R-01..R-20 are read-only (R-20 rebuilds a snapshot table).
            R-21..R-23 are the maintenance demonstrations; R-21 and R-22 are idempotent
            (running the script again changes nothing further) and R-23 always rolls back.
   Prereq : 01_schema.sql and 02_seed.sql have been executed.
   ============================================================================= */
USE CampusMart;
GO
SET NOCOUNT ON;
GO

-- [R-01] Business purpose: premium items - products priced above 100 EGP (operator >).
SELECT sku, name, price
FROM   dbo.product
WHERE  price > 100;
GO

-- [R-02] Business purpose: recent sign-ups - customers registered in the last 180 days (operator >=).
SELECT full_name, email, city, registered_at
FROM   dbo.customer
WHERE  registered_at >= DATEADD(DAY, -180, SYSUTCDATETIME());
GO

-- [R-03] Business purpose: re-order list - products with fewer than 10 units in stock (operator <).
SELECT sku, name, stock_qty
FROM   dbo.product
WHERE  stock_qty < 10;
GO

-- [R-04] Business purpose: small baskets - orders whose total is at most 500 EGP (operator <=).
SELECT order_no, order_date, total_amount
FROM   dbo.[order]
WHERE  total_amount <= 500;
GO

-- [R-05] Business purpose: customer service - the complete order history of one specific customer (operator =).
SELECT o.order_no, o.order_date, o.total_amount
FROM   dbo.[order]   AS o
INNER JOIN dbo.customer AS c ON c.id = o.customer_id
WHERE  c.email = N'ahmed.hassan@example.com'
ORDER BY o.order_date;
GO

-- [R-06] Business purpose: regional marketing - customers who are NOT located in Cairo (operator <>).
SELECT full_name, email, city
FROM   dbo.customer
WHERE  city <> N'Cairo';
GO

-- [R-07] Business purpose: printable price list, cheapest first (ORDER BY ASC).
SELECT sku, name, price
FROM   dbo.product
ORDER BY price ASC;
GO

-- [R-08] Business purpose: the five most expensive products (TOP + ORDER BY DESC).
SELECT TOP (5) sku, name, price
FROM   dbo.product
ORDER BY price DESC;
GO

-- [R-09] Business purpose: order-value overview - count, sum, average, minimum and maximum order totals.
SELECT COUNT(*)          AS order_count,
       SUM(total_amount) AS total_revenue,
       AVG(total_amount) AS average_order,
       MIN(total_amount) AS smallest_order,
       MAX(total_amount) AS largest_order
FROM   dbo.[order];
GO

-- [R-10] Business purpose: broad categories - categories that hold more than 3 products (GROUP BY ... HAVING).
SELECT c.name AS category_name, COUNT(*) AS product_count
FROM   dbo.category AS c
INNER JOIN dbo.product AS p ON p.category_id = c.id
GROUP BY c.name
HAVING COUNT(*) > 3
ORDER BY product_count DESC, category_name;
GO

-- [R-11] Business purpose: product search - names starting with 'S' (LIKE 'S%').
SELECT sku, name FROM dbo.product WHERE name LIKE N'S%';
GO

-- [R-12] Business purpose: product search - names containing 'M' anywhere (LIKE '%M%'; the collation is case-insensitive).
SELECT sku, name FROM dbo.product WHERE name LIKE N'%M%';
GO

-- [R-13] Business purpose: product search - names that begin with 'A' AND end with 'a' (LIKE 'A%' and LIKE '%a').
SELECT sku, name FROM dbo.product WHERE name LIKE N'A%' AND name LIKE N'%a';
GO

-- [R-14] Business purpose: product search - names containing 'mo' anywhere (LIKE '%mo%').
SELECT sku, name FROM dbo.product WHERE name LIKE N'%mo%';
GO

-- [R-15] Business purpose: product search - names whose second character is 'h' (LIKE '_h%').
SELECT sku, name FROM dbo.product WHERE name LIKE N'_h%';
GO

-- [R-16] Business purpose: merchandising view - products of a chosen set of categories (IN; ids resolved by name so the script is portable).
SELECT p.sku, p.name, p.category_id
FROM   dbo.product AS p
WHERE  p.category_id IN (SELECT id FROM dbo.category WHERE name IN (N'Notebooks', N'Writing Tools', N'Snacks'))
ORDER BY p.category_id, p.sku;
GO

-- [R-17] Business purpose: mid-range catalogue - products priced between 50 and 300 EGP (BETWEEN).
SELECT sku, name, price
FROM   dbo.product
WHERE  price BETWEEN 50 AND 300
ORDER BY price;
GO

-- [R-18] Business purpose: local campaign - active customers in Cairo or Alexandria, excluding accounts opened in the last 30 days (AND / OR / NOT).
SELECT full_name, email, city
FROM   dbo.customer
WHERE  is_active = 1
  AND  (city = N'Cairo' OR city = N'Alexandria')
  AND  NOT (registered_at > DATEADD(DAY, -30, SYSUTCDATETIME()));
GO

-- [R-19] Business purpose: monthly revenue snapshot for the finance team (GROUP BY month).
SELECT YEAR(order_date)  AS sales_year,
       MONTH(order_date) AS sales_month,
       COUNT(*)          AS order_count,
       SUM(total_amount) AS revenue
FROM   dbo.[order]
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY sales_year, sales_month;
GO

-- [R-20] Business purpose: materialise the monthly-sales summary as a physical table so reports do not
--        re-aggregate every time. Follows C-02/C-03: id (IDENTITY), created_at, updated_at.
IF OBJECT_ID(N'dbo.monthly_sales_snapshot', N'U') IS NOT NULL DROP TABLE dbo.monthly_sales_snapshot;
GO
-- [R-20] [A2.2] SELECT ... INTO - build the materialised monthly-sales snapshot from [order] and order_item.
SELECT IDENTITY(INT, 1, 1)      AS id,
       s.sales_year,
       s.sales_month,
       s.order_count,
       s.units_sold,
       s.revenue,
       SYSUTCDATETIME()         AS created_at,
       SYSUTCDATETIME()         AS updated_at
INTO   dbo.monthly_sales_snapshot
FROM  (SELECT YEAR(o.order_date)                    AS sales_year,
              MONTH(o.order_date)                   AS sales_month,
              COUNT(DISTINCT o.id)                  AS order_count,
              SUM(oi.quantity)                      AS units_sold,
              CAST(SUM(oi.line_total) AS DECIMAL(10,2)) AS revenue
       FROM   dbo.[order] AS o
       INNER JOIN dbo.order_item AS oi ON oi.order_id = o.id
       GROUP BY YEAR(o.order_date), MONTH(o.order_date)) AS s
ORDER BY s.sales_year, s.sales_month;
GO
-- SELECT ... INTO cannot declare keys or defaults, so add them afterwards to match the table conventions.
ALTER TABLE dbo.monthly_sales_snapshot ADD CONSTRAINT pk_monthly_sales_snapshot PRIMARY KEY (id);
ALTER TABLE dbo.monthly_sales_snapshot ADD CONSTRAINT df_monthly_sales_snapshot_created_at DEFAULT (SYSUTCDATETIME()) FOR created_at;
ALTER TABLE dbo.monthly_sales_snapshot ADD CONSTRAINT df_monthly_sales_snapshot_updated_at DEFAULT (SYSUTCDATETIME()) FOR updated_at;
GO
SELECT * FROM dbo.monthly_sales_snapshot ORDER BY sales_year, sales_month;
GO

-- [R-21] Business purpose: a customer cancelled one line of seeded order -057. Remove the line, put the
--        units back into stock and recompute the order total so FR-013 / FR-014 still hold.
--        Idempotent: only acts while the order still has exactly 3 lines, so FR-011 (>= 1 line) is never broken.
DECLARE @order_id INT, @line_id INT, @product_id INT, @qty INT;

SELECT TOP (1) @order_id = o.id
FROM   dbo.[order] AS o
WHERE  o.order_no LIKE N'ORD-%-057'
  AND  o.order_date < CAST(SYSUTCDATETIME() AS DATE)
  AND  (SELECT COUNT(*) FROM dbo.order_item AS x WHERE x.order_id = o.id) = 3;

IF @order_id IS NULL
BEGIN
    PRINT N'R-21: the cancelled line was already removed - nothing to do.';
    RETURN;
END;

SELECT TOP (1) @line_id = id, @product_id = product_id, @qty = quantity
FROM   dbo.order_item
WHERE  order_id = @order_id
ORDER BY id DESC;

BEGIN TRY
    BEGIN TRANSACTION;

    -- [R-21] [A2.4] DELETE FROM ... WHERE - remove the cancelled order line.
    DELETE FROM dbo.order_item
    WHERE  id = @line_id;

    -- Return the cancelled units to stock.
    UPDATE dbo.product SET stock_qty = stock_qty + @qty WHERE id = @product_id;

    -- Order total must equal the sum of its remaining line totals.
    UPDATE dbo.[order]
    SET    total_amount = (SELECT SUM(line_total) FROM dbo.order_item WHERE order_id = @order_id)
    WHERE  id = @order_id;

    COMMIT TRANSACTION;
    PRINT N'R-21: cancelled line removed.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

-- [R-22] Business purpose: price correction - the blue ballpoint box was mis-priced; set the correct price.
--        Idempotent (fixed target value). Past order lines keep their old unit_price snapshot (Appendix C).
-- [R-22] [A2.3] UPDATE ... WHERE - correct the price of one specific product (the audit trigger refreshes updated_at).
UPDATE dbo.product
SET    price = 47.50
WHERE  sku = N'WT-001';

SELECT sku, name, price, updated_at FROM dbo.product WHERE sku = N'WT-001';
GO

-- [R-23] Business purpose: show that a bulk customer import can be undone. Three customers are inserted in ONE
--        statement, counted, and then the whole transaction is rolled back.
BEGIN TRANSACTION;

-- [R-23] [A2.6] INSERT INTO (multi-row) inside a transaction that is rolled back below.
INSERT INTO dbo.customer (full_name, email, city)
VALUES (N'Rollback Test One',   N'rollback.one@example.com',   N'Cairo'),
       (N'Rollback Test Two',   N'rollback.two@example.com',   N'Giza'),
       (N'Rollback Test Three', N'rollback.three@example.com', N'Aswan');

SELECT COUNT(*) AS rows_visible_inside_transaction
FROM   dbo.customer
WHERE  email LIKE N'rollback.%@example.com';

-- [R-23] [A2.6] [A5.2] ROLLBACK TRANSACTION - undo the multi-row insert (identity values consumed by the insert are not reused).
ROLLBACK TRANSACTION;

SELECT COUNT(*) AS rows_remaining_after_rollback
FROM   dbo.customer
WHERE  email LIKE N'rollback.%@example.com';
GO
