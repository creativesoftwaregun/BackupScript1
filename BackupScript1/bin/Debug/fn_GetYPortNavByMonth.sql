SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
-- ==============================================================================================================
-- Name:			fn_GetYPortNavByMonth
-- Description:		Get YPort's NAV for a month and year
-- Author:			JL
-- Create date:		14 Jan 2013
-- History:		
--					1. Created
--					2. 20130424 - AS - Get txn data from VW_EMIS_TXN
--					3. 20130424 - AS - Data should be further filtered by: Asset Class = MA; Fund Type = Non-Admin
--					4. 20130715 - AS/JL - Change Logic to get the SumRedemption 
--										a. Get “RP” (Redemption Proceed) txn NOT “R” (Redemption Request) txn
--										b. Retrieve based on NAV_Date + 1 NOT NAV_Date
--					5. 20130923 - JL - log #336451 Performance Report to include CA tickets
--					6. 20131018 - JL - log #336451 Performance Report to include T tickets
--					7. 20131029 - AS - log #336451 For RP Ticket, get TXN_AMT_LCL if TXN_AMT_USD is NULL
--					8. 20131030 - JL - log #336451 Performance Report to include DD, RC, RN, DI, DN tickets
-- ==============================================================================================================
CREATE FUNCTION [dbo].[fn_GetYPortNavByMonth]
(
    @YPort VARCHAR(20),
    @Month INT,
    @Year INT,
    @Type INT, -- 1 = Estimate only, 2 = Actual only, 3 = Actual if available otherwise estimate
    @RolloverNav BIT, -- 0 = Normal, 1 = Quarterly Nav will be roll over monthly
    @TBL_EMIS_YPORT_MONTHLY_PERF dbo.TBL_EMIS_YPORT_MONTHLY_PERF READONLY,
    @SubscriptionTable  dbo.SubscriptionTableType READONLY
)
RETURNS DECIMAL(38, 10)
AS
BEGIN

/*********************************************	
-- For Testing
DECLARE @YPort VARCHAR(20),
		@Month INT,
		@Year INT,
		@Type INT, -- 1 = Estimate only, 2 = Actual only, 3 = Actual if available otherwise estimate
		@RolloverNav BIT -- 0 = Normal, 1 = Quarterly Nav will be roll over monthly

SET @YPort = 'YETONAIU'
SET @Month = 9
SET @Year = 2013
SET @Type = 1
SET @RolloverNav = 1
**********************************************/


    DECLARE @Nav DECIMAL(38, 10)
    DECLARE @RptFreq VARCHAR(255)
    
    SET @RptFreq = dbo.fn_GetReportingFreq(@YPort)

    -- ===================================================================
    -- CONDITION 1: If it is monthly, get the nav from TBL_EMIS_YPORT_MONTHLY_PERF
    -- ===================================================================
    IF (@RptFreq = 'MONTHLY')
    BEGIN
		
        SELECT -- MONTHLY
            @Nav = CASE 
                       WHEN @Type = 1 THEN A.NAV_ESTIMATE_USD 
                       WHEN @Type = 2 THEN A.NAV_ACTUAL_USD 
                       WHEN @Type = 3 THEN ISNULL(ISNULL(A.NAV_ACTUAL_USD, A.NAV_ESTIMATE_USD),
							(SELECT TOP 1 B.NAV_ACTUAL_USD
							FROM @TBL_EMIS_YPORT_MONTHLY_PERF B
							WHERE B.YPORT = A.YPORT
							AND B.PERF_REPORTING_DATE <= A.PERF_REPORTING_DATE
							AND B.NAV_ACTUAL_USD IS NOT NULL 
							AND B.DELETE_FLAG = 0
							ORDER BY B.PERF_REPORTING_DATE  DESC)
						)
                   END
        FROM
            @TBL_EMIS_YPORT_MONTHLY_PERF A
        WHERE
            A.YPORT = @YPort
            AND
            MONTH(A.PERF_REPORTING_DATE) = @Month
            AND
            YEAR(A.PERF_REPORTING_DATE) = @Year
            
		            
    END    
    -- =======================================================================
    -- CONDITION 2: If it is not monthly, 
    -- get the nav from TBL_EMIS_YPORT_MONTHLY_PERF +
    -- subscription amount (not fully redeemed) -
    -- redemption amount (not fully redeemed)
    -- =======================================================================
    ELSE
    BEGIN
		
    
        --DECLARE @FreqPeriod INT
        DECLARE @ReportDate DATETIME
        DECLARE @QuarterDate DATETIME    
        DECLARE @FirstSubscriptionDate DATETIME
        DECLARE @FirstSubscriptionVDate DATETIME
        DECLARE @FullyRedeemedDate DATETIME
        
        SET @ReportDate = CONVERT(DATETIME, CAST(@Year AS VARCHAR(4)) + '-' + CAST(@Month AS VARCHAR(2)) + '-1')
        SET @ReportDate = dbo.fn_GetMonthEndDate(@ReportDate)     
               
        --SELECT
        --    @FreqPeriod = CASE @RptFreq
        --                      WHEN 'Quarterly' THEN 3
        --                      WHEN 'Semi-Annual' THEN 6
        --                      WHEN 'Annual' THEN 12
        --                  END
        
        SELECT -- NOT MONTHLY
			@FirstSubscriptionDate = MIN(DATEADD(day, 1, ET.NAV_DATE)) 
		FROM 
			@SubscriptionTable ET
		WHERE 
			--MT.STATUS NOT IN (12,18,19) -- cancelled, draft, reversal cancellation
			--AND 
			-- Modified on 20130923 - JL - log #336451 Performance Report to include CA tickets			
			ET.TXN_TYPE IN ('S','CA','T')
			AND
			ET.YPORT = @YPort
			AND
			ET.ASSET_CLASS = dbo.fn_encode_code_name_to_code_id ('MA', 'ASSET_CLASS') -- asset class = MA        
        
        -- Modified on 20131030 to include DD tickets
        -- Start
        SELECT 
			@FirstSubscriptionVDate = MIN(DATEADD(day, 1, ET.VALUE_DATE)) 
		FROM 
			@SubscriptionTable ET
		WHERE 			
			ET.TXN_TYPE = 'DD'
			AND
			ET.YPORT = @YPort
			AND
			ET.ASSET_CLASS = dbo.fn_encode_code_name_to_code_id ('MA', 'ASSET_CLASS')
		
		IF (@FirstSubscriptionVDate < @FirstSubscriptionDate)
		BEGIN
			SET @FirstSubscriptionDate = @FirstSubscriptionVDate
		END
		-- End
		
        -- ===================================================================================================================    
        -- Get YPort's fully redeemed date so that no NAV is returned if the report date is greater than its redeemed date.
        -- ===================================================================================================================
        SELECT
            @FullyRedeemedDate = dbo.fn_GetMonthEndDate(FULLY_REDEEMED)
        FROM
            VW_EMIS_YPORT
        WHERE
            YPORT = @YPort
            
            
        SELECT TOP 1
            @Nav = CASE 
                       WHEN @Type = 1 THEN NAV_ESTIMATE_USD 
                       WHEN @Type = 2 THEN NAV_ACTUAL_USD 
                       WHEN @Type = 3 THEN ISNULL(NAV_ACTUAL_USD, NAV_ESTIMATE_USD) 
                   END,
            @QuarterDate = PERF_REPORTING_DATE
        FROM
            @TBL_EMIS_YPORT_MONTHLY_PERF Perf
        INNER JOIN
            VW_EMIS_YPORT YPort
        ON
            YPort.YPORT = Perf.YPORT
        WHERE
            Perf.YPORT = @YPort
            AND
            (FULLY_REDEEMED >= @ReportDate OR FULLY_REDEEMED IS NULL)
            AND
            PERF_REPORTING_DATE <= @ReportDate
            AND
            (NAV_ESTIMATE_USD IS NOT NULL OR NAV_ACTUAL_USD IS NOT NULL)
        ORDER BY
            PERF_REPORTING_DATE DESC   
            
        
        DECLARE @SumSubscription DECIMAL(38, 10)
        DECLARE @SumRedemption DECIMAL(38, 10)
               
        SET @QuarterDate = ISNULL(@QuarterDate, @FirstSubscriptionDate)
       
       -- =======================================================================================================================
       --If the reportdate doesn't falls on quarter end get subscription and redemption sum from last nav date to report date    
       -- =======================================================================================================================                           
       IF( (@QuarterDate <> @ReportDate) OR (@FirstSubscriptionDate <= @ReportDate) ) and (@ReportDate <ISNULL(@FullyRedeemedDate,'31-DEC-9999'))
       BEGIN 
            IF( @RolloverNav = 1 ) 
            BEGIN
                SET @QuarterDate = dbo.fn_GetMonthStartDate(@QuarterDate)

				-- =========================================
				-- 1. Retrieve the subscription amount
				-- =========================================
                SELECT -- Retrieve the subscription amount
					@SumSubscription = ISNULL(SUM(ET.TXN_AMT_USD), 0)
				FROM 
					@SubscriptionTable ET
				WHERE 
					--MT.STATUS NOT IN (12,18,19) -- cancelled, draft, reversal cancellation
					--AND 
					-- Modified on 20130923 - JL - log #336451 Performance Report to include CA tickets
					(
						(ET.TXN_TYPE IN ('S','CA','T') AND DATEADD(day, 1, ET.NAV_DATE) BETWEEN @QuarterDate AND @ReportDate)
						OR
						(ET.TXN_TYPE = 'DD' AND DATEADD(day, 1, ET.VALUE_DATE) BETWEEN @QuarterDate AND @ReportDate)
					) AND
					ET.YPORT = @YPort
					AND
					ET.ASSET_CLASS = dbo.fn_encode_code_name_to_code_id ('MA', 'ASSET_CLASS') -- asset class = MA        
					
				-- =========================================
				-- 2. Retrieve the redemption amount
				-- =========================================						    
                SELECT 
					@SumRedemption = ISNULL(SUM(ISNULL(ET.TXN_AMT_USD,ET.TXN_AMT_LCL)), 0)
				FROM 
					@SubscriptionTable ET
				WHERE 
					--MT.STATUS NOT IN (12,18,19) -- cancelled, draft, reversal cancellation
					--AND 
					-- Modified on 20130923 - JL - log #336451 Performance Report to include CA tickets.
					-- modified on 15 Jul 2013 from 'R' to 'RP'
					-- modified on 15 Jul 2013 from NAV Date to NAV Date + 1
					-- Modified on 20131030 to include RC, RN, DI, DN tickets
					(
						(ET.TXN_TYPE IN ('RP','CA','T') AND DATEADD(day, 1, ET.NAV_DATE) BETWEEN @QuarterDate AND @ReportDate)
						OR
						(ET.TXN_TYPE IN ('RC','RN','DI','DN') AND DATEADD(day, 1, ET.VALUE_DATE) BETWEEN @QuarterDate AND @ReportDate)
					) AND
					ET.YPORT = @YPort
					AND
					ET.ASSET_CLASS = dbo.fn_encode_code_name_to_code_id ('MA', 'ASSET_CLASS') -- asset class = MA         
									    
                IF NOT ( (@SumSubscription - @SumRedemption = 0) AND @Nav IS NULL)
                BEGIN
                    SET @Nav = ISNULL(@Nav, 0) + @SumSubscription - @SumRedemption
                END
            END
            ELSE
            BEGIN
                SET @Nav = NULL
            END

        END
            
    END

    RETURN @Nav    
END


