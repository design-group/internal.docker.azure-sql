USE [master]
RESTORE DATABASE [$(databaseName)] FROM DISK = N'$(databaseBackup)' WITH FILE = 1, NOUNLOAD, REPLACE, STATS = 10
GO
