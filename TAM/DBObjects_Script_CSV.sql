--SELECT dbo.CheckFileExists('D:\Test.pdf') AS FileExistsStatus;

--Function to validate the Attachment Exist on location or Not
CREATE OR ALTER FUNCTION dbo.CheckFileExists (@filePath NVARCHAR(255))
RETURNS NVARCHAR(50)
AS
BEGIN
    IF LEN(@filePath)<1 or  UPPER(@filePath)='NULL'
	BEGIN
	 RETURN 'No Attachment Record Exists'
	END
    DECLARE @isExists INT;

    EXEC master.dbo.xp_fileexist @filePath, @isExists OUTPUT;

    RETURN CASE 
               WHEN @isExists = 1 THEN ''
               ELSE 'No Attachment file in Folder'
           END;
END;
GO

/*<br>
##########################################################################<br>
-- Name : gNxtSystems
-- Date             : 07/11/2024
-- Author           :   
-- Company          :   gNxtSystems
-- Purpose          :   Generate Attachment File Data with Provided Input CSV File data
-- Usage        
-- Impact   :<br>
-- Required grants  :   
-- Called by        :   
##########################################################################<br>
-- ver  user    date        change  <br>
-- 
##########################################################################<br>
*/

CREATE OR ALTER PROCEDURE [dbo].[GenerateAttCSVFileForTAM]
	@EpicBusinessInputFilePath NVARCHAR(255),
	@EpicIndividualInputFilePath NVARCHAR(255),
	@AttachmentFolderPath NVARCHAR(255),
	@EasyLinkOutPutFolderPath NVARCHAR(255)
AS
BEGIN



DECLARE @IsEpicBusinessFileExists INT
DECLARE @IsEpicIndividualFileExists INT
DECLARE @IsAttachmentFolderExists NVARCHAR(500)
DECLARE @AttachmentResult TABLE (output NVARCHAR(255))
DECLARE @IsEasyOutPutFolderExists NVARCHAR(500)
DECLARE @EasyOutPutResult TABLE (output NVARCHAR(255))
DECLARE @FinalMessage VARCHAR(150) = ''
DECLARE @bcpBusinessFileCommand NVARCHAR(400)
DECLARE @bcpIndividualFileCommand NVARCHAR(400)

--Validating File Location
EXEC xp_fileexist @EpicBusinessInputFilePath, @IsEpicBusinessFileExists OUTPUT
EXEC xp_fileexist @EpicIndividualInputFilePath, @IsEpicIndividualFileExists OUTPUT

--Validating Folder Location
SET @IsAttachmentFolderExists = 'IF EXIST "' + @AttachmentFolderPath + '" (echo Folder exists) ELSE (echo Folder does not exist)'
SET @IsEasyOutPutFolderExists = 'IF EXIST "' + @EasyLinkOutPutFolderPath + '" (echo Folder exists) ELSE (echo Folder does not exist)'

INSERT INTO @AttachmentResult (output)
EXEC xp_cmdshell @IsAttachmentFolderExists
INSERT INTO @EasyOutPutResult (output)
EXEC xp_cmdshell @IsEasyOutPutFolderExists

----Generate Error Messages if any 
SET @FinalMessage=''
IF @IsEpicBusinessFileExists != 1 
SET @FinalMessage='Epic Business Input File does not exists.'
IF @IsEpicIndividualFileExists != 1 
SET @FinalMessage='Epic Individual Input File does not exists.'
-- Check the output
IF NOT EXISTS (SELECT 1 FROM @AttachmentResult WHERE output = 'Folder exists')
SET @FinalMessage = @FinalMessage +CHAR(10)+'Attachment Folder does not exists.'
-- Check the output
IF NOT EXISTS (SELECT 1 FROM @EasyOutPutResult WHERE output = 'Folder exists')
SET @FinalMessage = @FinalMessage +CHAR(10)+'EZLynx Output Folder does not exists.'
	
PRINT @FinalMessage

IF LEN(@FinalMessage) > 0
BEGIN
    RETURN;
END
ELSE
BEGIN


----Fetching data from Input Business CSV File
IF OBJECT_ID('tempdb..##TempBusinessInput') IS NOT NULL DROP TABLE ##TempBusinessInput

CREATE TABLE ##TempBusinessInput (
    [Prior Account ID] NVARCHAR(50),
    [Epic Lookup Code] NVARCHAR(50)
);

-- Construct the BULK INSERT command using dynamic SQL
DECLARE @sql1 NVARCHAR(MAX);
SET @sql1 = N'
    BULK INSERT ##TempBusinessInput
    FROM ''' + @EpicBusinessInputFilePath + '''
    WITH (
        FIELDTERMINATOR = '','',
        ROWTERMINATOR = ''\n'',
        FIRSTROW = 2 -- Skip header if needed
    );
';

-- Execute the dynamic SQL
EXEC sp_executesql @sql1;


----Fetching data from Input Individual CSV File
IF OBJECT_ID('tempdb..##TempIndividualInput') IS NOT NULL DROP TABLE ##TempIndividualInput

-- Create a temporary table EpicIndividualInput
CREATE TABLE ##TempIndividualInput (
    [Prior Account ID] NVARCHAR(50),
    [Epic Lookup Code] NVARCHAR(50)
);

-- Construct the BULK INSERT command using dynamic SQL
DECLARE @sql2 NVARCHAR(MAX);
SET @sql2 = N'
    BULK INSERT ##TempIndividualInput
    FROM ''' + @EpicIndividualInputFilePath + '''
    WITH (
        FIELDTERMINATOR = '','',
        ROWTERMINATOR = ''\n'',
        FIRSTROW = 2 -- Skip header if needed
    );
';

-- Execute the dynamic SQL
EXEC sp_executesql @sql2;

-- Insert physical path of attachments in a temp table
IF OBJECT_ID('tempdb..##AttachmentStatus') IS NOT NULL DROP TABLE ##AttachmentStatus
CREATE TABLE ##AttachmentStatus
(REC VARCHAR(25),
AttachDate DATE,
Path Varchar(255));

WITH TempPath(REC, AttachDate, Path)
AS 
(
    SELECT REC, TRY_CONVERT(DATE, CONCAT(SUBSTRING(ATCHDATE, 1, 4), '-', SUBSTRING(ATCHDATE, 5,2), '-', SUBSTRING(ATCHDATE, 7, 2))) AS AttachDate,
        CASE 
            WHEN type = '*M' THEN CONCAT(@AttachmentFolderPath, '\', SUBSTRING(ATCHDATE, 1, 4), '\', SUBSTRING(ATCHDATE, 5, 4), '\', SEQNO, '.eml')
			WHEN type = 'JPX' THEN CONCAT(@AttachmentFolderPath, '\', SUBSTRING(ATCHDATE, 1, 4), '\', SUBSTRING(ATCHDATE, 5, 4), '\', SEQNO, '.jpeg')
			WHEN type = 'DOX' THEN CONCAT(@AttachmentFolderPath, '\', SUBSTRING(ATCHDATE, 1, 4), '\', SUBSTRING(ATCHDATE, 5, 4), '\', SEQNO, '.docx')
            ELSE CONCAT(@AttachmentFolderPath, '\', SUBSTRING(ATCHDATE, 1, 4), '\', SUBSTRING(ATCHDATE, 5, 4), '\', SEQNO, '.', TYPE)
        END AS Path
    FROM ATTACH
)
INSERT INTO ##AttachmentStatus (REC, AttachDate, Path)
SELECT [REC], [AttachDate], [Path]
FROM TempPath WHERE AttachDate IS NOT NULL;

--Insert data into EpicEasyBusinessOutput Table by Joining Business CSV File & ApplicantAttachment Table
IF EXISTS(SELECT 1 FROM sys.Objects WHERE  Object_id = OBJECT_ID(N'dbo.EpicEasyBusinessOutput') AND Type = N'U')
BEGIN
   DROP TABLE [TAM].[DBO].[EpicEasyBusinessOutput]
END

SELECT A1.[Prior Account ID], A1.[Epic Lookup Code],'Cust' AS [Account Type], '' AS [Epic Policy ID],'' AS [Epic Policy Number],'' AS [Epic Policy Effective Date],'' AS [Epic Policy Expiration Date],'' AS [Epic Line ID],'' AS [Epic Line Type],'' AS [Epic Activity ID],'' AS [Epic Activity Code],'' AS [Activity Entered Date],'' AS [Activity Associated To],B1.Path AS [File Name On Disk],'Account' AS [Attach To],'' AS [File Description], dbo.CheckFileExists(B1.Path) AS [Comments], format(B1.AttachDate, 'd', 'en-US') AS [Received],'Public' AS [Security],0 AS [Client Accessible],'' AS [Client Accessible Expiration],'' AS [Folder],'' AS [Sub-Folder 1],'' AS [Sub-Folder 2],'' AS [Sub-Folder 3],'' AS [Sub-Folder 4],'' AS [Sub-Folder 5],'' AS [Exception Reason],'' AS [Success/Failure] into [TAM].[DBO].[EpicEasyBusinessOutput]
FROM ##TempBusinessInput A1 INNER JOIN ##AttachmentStatus B1
ON A1.[Prior Account ID] = B1.[REC]


--Code to Generate BusinessOutput.csv 
SET @bcpBusinessFileCommand = 'bcp "select * from [TAM].[DBO].[EpicEasyBusinessOutput]" queryout "'+@EasyLinkOutPutFolderPath+'\BusinessOutput.csv" -c -t"," -T -S CPC-leigh-5SAXQ'
EXEC xp_cmdshell @bcpBusinessFileCommand;


--Insert data into EpicEasyIndividualOutput Table by Joining Individual CSV File & ApplicantAttachment Table
IF EXISTS(SELECT 1 FROM sys.Objects WHERE  Object_id = OBJECT_ID(N'dbo.EpicEasyIndividualOutput') AND Type = N'U')
BEGIN
   DROP TABLE [TAM].[DBO].[EpicEasyIndividualOutput]
END

SELECT A1.[Prior Account ID], A1.[Epic Lookup Code],'Cust' AS [Account Type], '' AS [Epic Policy ID],'' AS [Epic Policy Number],'' AS [Epic Policy Effective Date],'' AS [Epic Policy Expiration Date],'' AS [Epic Line ID],'' AS [Epic Line Type],'' AS [Epic Activity ID],'' AS [Epic Activity Code],'' AS [Activity Entered Date],'' AS [Activity Associated To], B1.Path AS [File Name On Disk],'Account' AS [Attach To],'' AS [File Description], dbo.CheckFileExists(B1.Path) AS [Comments], format(B1.AttachDate, 'd', 'en-US') AS [Received],'Public' AS [Security],0 AS [Client Accessible],'' AS [Client Accessible Expiration],'' AS [Folder],'' AS [Sub-Folder 1],'' AS [Sub-Folder 2],'' AS [Sub-Folder 3],'' AS [Sub-Folder 4],'' AS [Sub-Folder 5],'' AS [Exception Reason],'' AS [Success/Failure] into [TAM].[DBO].[EpicEasyIndividualOutput]
FROM ##TempIndividualInput A1 INNER JOIN  ##AttachmentStatus B1
ON A1.[Prior Account ID] = B1.REC


--Code to Generate IndividualOutput.csv 
SET @bcpBusinessFileCommand = 'bcp "select * from [TAM].[DBO].[EpicEasyIndividualOutput]" queryout "'+@EasyLinkOutPutFolderPath+'\IndividualOutput.csv" -c -t"," -T -S CPC-leigh-5SAXQ'
EXEC xp_cmdshell @bcpBusinessFileCommand;

END
END
GO