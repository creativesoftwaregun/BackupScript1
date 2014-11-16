SET ANSI_NULLS ON
SET QUOTED_IDENTIFIER ON
-- =======================================================
-- Name:			fn_GetYPortSubscriptionByMonth
-- Description:		Get YPort's subscription sum by Subscription ticket (NAV DATE + 1) month and (NAV DATE + 1) year.
-- Author:			JL
-- Create date:		14 Jan 2013
-- History:		
--					1. Created
--					2. 20130424 - AS - Get txn data from VW_EMIS_TXN
--					3. 20130424 - AS - Data should be further filtered by: Asset Class = MA; Fund Type = Non-Admin
--					4. 20130923 - JL - log #336451 Performance Report to include CA tickets
--					5. 20131018 - JL - log #336451 Performance Report to include T tickets
--					9. 20131030 - JL - log #336451 Performance Report to include DD tickets
-- =======================================================
CREATE FUNCTION [dbo].[fn_GetYPortSubscriptionByMonth]
(
    @YPort VARCHAR(20),
    @Month INT,
    @Year INT,
	@SubscriptionTable dbo.SubscriptionTableType READONLY
)
RETURNS DECIMAL(38, 10)
AS
BEGIN
    
    DECLARE @SumSubscription DECIMAL(38, 10)
        
    SELECT 
		@SumSubscription = SUM(ET.TXN_AMT_USD) 
	FROM
		@SubscriptionTable ET
	WHERE 
		--MT.STATUS NOT IN (12,18,19) -- cancelled, draft, reversal cancellation
		--AND 
		-- Modified on 20130923 - JL - log #336451 Performance Report to include CA tickets
		-- Modified on 20131030 to include DD tickets
		(
			(ET.TXN_TYPE IN ('S','CA','T') AND MONTH(DATEADD(day, 1, ET.NAV_DATE)) = @Month AND YEAR(DATEADD(day, 1, ET.NAV_DATE)) = @Year)
			OR
			(ET.TXN_TYPE = 'DD' AND MONTH(DATEADD(day, 1, ET.VALUE_DATE)) = @Month AND YEAR(DATEADD(day, 1, ET.VALUE_DATE)) = @Year)
		) AND
		ET.YPORT = @YPort AND
		ET.ASSET_CLASS = dbo.fn_encode_code_name_to_code_id ('MA', 'ASSET_CLASS') -- asset class = MA

    RETURN ISNULL(@SumSubscription, 0)
 
END


