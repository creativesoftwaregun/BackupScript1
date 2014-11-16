SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
-- =======================================================
-- Name:			usp_emis_report_PerfRpt_ExecSmry_GetPerf
-- Description:		Retrieve performance data for Executive Summary - Performance Report
-- Author:			JL
-- Create date:		14 Jan 2013
-- History:		
--					1. Created
-- =======================================================
CREATE PROCEDURE [dbo].[usp_emis_report_PerfRpt_ExecSmry_GetPerf] 
	@ReportDate		DATETIME,	 -- the first day of the month, e.g. 2008-01-01 00:00:00 refers to Jan 2008
	@PortfolioName	VARCHAR(255) -- may be either 'Global' or 'Asia'
AS	
BEGIN
/*********************************************	
-- For Testing
DECLARE @ReportDate		DATETIME,	 -- the first day of the month, e.g. 2008-01-01 00:00:00 refers to Jan 2008
	@PortfolioName	VARCHAR(255) -- may be either 'Global' or 'Asia'

SET @ReportDate = '30 Nov 2012'
SET @PortfolioName = 'Asia'
**********************************************/
	SET NOCOUNT ON
	
	DECLARE
		@CYStart			DATETIME,
		@FYStart			DATETIME,
		@ReportMonth		DATETIME,
		@ReportMonthEnd		DATETIME
	
	SELECT
		@ReportMonth = dbo.fn_GetMonthStartDate(@ReportDate),
		@ReportMonthEnd = DATEADD(ss, -1, DATEADD(mm, 1, @ReportMonth)),
		@CYStart = dbo.fn_GetCYStartDate(@ReportMonth),
		@FYStart = dbo.fn_GetFYStartDate(@ReportMonth)
	
	DECLARE
		@PortfCodeID		INT,
		@LiborID		INT
	
	-- =======================================================
	-- get portfolio code id
	-- =======================================================
	SET @PortfCodeID = dbo.fn_encode_code_name_to_code_id(@PortfolioName, 'DIVISION') 
	
	
	-- =======================================================
	-- get benchmark id of 'LIBOR'
	-- =======================================================
	SET	@LiborID = 1
	
	-- =======================================================
	-- result table
	-- =======================================================
	DECLARE @toDatePerf AS TABLE
	(
		[NAME]			VARCHAR(50),
		PORTFOLIO		DECIMAL(10,4), -- decimal value not percentage
		BENCHMARK		DECIMAL(10,4), -- decimal value not percentage
		VALUE_ADDED		DECIMAL(10,4)  -- decimal value not percentage
	)

    DECLARE @PerfSmry AS TABLE
    (
        PERF_NAME VARCHAR(255),
        PERF_CYTD DECIMAL(22, 16),
        PERF_FYTD DECIMAL(22, 16),
        PERF_INCP DECIMAL(22, 16),
        GAIN_PERIOD INT,
        GAIN_FACTOR DECIMAL(22, 16),
        ANNUALISED_RETURN DECIMAL(22, 16)
    )
    
    INSERT INTO @PerfSmry
	EXEC dbo.usp_emis_report_PerfRpt_GetChainlinkTotalSmry @PortfolioName, @ReportMonthEnd


	-- test
	return

	DECLARE
		@PortfFYTD DECIMAL(22, 16),
        @PortfCYTD DECIMAL(22, 16),
        @PortfSinceInc DECIMAL(22, 16),
		@BmFYTD DECIMAL(22, 16),
        @BmCYTD DECIMAL(22, 16),
        @BmSinceInc DECIMAL(22, 16)
        
        
    SELECT
		@PortfFYTD = PERF_FYTD,
		@PortfCYTD = PERF_CYTD,
		@PortfSinceInc = ANNUALISED_RETURN
	FROM
		@PerfSmry
	WHERE
		PERF_NAME = @PortfolioName
	
	SELECT
		@BmFYTD = PERF_FYTD,
		@BmCYTD = PERF_CYTD,
		@BmSinceInc = ANNUALISED_RETURN
	FROM
		@PerfSmry
	WHERE
		PERF_NAME = 'Index'
     
    -- =======================================================    
	-- 1. calculate month-to-date portfolio perfomance
	-- =======================================================
	INSERT @toDatePerf
	SELECT
		'Month To Date',
		dbo.fn_CalPortfPerfWgtPrdtSum(@PortfolioName, @ReportMonth, @ReportMonthEnd, 3),
		dbo.fn_GetBmPerfPrdtReturns(@LiborID, @ReportMonth, @ReportMonthEnd),
		NULL
	
	-- =======================================================
	-- 2. calculate fiscal-year-to-date portfolio perfomance
	-- =======================================================
	INSERT @toDatePerf
	SELECT 
		'Calendar Year To Date',
		@PortfCYTD,
		@BmCYTD,
		NULL
	
	-- =======================================================
	-- 3. calculate since-inception portfolio perfomance
	-- =======================================================
	INSERT @toDatePerf
	SELECT 
		'Fiscal Year To Date',
		@PortfFYTD,
		@BmFYTD,
		NULL
	
	-- =======================================================	
	-- 4. calculate since-inception portfolio perfomance
	-- =======================================================
	INSERT @toDatePerf
	SELECT 
		'Since Inception (annualised)',
		@PortfSinceInc,
		@BmSinceInc,
		NULL
		
	-- =======================================================
	-- 5. update value-added
	-- =======================================================
	UPDATE @toDatePerf
	SET
		VALUE_ADDED = PORTFOLIO - BENCHMARK

	SELECT 
		[NAME],
		PORTFOLIO * 100 AS PORTFOLIO, 
		BENCHMARK * 100 AS BENCHMARK, 
		VALUE_ADDED * 100 AS VALUE_ADDED
	FROM @toDatePerf

END


