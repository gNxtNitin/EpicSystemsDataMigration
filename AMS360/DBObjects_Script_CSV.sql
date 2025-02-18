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

CREATE OR ALTER PROCEDURE [dbo].[GenerateAttCSVFileForAMS360]
	@EpicBusinessInputFilePath NVARCHAR(255),
	@EpicIndividualInputFilePath NVARCHAR(255),
	@AttachmentFolderPath NVARCHAR(255),
	@AMS360OutPutFolderPath NVARCHAR(255)
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
SET @IsEasyOutPutFolderExists = 'IF EXIST "' + @AMS360OutPutFolderPath + '" (echo Folder exists) ELSE (echo Folder does not exist)'

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
SET @FinalMessage = @FinalMessage +CHAR(10)+'AMS360 Output Folder does not exists.'
	
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

-- Generate File Location info for customers

DECLARE @ErrorNo INT, 
        @Const_LTBL_NOTES SMALLINT, 
        @Const_LTBL_TRAN SMALLINT, 
        @Const_LTBL_ROUT SMALLINT, 
        @Const_LTBL_EFLDR SMALLINT, 
        @Const_LTBL_EFORM SMALLINT, 
        @Const_LTBL_EFRMDTL SMALLINT, 
        @EntityType SMALLINT;

-- Assigning constants
SELECT @Const_LTBL_NOTES = 45, 
       @Const_LTBL_TRAN = 185, 
       @Const_LTBL_ROUT = 959, 
       @Const_LTBL_EFLDR = 715, 
       @Const_LTBL_EFORM = 711, 
       @Const_LTBL_EFRMDTL = 713, 
       @EntityType = 4;

DECLARE @DocCount INT;

DECLARE @DocA TABLE (
    DocAId UNIQUEIDENTIFIER, 
    CustomerId UNIQUEIDENTIFIER, 
    CustNo INT, 
    AttDate DATETIME
);

DECLARE @tmp_eform_folderids TABLE (
    ElfFormFldrId UNIQUEIDENTIFIER, 
    CustomerId UNIQUEIDENTIFIER, 
    CustNo INT, 
    AttDate DATETIME
);

DECLARE @tmp_eformids TABLE (
    ElfFormId UNIQUEIDENTIFIER, 
    CustomerId UNIQUEIDENTIFIER, 
    CustNo INT, 
    AttDate DATETIME
);

INSERT INTO @tmp_eform_folderids
SELECT eff.ElfFormFldrId, cust1.CustId, cust1.CustNo, eff.EnteredDate 
FROM AFW_ElfFormFolder eff 
INNER JOIN AFW_Customer cust1 ON cust1.CustId = eff.CustId;

INSERT INTO @tmp_eformids
SELECT eform.ElfFormId, a.CustomerId, a.CustNo, eform.EnteredDate 
FROM AFW_ElfForm eform 
INNER JOIN @tmp_eform_folderids a ON eform.ElfFormFldrId = a.ElfFormFldrId;

INSERT INTO @DocA
	SELECT docre.DocAId, cust1.CustId, cust1.CustNo, notes.EnteredDate 
	FROM AFW_Notes notes 
	INNER JOIN AFW_DocRelation docre 
		ON docre.AttachId = notes.NoteId AND docre.AttachType = @Const_LTBL_NOTES 
	INNER JOIN AFW_Customer cust1 
		ON notes.EntityId = CONVERT(VARCHAR(36), cust1.CustId) 
	WHERE notes.EntityType = @EntityType

	UNION ALL

	SELECT docre.DocAId, cust1.CustId, cust1.CustNo, docr.EnteredDate 
	FROM AFW_DocRouting docr 
	INNER JOIN AFW_DocRelation docre 
		ON docre.AttachId = docr.DocRoId AND docre.AttachType = @Const_LTBL_ROUT 
	INNER JOIN AFW_Customer cust1 
		ON docr.EntityId = CONVERT(VARCHAR(36), cust1.CustId) 
	WHERE docr.EntityType = @EntityType

	UNION ALL

	SELECT docre.DocAId, cust1.CustId, cust1.CustNo, trans.EnteredDate 
	FROM AFW_Transaction trans 
	INNER JOIN AFW_DocRelation docre 
		ON docre.AttachId = trans.TranId AND docre.AttachType = @Const_LTBL_TRAN 
	INNER JOIN AFW_Customer cust1 
		ON trans.EntityId = CONVERT(VARCHAR(36), cust1.CustId) 
	WHERE trans.EntityType = @EntityType

	UNION ALL

	SELECT docre.DocAId, a.CustomerId, a.CustNo, a.AttDate 
	FROM @tmp_eform_folderids a 
	INNER JOIN AFW_DocRelation docre 
		ON a.ElfFormFldrId = docre.AttachId AND docre.AttachType = @Const_LTBL_EFLDR

	UNION ALL

	SELECT docre.DocAId, a.CustomerId, a.CustNo, a.AttDate 
	FROM AFW_DocRelation docre 
	INNER JOIN @tmp_eformids a 
		ON a.ElfFormId = docre.AttachId AND docre.AttachType = @Const_LTBL_EFORM

	UNION ALL

	SELECT docre.DocAId, a.CustomerId, a.CustNo, efdetail.EnteredDate 
	FROM @tmp_eformids a 
	INNER JOIN AFW_ELFFormDetail efdetail 
		ON efdetail.ElfFormId = a.ElfFormId 
	INNER JOIN AFW_DocRelation docre 
		ON efdetail.ElfFormDtlId = docre.AttachId AND docre.AttachType = @Const_LTBL_EFRMDTL


DROP TABLE IF EXISTS ##TempAttachIds

CREATE TABLE ##TempAttachIds (
    DocAId UNIQUEIDENTIFIER, 
    CustomerId UNIQUEIDENTIFIER, 
    CustNo INT, 
    AttDate DATETIME
);

INSERT INTO ##TempAttachIds
SELECT t1.* 
FROM @DocA t1 
INNER JOIN AFW_DocAttachment t2 ON t1.DocAId = t2.DocAId 
WHERE t2.DocType NOT IN (12, 13) AND t2.Status <> 'D'

DROP TABLE IF EXISTS ##TempAttachPath;
CREATE TABLE ##TempAttachPath (
    CustNo INT, 
    AttachPath VARCHAR(MAX), 
    AttDate DATETIME, 
    Descrptn VARCHAR(MAX), 
    Comment VARCHAR(255)
)


INSERT INTO ##TempAttachPath (CustNo, AttachPath, AttDate, Descrptn, Comment)
SELECT tIds.CustNo, CONCAT(@AttachmentFolderPath, '\', edoc.FilePath), tIds.AttDate, '', 
       dbo.CheckFileExists(CONCAT(@AttachmentFolderPath, '\', edoc.FilePath)) 
FROM ##TempAttachIds tIds 
INNER JOIN Extr_Documents edoc ON tIds.DocAId = edoc.DocAId



--Insert data into EpicEasyBusinessOutput Table by Joining Business CSV File & ApplicantAttachment Table
IF EXISTS(SELECT 1 FROM sys.Objects WHERE  Object_id = OBJECT_ID(N'dbo.AMS360BusinessOutput') AND Type = N'U')
BEGIN
   DROP TABLE [A2022480D1].[DBO].[AMS360BusinessOutput]
END

SELECT TRY_CAST(A1.[Prior Account ID] AS INT) AS [Prior Account ID], A1.[Epic Lookup Code],'Cust' AS [Account Type], '' AS [Epic Policy ID],'' AS [Epic Policy Number],'' AS [Epic Policy Effective Date],'' AS [Epic Policy Expiration Date],'' AS [Epic Line ID],'' AS [Epic Line Type],'' AS [Epic Activity ID],'' AS [Epic Activity Code],'' AS [Activity Entered Date],'' AS [Activity Associated To],B1.AttachPath AS [File Name On Disk],'Account' AS [Attach To],'' AS [File Description], B1.Comment AS [Comments],FORMAT(B1.AttDate, 'd', 'en-US') AS [Received],'Public' AS [Security],0 AS [Client Accessible],'' AS [Client Accessible Expiration],'' AS [Folder],'' AS [Sub-Folder 1],'' AS [Sub-Folder 2],'' AS [Sub-Folder 3],'' AS [Sub-Folder 4],'' AS [Sub-Folder 5],'' AS [Exception Reason],'' AS [Success/Failure] into [A2022480D1].[DBO].[AMS360BusinessOutput]
FROM ##TempBusinessInput A1 INNER JOIN ##TempAttachPath B1
ON TRY_CAST(A1.[Prior Account ID] AS INT) = B1.CustNo



DECLARE @RowCount INT, @ChunkSize INT, @Offset INT, @FileIndex INT
DECLARE @FileName VARCHAR(500), @bcpCommand NVARCHAR(500)

SET @ChunkSize = 50000
SET @Offset = 0
SET @FileIndex = 1

-- Get total count of records
SELECT @RowCount = COUNT(*) FROM [A2022480D1].[DBO].[AMS360BusinessOutput]

WHILE @Offset < @RowCount
BEGIN
    
    SET @FileName = @AMS360OutPutFolderPath + '\BusinessOutput_' + CAST(@FileIndex AS VARCHAR) + '.csv'

	SET @bcpCommand = 'bcp "SELECT * FROM [A2022480D1].[DBO].[AMS360BusinessOutput] ORDER BY [Prior Account ID] OFFSET ' + CAST(@Offset AS VARCHAR) + ' ROWS FETCH NEXT ' + CAST(@ChunkSize AS VARCHAR) + ' ROWS ONLY" queryout "' + @FileName + '" -c -t"," -T -S LEIGH-CLOUDPC'
	print @bcpCommand
    -- Execute BCP command
    EXEC xp_cmdshell @bcpCommand

    -- Move to the next chunk
    SET @Offset = @Offset + @ChunkSize
    SET @FileIndex = @FileIndex + 1
END


--Insert data into EpicEasyIndividualOutput Table by Joining Individual CSV File & ApplicantAttachment Table
IF EXISTS(SELECT 1 FROM sys.Objects WHERE  Object_id = OBJECT_ID(N'dbo.AMS360IndividualOutput') AND Type = N'U')
BEGIN
   DROP TABLE [A2022480D1].[DBO].[AMS360IndividualOutput]
END

SELECT TRY_CAST(A1.[Prior Account ID] AS INT) AS [Prior Account ID], A1.[Epic Lookup Code],'Cust' AS [Account Type], '' AS [Epic Policy ID],'' AS [Epic Policy Number],'' AS [Epic Policy Effective Date],'' AS [Epic Policy Expiration Date],'' AS [Epic Line ID],'' AS [Epic Line Type],'' AS [Epic Activity ID],'' AS [Epic Activity Code],'' AS [Activity Entered Date],'' AS [Activity Associated To],B1.AttachPath AS [File Name On Disk],'Account' AS [Attach To],'' AS [File Description], B1.Comment AS [Comments],FORMAT(B1.AttDate, 'd', 'en-US') AS [Received],'Public' AS [Security],0 AS [Client Accessible],'' AS [Client Accessible Expiration],'' AS [Folder],'' AS [Sub-Folder 1],'' AS [Sub-Folder 2],'' AS [Sub-Folder 3],'' AS [Sub-Folder 4],'' AS [Sub-Folder 5],'' AS [Exception Reason],'' AS [Success/Failure] into [A2022480D1].[DBO].[AMS360IndividualOutput]
FROM ##TempIndividualInput A1 INNER JOIN ##TempAttachPath B1
ON TRY_CAST(A1.[Prior Account ID] AS INT)  = B1.CustNo


--Code to Generate IndividualOutput.csv 
SET @ChunkSize = 50000
SET @Offset = 0
SET @FileIndex = 1

-- Get total count of records
SELECT @RowCount = COUNT(*) FROM [A2022480D1].[DBO].[AMS360IndividualOutput]

WHILE @Offset < @RowCount
	BEGIN
    
		SET @FileName = @AMS360OutPutFolderPath + '\IndividualOutput_' + CAST(@FileIndex AS VARCHAR) + '.csv'

		SET @bcpCommand = 'bcp "SELECT * FROM [A2022480D1].[DBO].[AMS360IndividualOutput] ORDER BY [Prior Account ID] OFFSET ' + CAST(@Offset AS VARCHAR) + ' ROWS FETCH NEXT ' + CAST(@ChunkSize AS VARCHAR) + ' ROWS ONLY" queryout "' + @FileName + '" -c -t"," -T -S LEIGH-CLOUDPC'


		-- Execute BCP command
		EXEC xp_cmdshell @bcpCommand

		-- Move to the next chunk
		SET @Offset = @Offset + @ChunkSize
		SET @FileIndex = @FileIndex + 1
	END
END
END
GO