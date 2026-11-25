/* =============================================================================
   CampusMart - 02_seed.sql                         SRS-CM-DB-1.0 / Deliverable D-02
   Purpose: Reference + demo data per section 4.5 (8+ categories, 6+ suppliers,
            30+ products, 20+ customers in 4+ cities, 50+ orders over 6+ months,
            120+ order items). All e-mails use example.com; no real personal data.
   Design : The whole script is ONE batch (no GO) so that the "already seeded" guard can
            stop it cleanly. Orders/lines are generated deterministically, set-based.
            Dates are relative to today, so the "last 180 days" reports are never empty.
   Re-run : Staging is reset every run; business data is loaded only into an EMPTY schema
            (run 05_teardown.sql + 01_schema.sql to start over).
   ============================================================================= */
USE CampusMart;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- [A1.4] TRUNCATE TABLE - reset the product staging table before re-seeding (staging table only, Appendix C).
TRUNCATE TABLE dbo.product_stage;

-- [A2.1] INSERT INTO - load a few sample import rows into the staging table.
INSERT INTO dbo.product_stage (sku, name, price)
VALUES (N'STG-001', N'Stapler Refill Pack', 9.50),
       (N'STG-002', N'Index Cards 100 pcs', 14.00),
       (N'STG-003', N'Desk Organizer', 55.00);

-- Guard: never double-load business data.
IF EXISTS (SELECT 1 FROM dbo.category)
BEGIN
    PRINT N'02_seed.sql: business data already present - nothing loaded. (Run 05_teardown.sql and 01_schema.sql to reset.)';
    RETURN;
END;

DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @product_count INT, @customer_count INT;

DECLARE @product_seed TABLE (
    sku           NVARCHAR(30)  NOT NULL,
    name          NVARCHAR(150) NOT NULL,
    price         DECIMAL(10,2) NOT NULL,
    stock_qty     INT           NOT NULL,
    category_name NVARCHAR(100) NOT NULL,
    supplier_name NVARCHAR(150) NULL
);
DECLARE @n TABLE (n INT NOT NULL PRIMARY KEY);

BEGIN TRY
    BEGIN TRANSACTION;   -- NFR-005: multi-table inserts are atomic

    /* ---- categories: 5 top-level + 5 children (single-level nesting, FR-002) ---- */
    -- [A2.1] INSERT INTO dbo.category - top-level categories first (no parent).
    INSERT INTO dbo.category (name, parent_id)
    VALUES (N'Stationery', NULL), (N'Electronics', NULL), (N'Food & Beverages', NULL),
           (N'Books', NULL), (N'Apparel', NULL);

    -- [A2.1] INSERT INTO dbo.category - child categories, parent resolved by name (portable, no hard-coded ids).
    INSERT INTO dbo.category (name, parent_id)
    SELECT c.child_name, p.id
    FROM (VALUES (N'Notebooks',            N'Stationery'),
                 (N'Writing Tools',        N'Stationery'),
                 (N'Computer Accessories', N'Electronics'),
                 (N'Snacks',               N'Food & Beverages'),
                 (N'Drinks',               N'Food & Beverages')) AS c (child_name, parent_name)
    INNER JOIN dbo.category AS p ON p.name = c.parent_name;

    /* ---- suppliers ---- */
    -- [A2.1] INSERT INTO dbo.supplier - seven suppliers in different cities.
    INSERT INTO dbo.supplier (name, contact_person, phone, city)
    VALUES (N'Nile Paper Trading',      N'Hany Fawzy',    N'+20-2-5550-0101',  N'Cairo'),
           (N'Upper Egypt Stationery',  N'Samir Gaber',   N'+20-97-5550-0102', N'Aswan'),
           (N'Delta Tech Distribution', N'Ola Mansour',   N'+20-50-5550-0103', N'Mansoura'),
           (N'Alex Food Supplies',      N'Wael Hosny',    N'+20-3-5550-0104',  N'Alexandria'),
           (N'Red Sea Beverages',       N'Dalia Kamel',   N'+20-65-5550-0105', N'Hurghada'),
           (N'Pyramid Books & Media',   N'Sherine Adel',  N'+20-2-5550-0106',  N'Giza'),
           (N'Sphinx Apparel Co.',      N'Magdy Lotfy',   N'+20-2-5550-0107',  N'Cairo');

    /* ---- products: 33 rows via a staging table variable, FKs resolved by name ---- */
    INSERT INTO @product_seed (sku, name, price, stock_qty, category_name, supplier_name)
    VALUES
      (N'NB-001', N'Spiral Notebook A4',        25.00, 120, N'Notebooks',            N'Nile Paper Trading'),
      (N'NB-002', N'Academic Agenda',           85.00,  60, N'Notebooks',            N'Nile Paper Trading'),
      (N'NB-003', N'Memo Pad Yellow',           18.50,   8, N'Notebooks',            N'Nile Paper Trading'),
      (N'NB-004', N'Sketch Book Premium',       95.00,  40, N'Notebooks',            N'Nile Paper Trading'),
      (N'NB-005', N'Lab Journal Hardcover',     70.00,  35, N'Notebooks',            N'Nile Paper Trading'),
      (N'WT-001', N'Ballpoint Pen Blue Box',    45.00, 200, N'Writing Tools',        N'Upper Egypt Stationery'),
      (N'WT-002', N'Whiteboard Marker Set',     60.00,  90, N'Writing Tools',        N'Upper Egypt Stationery'),
      (N'WT-003', N'Highlighter Set',           38.00,   7, N'Writing Tools',        N'Upper Egypt Stationery'),
      (N'WT-004', N'Mechanical Pencil 0.5mm',   32.00, 150, N'Writing Tools',        N'Upper Egypt Stationery'),
      (N'WT-005', N'Stapler Heavy Duty',       120.00,  25, N'Writing Tools',        N'Upper Egypt Stationery'),
      (N'CA-001', N'Wireless Mouse',           180.00,  45, N'Computer Accessories', N'Delta Tech Distribution'),
      (N'CA-002', N'USB Flash Drive 64GB',     140.00,  80, N'Computer Accessories', N'Delta Tech Distribution'),
      (N'CA-003', N'Phone Charger Fast',       250.00,  30, N'Computer Accessories', N'Delta Tech Distribution'),
      (N'CA-004', N'Laptop Stand Aluminum',    320.00,  12, N'Computer Accessories', N'Delta Tech Distribution'),
      (N'CA-005', N'Monitor Cleaning Kit',      95.00,   6, N'Computer Accessories', N'Delta Tech Distribution'),
      (N'CA-006', N'Bluetooth Headphones',     480.00,  18, N'Computer Accessories', N'Delta Tech Distribution'),
      (N'EL-001', N'Scientific Calculator',    290.00,  22, N'Electronics',          N'Delta Tech Distribution'),
      (N'EL-002', N'Power Bank 10000mAh',      380.00,   9, N'Electronics',          N'Delta Tech Distribution'),
      (N'EL-003', N'Smart Desk Lamp',          210.00,  15, N'Electronics',          N'Delta Tech Distribution'),
      (N'SN-001', N'Almond Granola',            55.00,  70, N'Snacks',               N'Alex Food Supplies'),
      (N'SN-002', N'Chocolate Bar Dark',        15.00, 300, N'Snacks',               N'Alex Food Supplies'),
      (N'SN-003', N'Salted Peanuts',            12.00, 250, N'Snacks',               N'Alex Food Supplies'),
      (N'SN-004', N'Sesame Bar',                 8.00, 180, N'Snacks',               N'Alex Food Supplies'),
      (N'DR-001', N'Smoothie Mix Berry',        35.00,  60, N'Drinks',               N'Red Sea Beverages'),
      (N'DR-002', N'Arabica Coffee Beans',     160.00,  40, N'Drinks',               N'Red Sea Beverages'),
      (N'DR-003', N'Sports Water Bottle',       75.00,  85, N'Drinks',               N'Red Sea Beverages'),
      (N'DR-004', N'Thermos Flask 500ml',      220.00,   8, N'Drinks',               N'Red Sea Beverages'),
      (N'BK-001', N'Database Systems Textbook',450.00,  20, N'Books',                N'Pyramid Books & Media'),
      (N'BK-002', N'Algorithms Handbook',      500.00,  14, N'Books',                N'Pyramid Books & Media'),
      (N'BK-003', N'English Dictionary',       130.00,  33, N'Books',                N'Pyramid Books & Media'),
      (N'AP-001', N'Campus Hoodie',            350.00,  28, N'Apparel',              N'Sphinx Apparel Co.'),
      (N'AP-002', N'Shoulder Bag Canvas',      190.00,   5, N'Apparel',              N'Sphinx Apparel Co.'),
      (N'AP-003', N'Campus Cap',                65.00,  48, N'Apparel',              NULL);

    -- [A2.1] INSERT INTO dbo.product - copy the seed rows, resolving category / supplier ids by name (supplier may be NULL, FR-006).
    INSERT INTO dbo.product (sku, name, price, stock_qty, category_id, supplier_id)
    SELECT s.sku, s.name, s.price, s.stock_qty, c.id, sp.id
    FROM @product_seed AS s
    INNER JOIN dbo.category AS c  ON c.name  = s.category_name
    LEFT  JOIN dbo.supplier AS sp ON sp.name = s.supplier_name;

    /* ---- customers: 20 rows, 5 cities, 2 inactive (soft-deleted) ---- */
    -- [A2.1] INSERT INTO dbo.customer - fictional customers on the example.com domain.
    INSERT INTO dbo.customer (full_name, email, city, is_active)
    VALUES (N'أحمد حسن',    N'ahmed.hassan@example.com',    N'Cairo',      1),
           (N'منى إبراهيم',  N'mona.ibrahim@example.com',    N'Alexandria', 1),
           (N'محمد علي',    N'mohamed.ali@example.com',     N'Giza',       1),
           (N'فاطمة السيد', N'fatma.elsayed@example.com',   N'Cairo',      1),
           (N'عمر خالد',    N'omar.khaled@example.com',     N'Mansoura',   1),
           (N'نور الدين',   N'nour.eldin@example.com',      N'Alexandria', 1),
           (N'ليلى مصطفى',  N'laila.mostafa@example.com',   N'Cairo',      1),
           (N'يوسف عادل',   N'youssef.adel@example.com',    N'Aswan',      1),
           (N'هدى سمير',    N'hoda.samir@example.com',      N'Giza',       0),
           (N'كريم فؤاد',   N'karim.fouad@example.com',     N'Cairo',      1),
           (N'دينا رأفت',   N'dina.raafat@example.com',     N'Alexandria', 1),
           (N'طارق شريف',   N'tarek.sherif@example.com',    N'Mansoura',   1),
           (N'رنا جمال',    N'rana.jamal@example.com',      N'Cairo',      1),
           (N'حسام وجدي',   N'hossam.wagdy@example.com',    N'Giza',       1),
           (N'ياسمين أشرف', N'yasmin.ashraf@example.com',   N'Alexandria', 1),
           (N'إسلام ماهر',  N'islam.maher@example.com',     N'Cairo',      1),
           (N'مريم صلاح',   N'mariam.salah@example.com',    N'Mansoura',   1),
           (N'بلال زكريا',  N'bilal.zakaria@example.com',   N'Aswan',      1),
           (N'آية عصام',    N'aya.essam@example.com',       N'Alexandria', 0),
           (N'زياد نبيل',   N'ziad.nabil@example.com',      N'Cairo',      1);

    SELECT @product_count = COUNT(*) FROM dbo.product;
    SELECT @customer_count = COUNT(*) FROM dbo.customer;

    /* ---- orders: 60 orders, one every 3 days, from 200 to 23 days ago (7 calendar months) ---- */
    INSERT INTO @n (n)
    SELECT TOP (60) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) FROM sys.all_objects;

    -- [A2.1] INSERT INTO dbo.[order] - header rows; order_no = ORD-YYYYMMDD-NNN (DR-03); totals filled in below.
    ;WITH cust AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY email) - 1 AS idx FROM dbo.customer
    )
    INSERT INTO dbo.[order] (order_no, customer_id, order_date, total_amount)
    SELECT N'ORD-' + CONVERT(NCHAR(8), d.order_dt, 112) + N'-' + RIGHT(N'00' + CAST(n.n AS NVARCHAR(3)), 3),
           c.id,
           d.order_dt,
           0
    FROM @n AS n
    CROSS APPLY (SELECT DATEADD(HOUR, 9 + (n.n % 9), CAST(DATEADD(DAY, n.n * 3 - 203, @today) AS DATETIME2)) AS order_dt) AS d
    INNER JOIN cust AS c ON c.idx = (n.n * 7) % @customer_count;      -- 7 is coprime with 20: every customer buys

    /* ---- order lines: 3 lines for odd order numbers, 2 for even -> 150 lines ---- */
    -- [A2.1] INSERT INTO dbo.order_item - unit_price snapshots the product price at the time of sale (Appendix C).
    ;WITH prod AS (
        SELECT id, price, ROW_NUMBER() OVER (ORDER BY sku) - 1 AS idx FROM dbo.product
    ),
    ord AS (
        SELECT id, CAST(RIGHT(order_no, 3) AS INT) AS n FROM dbo.[order]
    ),
    line AS (
        SELECT o.id AS order_id, o.n, j.j
        FROM ord AS o
        CROSS JOIN (VALUES (0), (1), (2)) AS j (j)
        WHERE j.j < 2 + (o.n % 2)
    )
    INSERT INTO dbo.order_item (order_id, product_id, quantity, unit_price)
    SELECT l.order_id,
           p.id,
           ((l.n + l.j * 2) % 4) + 1,                                  -- quantity 1..4
           p.price
    FROM line AS l
    INNER JOIN prod AS p ON p.idx = (l.n * 5 + l.j * 11) % @product_count;   -- 0 / 11 / 22 offsets are distinct => unique (order, product)

    -- [A2.3] UPDATE ... WHERE - order totals = sum of line totals (FR-014).
    UPDATE o
    SET    o.total_amount = t.total
    FROM   dbo.[order] AS o
    INNER JOIN (SELECT order_id, SUM(line_total) AS total FROM dbo.order_item GROUP BY order_id) AS t
            ON t.order_id = o.id;

    -- [A2.3] UPDATE ... WHERE - a customer registers one day before their first order, so history is coherent.
    UPDATE c
    SET    c.registered_at = DATEADD(DAY, -1, f.first_order)
    FROM   dbo.customer AS c
    INNER JOIN (SELECT customer_id, MIN(order_date) AS first_order FROM dbo.[order] GROUP BY customer_id) AS f
            ON f.customer_id = c.id;

    COMMIT TRANSACTION;

    PRINT N'02_seed.sql completed.';
    SELECT (SELECT COUNT(*) FROM dbo.category)   AS categories,
           (SELECT COUNT(*) FROM dbo.supplier)   AS suppliers,
           (SELECT COUNT(*) FROM dbo.product)    AS products,
           (SELECT COUNT(*) FROM dbo.customer)   AS customers,
           (SELECT COUNT(*) FROM dbo.[order])    AS orders,
           (SELECT COUNT(*) FROM dbo.order_item) AS order_items;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
