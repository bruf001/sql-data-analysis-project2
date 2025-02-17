

--PostgreSQL --

--PART 1--
--DATA CLEANING--
ALTER TABLE data_mart.weekly_sales
ADD COLUMN week_date_new DATE;

UPDATE data_mart.weekly_sales
SET week_date_new = TO_DATE(week_date,'DD/MM/YYYY')::DATE;

CREATE TEMP TABLE NEWTABLE AS

    SELECT 
        *,
        EXTRACT(DOW FROM week_date_new) AS DOW_NUM,
        EXTRACT(WEEK FROM week_date_new) AS WEEK_NUM,
        EXTRACT(MONTH FROM week_date_new) AS MONTH_NUM,
        EXTRACT(YEAR FROM week_date_new) AS TRANSACTION_YEAR
    FROM data_mart.weekly_sales;

CREATE TEMP TABLE NEWTABLE2 AS
SELECT 
		*,
        
        CASE 
        WHEN transaction_year= 20 THEN '2020'
        WHEN transaction_year= 19 THEN '2019'
        WHEN transaction_year= 18 THEN '2018'
        ELSE 'Unknown'
        END AS YEAR_OF_TRANSACTION,
        
        CASE
        WHEN segment LIKE '%1' THEN 'Young Adults'
        WHEN segment LIKE '%2' THEN 'Middle Aged'
        WHEN segment LIKE'%3' THEN 'Retirees'
        WHEN segment LIKE '%4' THEN 'Retirees'
        ELSE 'Unknown'
        END AS AGE_BAND,
        
        CASE
        WHEN segment LIKE 'C%' THEN 'Couples'
        WHEN segment LIKE 'F%' THEN 'Families'
        ELSE 'Unknown'
        END AS Demographic
FROM NEWTABLE;

--CREATED A TEMPORARY TABLE TO HOUSE MY CLEANED DATASET--
CREATE TEMP TABLE CLEAN_TABLE AS
SELECT 
	week_date_new,
    	DOW_NUM,
        week_num,
        month_num,
        year_of_transaction,
        region,
        platform,
        customer_type,
        transactions,
        sales,
        age_band,
        demographic,
        ROUND(sales/transactions, 2) AS AVERAGE_TRANSACTION
FROM NEWTABLE2;


--PART 2--
--BASIC DATA EXPLORATION--

--NUMBER OF TRANSACTIONS BY YEAR--
SELECT 
	year_of_transaction,
	SUM(transactions) AS ALL_TRANSACTIONS
    
FROM CLEAN_TABLE
GROUP BY year_of_transaction;

--SALES BY REGION--
SELECT 
	region,
	SUM(sales) AS SUM_OF_SALES
    
FROM CLEAN_TABLE
GROUP BY region
ORDER BY SUM_OF_SALES DESC;

--COUNT OF TRANSACTIONS BY PLATFORM--
SELECT 
	platform,
	SUM(transactions) AS transact_count  
    
FROM CLEAN_TABLE
GROUP BY platform
ORDER BY transact_count DESC;


--PERCENTAGE OF PLATFORM SALES FOR EACH MONTH--
WITH MONTHLYSALES AS (
    SELECT
        month_num,
  		
        SUM(sales) AS SUM_OF_SALES,
  		SUM(CASE WHEN platform='Retail' THEN sales ELSE 0 END) AS RETAIL_SALES,
  		SUM(CASE WHEN platform='Shopify' THEN sales ELSE 0 END) AS SHOPIFY_SALES

    FROM CLEAN_TABLE
    GROUP BY month_num
    ORDER BY month_num ASC
)
SELECT 
	*,
    
    ROUND((retail_sales::numeric/sum_of_sales)*100) AS RETAIL_PERCENT,
    ROUND((shopify_sales::numeric/sum_of_sales)*100) AS SHOPIFY_PERCENT
FROM MONTHLYSALES;


--PERCENTAGE OF DEMOGRAPHIC SALES BY YEAR--
WITH MONTHLYDEMOSALES AS (
    SELECT
        year_of_transaction,
  		
        SUM(sales) AS SUM_OF_SALES,
  		SUM(CASE WHEN demographic='Couples' THEN sales ELSE 0 END) AS Couple_SALES,
  		SUM(CASE WHEN demographic='Families' THEN sales ELSE 0 END) AS Family_SALES,
  SUM(CASE WHEN demographic='Unknown' THEN sales ELSE 0 END) AS unknown_SALES

    FROM CLEAN_TABLE
    GROUP BY year_of_transaction
    ORDER BY year_of_transaction ASC
)
SELECT 
	*,
    
    ROUND((Couple_SALES::numeric/sum_of_sales)*100) AS couplesales_PERCENT,
    ROUND((Family_SALES::numeric/sum_of_sales)*100) AS familysales_PERCENT,
    ROUND((unknown_SALES::numeric/sum_of_sales)*100) AS unknown_PERCENT
FROM MONTHLYDEMOSALES;

--Age band and Demographic RETAIL-sales contribution--
WITH AGEDEMOSALES AS (
    SELECT 
        age_band,
        demographic,
        SUM(sales) AS TOTAL_RETAIL_SALES
    FROM CLEAN_TABLE
    WHERE platform = 'Retail'
    GROUP BY age_band, demographic
)
SELECT 
	*,
    ROUND((TOTAL_RETAIL_SALES::numeric/SUM(TOTAL_RETAIL_SALES) OVER() )*100)  AS RETAIL_SALES_PERCENT
FROM AGEDEMOSALES
ORDER BY RETAIL_SALES_PERCENT DESC;


--PART 3--
--BEFORE/AFTER ANALYSIS--
--CREATING TWO TEMPORARY TABLES , BEFORE THE DATE OF CHANGE AND AFTER THE DATE OF CHANGE--
CREATE TEMP TABLE BEFORECHANGE AS
SELECT *
FROM CLEAN_TABLE
WHERE week_date_new < '0020-06-15';

CREATE TEMP TABLE AFTERCHANGE AS
SELECT *
FROM CLEAN_TABLE
WHERE week_date_new >= '0020-06-15';


--SALES DIFFERENCE BY REGION, 4 WEEKS BEFORE AND AFTER THE CHANGE OCCURED--
--4 WEEKS AFTER THE CHANGE, REGIONAL SALES INCREASED IN OCEANIA,ASIA,USA AND SOUTH AMERICA, BUT SALES REDUCED IN CANADA, EUROPE AND AFRICA--
--MEANWHILE, 12 WEEKS BEFORE AND AFTER THE CHANGE, ONLY EUROPE EXPERIENCED A DECREASE IN SALES--
--TO SEE 12 WEEKS CHANGE, JUST CHANGE THE week_num (13-24 AND 25-36)--
WITH FOUR_WEEKS_AFTER_CHANGE AS (
    SELECT *
    FROM BEFORECHANGE
    WHERE week_num BETWEEN 21 AND 24
    AND year_of_transaction = '2020'
),
FOUR_WEEKS_BEFORE_CHANGE AS (
    SELECT *
    FROM AFTERCHANGE
    WHERE week_num BETWEEN 25 AND 28
    AND year_of_transaction = '2020'
),
REGIONALSALES_BEFOREAFTER AS (
    SELECT 
        FWBC.region,
        SUM(FWBC.sales) AS SUM_OF_SALES_4WEEKS_BEFORE,
        SUM(FWAC.sales) AS SUM_OF_SALES_4WEEKS_AFTER

    FROM FOUR_WEEKS_BEFORE_CHANGE FWBC
    JOIN FOUR_WEEKS_AFTER_CHANGE FWAC
    ON FWBC.region = FWAC.region
    GROUP BY FWBC.region
)
SELECT 
	*,
    (SUM_OF_SALES_4WEEKS_AFTER -SUM_OF_SALES_4WEEKS_BEFORE) AS SALES_DIFF
FROM REGIONALSALES_BEFOREAFTER
ORDER BY SALES_DIFF DESC;



--4 WEEKS BEFORE AND AFTER CHANGE EFFECT ON AGEBAND AND DEMOGRAPHY--
--RESULT: 4 WEEKS AFTER CHANGE SALES INCREASED SIGNIFICANTLY AMONGST RETIREES COUPLES, INCREASED SLIGHTLY AMONGST MIDDLE AGED COUPLES,MIDDLE AGED FAMILIES AND YOUNG ADULT FAMILIES--
--BUT RETAIL SALES REDUCED AMONGST RETIREES FAMILIES--

WITH FOUR_WEEKS_BEFORE_CHANGE AS (
    SELECT *
    FROM BEFORECHANGE
    WHERE week_num BETWEEN 21 AND 24
    AND year_of_transaction = '2020'
),
FOUR_WEEKS_AFTER_CHANGE AS (
    SELECT *
    FROM AFTERCHANGE
    WHERE week_num BETWEEN 25 AND 28
    AND year_of_transaction = '2020'
),
AGE_DEMO_SALES AS (
    SELECT 
        FWBC.age_band,
        FWBC.demographic,
        SUM(FWBC.sales) AS TOTAL_RETAIL_SALES_FWBC,
  		SUM(FWAC.sales) AS TOTAL_RETAIL_SALES_FWAC
    FROM FOUR_WEEKS_BEFORE_CHANGE FWBC
  	JOIN FOUR_WEEKS_AFTER_CHANGE FWAC
  	ON FWBC.age_band = FWAC.age_band
    WHERE FWBC.platform = 'Retail' AND FWAC.platform = 'Retail'
    GROUP BY FWBC.age_band, FWBC.demographic
)


SELECT 
	*,
    ROUND((TOTAL_RETAIL_SALES_FWBC::numeric/SUM(TOTAL_RETAIL_SALES_FWBC) OVER() )*100)  AS RETAIL_SALES_FWBC_PERCENT,
    ROUND((TOTAL_RETAIL_SALES_FWAC::numeric/SUM(TOTAL_RETAIL_SALES_FWAC) OVER() )*100)  AS RETAIL_SALES_FWAC_PERCENT
FROM AGE_DEMO_SALES
ORDER BY RETAIL_SALES_FWAC_PERCENT DESC;




--CUSTOMER-TYPE SALE--
--WE SEE AN INCREASE IN NEW,EXISTING AND GUEST CUSTOMERS RETAIL SALES AND A DECREASE IN SHOPIFY OVER 4 WEEKS--
-- SIMILAR PATTERN IS OBSERVED OVER 12 WEEKS BEFORE AND AFTER--

WITH FOUR_WEEKS_BEFORE_CHANGE AS (
    SELECT *
    FROM BEFORECHANGE
    WHERE week_num BETWEEN 13 AND 24
    AND year_of_transaction = '2020'
),
FOUR_WEEKS_AFTER_CHANGE AS (
    SELECT *
    FROM AFTERCHANGE
    WHERE week_num BETWEEN 25 AND 36
    AND year_of_transaction = '2020'
),
BEFOREANDAFTER AS (
    SELECT 
        AFC.customer_type,
        AFC.platform,
        SUM(BFC.sales) AS SALES_4WEEKS_BEFORE,
        SUM(AFC.sales) AS SALES_4WEEKS_AFTER
  		


    FROM FOUR_WEEKS_BEFORE_CHANGE BFC
    JOIN FOUR_WEEKS_AFTER_CHANGE AFC
    ON BFC.customer_type = AFC.customer_type
  	
    GROUP BY AFC.customer_type, AFC.platform
    --ORDER BY TOTAL_SUM_4WEEKS_BEFORE DESC;
)
SELECT
	*,
    (SALES_4WEEKS_AFTER - SALES_4WEEKS_BEFORE) AS SALESDIFFERENCE
FROM BEFOREANDAFTER;




