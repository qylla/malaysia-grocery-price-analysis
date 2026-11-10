-- =====================================================================
-- PriceCatcher grocery price analysis (Jul 2025 - Jun 2026)
--
-- Items analysed:
--   1    = AYAM BERSIH - STANDARD (1kg)
--   1109 = TELUR AYAM GRED A (30 biji)
--   267  = MINYAK MASAK TULEN CAP VESAWIT (1kg)
--
-- Base tables (item, premise, prices) are created and loaded by
-- scripts/load_mysql.py. Run the sections below in order.
--
-- Note: the local XAMPP MySQL version does not support WITH / LAG(),
-- so month-over-month changes use self-joins instead of window functions.
-- East Malaysia = Sabah, Sarawak, W.P. Labuan.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. First look: average, min and max price by state (raw data)
-- ---------------------------------------------------------------------
SELECT i.item, p.state,
       COUNT(*)               AS n_records,
       ROUND(AVG(f.price), 2) AS avg_price,
       MIN(f.price)           AS min_price,
       MAX(f.price)           AS max_price
FROM prices f
JOIN premise p ON f.premise_code = p.premise_code
JOIN item i    ON f.item_code    = i.item_code
GROUP BY i.item, p.state
ORDER BY i.item, avg_price DESC;


-- ---------------------------------------------------------------------
-- 2. Price distribution per item (used to choose cleaning thresholds)
-- ---------------------------------------------------------------------
SELECT i.item,
       FLOOR(f.price) AS price_band_rm,
       COUNT(*)       AS n_records
FROM prices f
JOIN item i ON f.item_code = i.item_code
GROUP BY i.item, FLOOR(f.price)
ORDER BY i.item, price_band_rm;


-- ---------------------------------------------------------------------
-- 3. Are high egg prices errors or real? Check where they occur
-- ---------------------------------------------------------------------
-- 3a. Share of egg records priced at RM17+ by state
SELECT p.state,
       SUM(f.price >= 17)                            AS n_high,
       COUNT(*)                                      AS n_all,
       ROUND(100 * SUM(f.price >= 17) / COUNT(*), 1) AS pct_high,
       MAX(f.price)                                  AS max_price
FROM prices f
JOIN premise p ON f.premise_code = p.premise_code
WHERE f.item_code = 1109
GROUP BY p.state
ORDER BY pct_high DESC;

-- 3b. Upper tail of egg prices (RM22+)
SELECT FLOOR(price) AS price_band_rm,
       COUNT(*)     AS n_records
FROM prices
WHERE item_code = 1109 AND price >= 22
GROUP BY FLOOR(price)
ORDER BY price_band_rm;


-- ---------------------------------------------------------------------
-- 4. Cleaned table (raw table `prices` stays untouched)
--    Chicken RM5-15, eggs RM9-25, cooking oil RM5-9
-- ---------------------------------------------------------------------
CREATE TABLE prices_clean LIKE prices;

INSERT INTO prices_clean
SELECT * FROM prices
WHERE (item_code = 1    AND price BETWEEN 5 AND 15)
   OR (item_code = 1109 AND price BETWEEN 9 AND 25)
   OR (item_code = 267  AND price BETWEEN 5 AND 9);

-- Rows before vs after cleaning
SELECT i.item,
       (SELECT COUNT(*) FROM prices x       WHERE x.item_code = i.item_code) AS before_clean,
       (SELECT COUNT(*) FROM prices_clean y WHERE y.item_code = i.item_code) AS after_clean
FROM item i;


-- ---------------------------------------------------------------------
-- 5. Monthly summary by item and zone
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS monthly_prices;

CREATE TABLE monthly_prices AS
SELECT i.item,
       CASE WHEN p.state IN ('Sabah','Sarawak','W.P. Labuan')
            THEN 'East' ELSE 'Peninsular' END AS zone,
       CAST(DATE_FORMAT(f.`date`, '%Y-%m-01') AS DATE) AS month,
       ROUND(AVG(f.price), 2) AS avg_price,
       COUNT(*)               AS n_records
FROM prices_clean f
JOIN premise p ON f.premise_code = p.premise_code
JOIN item i    ON f.item_code    = i.item_code
GROUP BY i.item, zone, month;

-- 5a. Month-over-month change of the all-store average
SELECT a.item, a.zone,
       DATE_FORMAT(a.month, '%Y-%m') AS month,
       a.avg_price, a.n_records,
       ROUND(100 * (a.avg_price - b.avg_price) / b.avg_price, 2) AS pct_change
FROM monthly_prices a
LEFT JOIN monthly_prices b
       ON b.item  = a.item
      AND b.zone  = a.zone
      AND b.month = DATE_SUB(a.month, INTERVAL 1 MONTH)
ORDER BY a.item, a.zone, a.month;

-- 5b. Largest all-store monthly changes (months with 300+ records)
SELECT a.item, a.zone,
       DATE_FORMAT(a.month, '%Y-%m') AS month,
       b.avg_price AS avg_before,
       a.avg_price AS avg_this_month,
       a.n_records,
       ROUND(100 * (a.avg_price - b.avg_price) / b.avg_price, 2) AS pct_change
FROM monthly_prices a
JOIN monthly_prices b
  ON b.item  = a.item
 AND b.zone  = a.zone
 AND b.month = DATE_SUB(a.month, INTERVAL 1 MONTH)
WHERE a.n_records >= 300 AND b.n_records >= 300
ORDER BY ABS(a.avg_price - b.avg_price) / b.avg_price DESC
LIMIT 15;


-- ---------------------------------------------------------------------
-- 6. Same-store test: do jumps come from real price moves or from a
--    changing mix of reporting stores? Compare only stores that reported
--    in both months.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS premise_monthly;

CREATE TABLE premise_monthly AS
SELECT item_code, premise_code,
       CAST(DATE_FORMAT(`date`, '%Y-%m-01') AS DATE) AS month,
       AVG(price) AS avg_price,
       COUNT(*)   AS n
FROM prices_clean
GROUP BY item_code, premise_code, month;

CREATE INDEX idx_pm ON premise_monthly (item_code, month, premise_code);

-- 6a. Largest same-store monthly changes (at least 30 matched stores)
SELECT i.item,
       CASE WHEN p.state IN ('Sabah','Sarawak','W.P. Labuan')
            THEN 'East' ELSE 'Peninsular' END AS zone,
       DATE_FORMAT(a.month, '%Y-%m')   AS month,
       COUNT(*)                        AS n_matched_stores,
       ROUND(AVG(b.avg_price), 2)      AS avg_before,
       ROUND(AVG(a.avg_price), 2)      AS avg_this_month,
       ROUND(100 * (AVG(a.avg_price) - AVG(b.avg_price)) / AVG(b.avg_price), 2) AS same_store_pct
FROM premise_monthly a
JOIN premise_monthly b
  ON b.item_code    = a.item_code
 AND b.premise_code = a.premise_code
 AND b.month        = DATE_SUB(a.month, INTERVAL 1 MONTH)
JOIN premise p ON p.premise_code = a.premise_code
JOIN item i    ON i.item_code    = a.item_code
GROUP BY i.item, zone, a.month
HAVING COUNT(*) >= 30
ORDER BY ABS(AVG(a.avg_price) - AVG(b.avg_price)) / AVG(b.avg_price) DESC
LIMIT 12;

-- 6b. Stability check for East Malaysia and cooking oil (10+ matched stores)
SELECT i.item,
       CASE WHEN p.state IN ('Sabah','Sarawak','W.P. Labuan')
            THEN 'East' ELSE 'Peninsular' END AS zone,
       DATE_FORMAT(a.month, '%Y-%m')   AS month,
       COUNT(*)                        AS n_matched_stores,
       ROUND(AVG(b.avg_price), 2)      AS avg_before,
       ROUND(AVG(a.avg_price), 2)      AS avg_this_month,
       ROUND(100 * (AVG(a.avg_price) - AVG(b.avg_price)) / AVG(b.avg_price), 2) AS same_store_pct
FROM premise_monthly a
JOIN premise_monthly b
  ON b.item_code    = a.item_code
 AND b.premise_code = a.premise_code
 AND b.month        = DATE_SUB(a.month, INTERVAL 1 MONTH)
JOIN premise p ON p.premise_code = a.premise_code
JOIN item i    ON i.item_code    = a.item_code
GROUP BY i.item, zone, a.month
HAVING COUNT(*) >= 10 AND (zone = 'East' OR i.item LIKE 'MINYAK%')
ORDER BY ABS(AVG(a.avg_price) - AVG(b.avg_price)) / AVG(b.avg_price) DESC
LIMIT 8;


-- ---------------------------------------------------------------------
-- 7. Is the East-West gap just a store-type effect?
--    Compare zones within the same premise type (chicken and eggs).
-- ---------------------------------------------------------------------
SELECT i.item,
       p.premise_type,
       CASE WHEN p.state IN ('Sabah','Sarawak','W.P. Labuan')
            THEN 'East' ELSE 'Peninsular' END AS zone,
       COUNT(DISTINCT f.premise_code) AS n_stores,
       COUNT(*)                       AS n_records,
       ROUND(AVG(f.price), 2)         AS avg_price
FROM prices_clean f
JOIN premise p ON f.premise_code = p.premise_code
JOIN item i    ON f.item_code    = i.item_code
WHERE f.item_code IN (1, 1109)
GROUP BY i.item, p.premise_type, zone
ORDER BY i.item, p.premise_type, zone;


-- ---------------------------------------------------------------------
-- 8. Final state-level averages on cleaned data
-- ---------------------------------------------------------------------
-- 8a. Per item, with store counts
SELECT i.item, p.state,
       COUNT(*)                       AS n_records,
       COUNT(DISTINCT f.premise_code) AS n_stores,
       ROUND(AVG(f.price), 2)         AS avg_price
FROM prices_clean f
JOIN premise p ON f.premise_code = p.premise_code
JOIN item i    ON f.item_code    = i.item_code
GROUP BY i.item, p.state
ORDER BY i.item, avg_price DESC;

-- 8b. Eggs and cooking oil side by side
SELECT p.state,
       ROUND(AVG(CASE WHEN f.item_code = 1109 THEN f.price END), 2) AS eggs_avg,
       COUNT(DISTINCT CASE WHEN f.item_code = 1109 THEN f.premise_code END) AS eggs_stores,
       ROUND(AVG(CASE WHEN f.item_code = 267 THEN f.price END), 2)  AS oil_avg,
       COUNT(DISTINCT CASE WHEN f.item_code = 267 THEN f.premise_code END)  AS oil_stores
FROM prices_clean f
JOIN premise p ON f.premise_code = p.premise_code
WHERE f.item_code IN (1109, 267)
GROUP BY p.state
ORDER BY eggs_avg DESC;