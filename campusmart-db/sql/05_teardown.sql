/* =============================================================================
   CampusMart - 05_teardown.sql                     SRS-CM-DB-1.0 / Deliverable D-05
   Purpose: Clean, repeatable removal of the whole schema and the database.
            Safe to run when the database (or any table) is already gone.
   Warning: ALL CampusMart data is permanently deleted.
   ============================================================================= */
SET NOCOUNT ON;
GO

USE master;
GO

-- [A1.2] DROP TABLE, each guarded by IF OBJECT_ID('dbo.<table>', 'U') IS NOT NULL - remove every table, children before
--        parents so foreign keys never block a drop. Runs inside CampusMart through dynamic SQL, so this script
--        also works when the database does not exist (the IF DB_ID guard skips it).
IF DB_ID(N'CampusMart') IS NOT NULL
    EXEC (N'USE CampusMart;
IF OBJECT_ID(''dbo.order_item'', ''U'')             IS NOT NULL DROP TABLE dbo.order_item;
IF OBJECT_ID(''dbo.[order]'', ''U'')                IS NOT NULL DROP TABLE dbo.[order];
IF OBJECT_ID(''dbo.product'', ''U'')                IS NOT NULL DROP TABLE dbo.product;
IF OBJECT_ID(''dbo.customer'', ''U'')               IS NOT NULL DROP TABLE dbo.customer;
IF OBJECT_ID(''dbo.supplier'', ''U'')               IS NOT NULL DROP TABLE dbo.supplier;
IF OBJECT_ID(''dbo.category'', ''U'')               IS NOT NULL DROP TABLE dbo.category;
IF OBJECT_ID(''dbo.product_stage'', ''U'')          IS NOT NULL DROP TABLE dbo.product_stage;
IF OBJECT_ID(''dbo.customer_stage'', ''U'')         IS NOT NULL DROP TABLE dbo.customer_stage;
IF OBJECT_ID(''dbo.monthly_sales_snapshot'', ''U'') IS NOT NULL DROP TABLE dbo.monthly_sales_snapshot;
IF OBJECT_ID(''dbo.validation_scratch'', ''U'')     IS NOT NULL DROP TABLE dbo.validation_scratch;
IF OBJECT_ID(''dbo.validation_product_copy'', ''U'') IS NOT NULL DROP TABLE dbo.validation_product_copy;');
GO

-- [A1.3] DROP DATABASE, guarded by IF DB_ID('CampusMart') IS NOT NULL - remove the database itself.
--        Other sessions are disconnected first (ROLLBACK IMMEDIATE), otherwise the drop would fail.
IF DB_ID(N'CampusMart') IS NOT NULL
BEGIN
    ALTER DATABASE CampusMart SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE CampusMart;
    PRINT N'Database CampusMart dropped.';
END
ELSE
    PRINT N'Database CampusMart does not exist - nothing to drop.';
GO
