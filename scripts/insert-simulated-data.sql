-- insert-simulated-data.sql
-- This script is used to insert data from a CSV file into the corresponding table.
-- The CSV file's name, passed as a variable, should match the table name.

DECLARE @TableName NVARCHAR(128)
DECLARE @CSVFilePath NVARCHAR(255)
DECLARE @Sql NVARCHAR(MAX)

-- Extract the table name from the CSV file path
SET @CSVFilePath = '$(csvFile)'
SET @TableName = REPLACE(RIGHT(@CSVFilePath, CHARINDEX('/', REVERSE('/' + @CSVFilePath)) - 1), '.csv', '')

-- Dynamic SQL to import data from CSV file into the table
SET @Sql = 'BULK INSERT ' + QUOTENAME(@TableName) + '
FROM ''' + @CSVFilePath + '''
WITH
(
    FIRSTROW = 2, -- Assumes that the first row contains column headers
    FIELDTERMINATOR = '','', -- CSV field delimiter
    ROWTERMINATOR = ''\n'', -- CSV row delimiter
    TABLOCK
)'

-- Execute the dynamic SQL
EXEC sp_executesql @Sql
