USE [$(databaseName)]
BACKUP DATABASE [$(databaseName)] TO DISK = '$(databaseBackup)' WITH NOFORMAT, NOINIT, NAME = N'$(databaseName)-Full Database Backup', SKIP, NOREWIND, NOUNLOAD, STATS = 10
GO