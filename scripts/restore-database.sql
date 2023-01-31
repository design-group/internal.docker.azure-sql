USE [master]
RESTORE DATABASE [$(databaseName)] FROM DISK = N'/backups/$(databaseBackup).bak' WITH FILE = 1, NOUNLOAD, REPLACE, STATS = 10
GO