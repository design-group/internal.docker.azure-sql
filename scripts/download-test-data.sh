#!/bin/bash
set -e

echo "Downloading sample databases for testing..."

# Create test fixtures directory
mkdir -p test/fixtures

# Download Northwind .bacpac (small, classic example)
echo "Downloading Northwind.bacpac..."
curl -L "https://github.com/urfnet/URF.Core.Sample/raw/master/Northwind.Data/Sql/northwind.bacpac" \
  -o test/fixtures/Northwind.bacpac

# Download WideWorldImporters Standard .bacpac (modern example)
echo "Downloading WideWorldImporters-Standard.bacpac..."
curl -L "https://github.com/Microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Standard.bacpac" \
  -o test/fixtures/WideWorldImporters-Standard.bacpac

# Alternative: Create a small custom test database
echo "Creating custom test database script..."
cat > test/fixtures/create-testdb.sql << 'EOF'
CREATE DATABASE TestDB;
GO

USE TestDB;
GO

-- Create sample tables
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100),
    City NVARCHAR(50),
    CreatedDate DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(100) NOT NULL,
    Price DECIMAL(10,2),
    CategoryID INT,
    CreatedDate DATETIME2 DEFAULT GETUTCDATE()
);

CREATE TABLE Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID INT FOREIGN KEY REFERENCES Customers(CustomerID),
    OrderDate DATETIME2 DEFAULT GETUTCDATE(),
    TotalAmount DECIMAL(10,2)
);

-- Insert sample data
INSERT INTO Customers (CustomerName, Email, City) VALUES
('Acme Corp', 'contact@acme.com', 'New York'),
('TechStart Inc', 'hello@techstart.com', 'San Francisco'),
('Global Solutions', 'info@global.com', 'Chicago'),
('Innovation Labs', 'team@innovation.com', 'Austin'),
('Future Systems', 'sales@future.com', 'Seattle');

INSERT INTO Products (ProductName, Price, CategoryID) VALUES
('Widget Pro', 29.99, 1),
('Super Widget', 49.99, 1),
('Mega Widget', 99.99, 1),
('Basic Tool', 19.99, 2),
('Advanced Tool', 39.99, 2);

INSERT INTO Orders (CustomerID, TotalAmount) VALUES
(1, 129.97),
(2, 49.99),
(3, 199.98),
(4, 79.98),
(5, 29.99);

PRINT 'TestDB created and populated successfully';
GO
EOF

echo "Sample database files ready in test/fixtures/"
ls -la test/fixtures/
