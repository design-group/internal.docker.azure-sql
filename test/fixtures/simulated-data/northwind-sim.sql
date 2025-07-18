-- northwind-sim.sql
-- Fixed version - This script adds permanent test tables to Northwind database with 'z' prefix
-- Place this file in your /simulated-data directory

-- Check if Northwind database exists first
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'Northwind')
BEGIN
    PRINT 'Northwind database not found - skipping simulated data';
    RETURN;
END

USE [Northwind];
GO

PRINT 'Adding simulated data tables to Northwind database...';
GO

-- Create our test customer table (similar to Customers but clearly ours)
IF OBJECT_ID('dbo.zTestCustomers') IS NOT NULL
    DROP TABLE dbo.zTestCustomers;

CREATE TABLE dbo.zTestCustomers (
    TestCustomerID NCHAR(5) NOT NULL PRIMARY KEY,
    CompanyName NVARCHAR(40) NOT NULL,
    ContactName NVARCHAR(30),
    ContactTitle NVARCHAR(30),
    Address NVARCHAR(60),
    City NVARCHAR(15),
    Region NVARCHAR(15),
    PostalCode NVARCHAR(10),
    Country NVARCHAR(15),
    Phone NVARCHAR(24),
    Fax NVARCHAR(24),
    CreatedBy NVARCHAR(50) DEFAULT 'SimulatedDataScript',
    CreatedDate DATETIME2 DEFAULT GETUTCDATE()
);

-- Create test orders table
IF OBJECT_ID('dbo.zTestOrders') IS NOT NULL
    DROP TABLE dbo.zTestOrders;

CREATE TABLE dbo.zTestOrders (
    TestOrderID INT IDENTITY(1,1) PRIMARY KEY,
    TestCustomerID NCHAR(5),
    OrderDate DATETIME,
    RequiredDate DATETIME,
    ShippedDate DATETIME,
    Freight MONEY DEFAULT 0,
    ShipName NVARCHAR(40),
    ShipAddress NVARCHAR(60),
    ShipCity NVARCHAR(15),
    ShipRegion NVARCHAR(15),
    ShipPostalCode NVARCHAR(10),
    ShipCountry NVARCHAR(15),
    CreatedDate DATETIME2 DEFAULT GETUTCDATE(),
    FOREIGN KEY (TestCustomerID) REFERENCES dbo.zTestCustomers(TestCustomerID)
);

-- Create test products table
IF OBJECT_ID('dbo.zTestProducts') IS NOT NULL
    DROP TABLE dbo.zTestProducts;

CREATE TABLE dbo.zTestProducts (
    TestProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(40) NOT NULL,
    CategoryName NVARCHAR(50),
    UnitPrice MONEY DEFAULT 0,
    UnitsInStock SMALLINT DEFAULT 0,
    Discontinued BIT DEFAULT 0,
    CreatedDate DATETIME2 DEFAULT GETUTCDATE()
);

-- Insert test customers
INSERT INTO dbo.zTestCustomers (TestCustomerID, CompanyName, ContactName, ContactTitle, Address, City, Region, PostalCode, Country, Phone, Fax)
VALUES 
('TEST1', 'Docker Test Company', 'John Container', 'CEO', '123 Container Street', 'Docker City', 'CA', '12345', 'USA', '(555) 123-4567', '(555) 123-4568'),
('TEST2', 'Simulated Data Corp', 'Jane Database', 'CTO', '456 Database Avenue', 'SQL Town', 'TX', '67890', 'USA', '(555) 234-5678', '(555) 234-5679'),
('TEST3', 'Development LLC', 'Bob Developer', 'Lead Dev', '789 Code Boulevard', 'Dev City', 'NY', '11111', 'USA', '(555) 345-6789', '(555) 345-6790'),
('TEST4', 'Testing Solutions Inc', 'Alice Tester', 'QA Manager', '321 Test Lane', 'Bug City', 'FL', '22222', 'USA', '(555) 456-7890', '(555) 456-7891'),
('TEST5', 'Cloud Native Co', 'Charlie Kubernetes', 'DevOps', '654 Cloud Drive', 'Container Town', 'WA', '33333', 'USA', '(555) 567-8901', '(555) 567-8902');

-- Insert test products
INSERT INTO dbo.zTestProducts (ProductName, CategoryName, UnitPrice, UnitsInStock)
VALUES 
('Docker Container License', 'Software', 299.99, 100),
('SQL Server Instance', 'Database', 1499.99, 50),
('Development Environment', 'Tools', 99.99, 200),
('Testing Framework', 'Tools', 149.99, 75),
('Cloud Storage Package', 'Services', 49.99, 500),
('Backup Solution', 'Services', 199.99, 25),
('Monitoring Dashboard', 'Software', 79.99, 150),
('Security Scanner', 'Software', 349.99, 30);

-- Insert test orders
INSERT INTO dbo.zTestOrders (TestCustomerID, OrderDate, RequiredDate, Freight, ShipName, ShipAddress, ShipCity, ShipRegion, ShipPostalCode, ShipCountry)
VALUES 
('TEST1', GETDATE(), DATEADD(day, 7, GETDATE()), 25.50, 'Docker Test Company', '123 Container Street', 'Docker City', 'CA', '12345', 'USA'),
('TEST2', GETDATE(), DATEADD(day, 10, GETDATE()), 45.75, 'Simulated Data Corp', '456 Database Avenue', 'SQL Town', 'TX', '67890', 'USA'),
('TEST3', DATEADD(day, -1, GETDATE()), DATEADD(day, 5, GETDATE()), 15.25, 'Development LLC', '789 Code Boulevard', 'Dev City', 'NY', '11111', 'USA'),
('TEST4', DATEADD(day, -2, GETDATE()), DATEADD(day, 8, GETDATE()), 35.00, 'Testing Solutions Inc', '321 Test Lane', 'Bug City', 'FL', '22222', 'USA'),
('TEST5', GETDATE(), DATEADD(day, 14, GETDATE()), 55.50, 'Cloud Native Co', '654 Cloud Drive', 'Container Town', 'WA', '33333', 'USA');

-- Create execution tracking table
IF OBJECT_ID('dbo.zSimulatedDataLog') IS NOT NULL
    DROP TABLE dbo.zSimulatedDataLog;

CREATE TABLE dbo.zSimulatedDataLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    ScriptName NVARCHAR(100),
    ExecutionTime DATETIME2 DEFAULT GETUTCDATE(),
    TableName NVARCHAR(100),
    RecordsAdded INT,
    Notes NVARCHAR(500),
    SessionID INT DEFAULT @@SPID
);

-- Log this execution (FIXED VERSION - No subqueries in VALUES)
DECLARE @CustomerCount INT;
DECLARE @ProductCount INT;
DECLARE @OrderCount INT;

SELECT @CustomerCount = COUNT(*) FROM dbo.zTestCustomers;
SELECT @ProductCount = COUNT(*) FROM dbo.zTestProducts;
SELECT @OrderCount = COUNT(*) FROM dbo.zTestOrders;

INSERT INTO dbo.zSimulatedDataLog (ScriptName, TableName, RecordsAdded, Notes)
VALUES 
('northwind-sim.sql', 'zTestCustomers', @CustomerCount, 'Created test customers table with sample data'),
('northwind-sim.sql', 'zTestProducts', @ProductCount, 'Created test products table with sample data'),
('northwind-sim.sql', 'zTestOrders', @OrderCount, 'Created test orders table with sample data');

-- Show summary of what we created
SELECT 
    'Test Tables Created' as Summary,
    'zTestCustomers' as TableName,
    COUNT(*) as RecordCount
FROM dbo.zTestCustomers
UNION ALL
SELECT 
    'Test Tables Created' as Summary,
    'zTestProducts' as TableName,
    COUNT(*) as RecordCount
FROM dbo.zTestProducts
UNION ALL
SELECT 
    'Test Tables Created' as Summary,
    'zTestOrders' as TableName,
    COUNT(*) as RecordCount
FROM dbo.zTestOrders;

-- Show sample data
SELECT 'Sample Test Customers' as DataType, TestCustomerID, CompanyName, ContactName, City, Country
FROM dbo.zTestCustomers
ORDER BY TestCustomerID;

-- Show the execution log
SELECT 
    LogID,
    ScriptName,
    ExecutionTime,
    TableName,
    RecordsAdded,
    Notes
FROM dbo.zSimulatedDataLog
ORDER BY ExecutionTime DESC;

-- List all our test tables
SELECT 
    'Our Test Tables in Northwind' as Info,
    name as TableName,
    create_date as CreatedAt
FROM sys.tables 
WHERE name LIKE 'z%'
ORDER BY name;

PRINT 'Northwind simulated data script completed successfully!';
PRINT 'Created tables: zTestCustomers, zTestProducts, zTestOrders, zSimulatedDataLog';

-- Show final counts
DECLARE @TotalRecords INT;
SELECT @TotalRecords = @CustomerCount + @ProductCount + @OrderCount;
PRINT 'Total test records: ' + CAST(@TotalRecords AS NVARCHAR(10));

GO