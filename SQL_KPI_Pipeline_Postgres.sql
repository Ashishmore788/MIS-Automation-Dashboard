/*================================================================
  MIS AUTOMATION DASHBOARD — SQL DATA PIPELINE (PostgreSQL 18)
  
  STAGE 1: Staging table — receives Master_Data.csv loaded via
           Python (load_to_postgres.py using SQLAlchemy/pandas)
           Columns are capitalised to match CSV header exactly.
  STAGE 2: Typed fact table — casts all columns, deduplicates
           on ticket_id PRIMARY KEY
  STAGE 3: 4 KPI views — Power BI connects to these views only

  FIXES APPLIED vs original script:
  - 'source' renamed to 'department' throughout (reserved word
    in PostgreSQL 18 causes GROUP BY errors if used unquoted)
  - stg_tickets columns capitalised to match pandas to_sql output
  - Removed CASE WHEN col = '' checks on numeric columns
    (pandas preserves NaN as NULL, not empty string)
  - Added CASCADE to DROP TABLE for safe reruns
  - Verified against 440-row Master_Data.csv
================================================================*/

-- ============================================================
-- UTILITY: clean slate for reruns
-- ============================================================
DROP TABLE IF EXISTS fact_tickets CASCADE;
DROP TABLE IF EXISTS stg_tickets CASCADE;

-- ============================================================
-- STAGE 1: Staging table (capitalised to match pandas to_sql)
-- ============================================================
CREATE TABLE stg_tickets (
    "Source"            VARCHAR(20),
    "Ticket_ID"         VARCHAR(20),
    "Created_Date"      VARCHAR(40),
    "Closed_Date"       VARCHAR(40),
    "Priority"          VARCHAR(5),
    "Status"            VARCHAR(20),
    "Region"            VARCHAR(20),
    "Agent"             VARCHAR(50),
    "SLA_Target_Hrs"    NUMERIC(6,2),
    "TAT_Hrs"           NUMERIC(8,2),
    "SLA_Status"        VARCHAR(15),
    "TAT_Variance_Hrs"  NUMERIC(8,2),
    "Month"             VARCHAR(10)
);

-- Load via Python (recommended — avoids file permission issues):
--   python load_to_postgres.py
--
-- Or via psql client:
-- \copy stg_tickets("Source","Ticket_ID","Created_Date","Closed_Date",
--   "Priority","Status","Region","Agent","SLA_Target_Hrs","TAT_Hrs",
--   "SLA_Status","TAT_Variance_Hrs","Month")
-- FROM 'Master_Data.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- ============================================================
-- STAGE 2: Core fact table
-- 'department' used instead of 'source' (PG18 reserved word)
-- ============================================================
CREATE TABLE fact_tickets (
    department        VARCHAR(20),
    ticket_id         VARCHAR(20) PRIMARY KEY,
    created_date      TIMESTAMP,
    closed_date       TIMESTAMP NULL,
    priority          VARCHAR(5),
    status            VARCHAR(20),
    region            VARCHAR(20),
    agent             VARCHAR(50),
    sla_target_hrs    NUMERIC(6,2),
    tat_hrs           NUMERIC(8,2) NULL,
    sla_status        VARCHAR(15),
    tat_variance_hrs  NUMERIC(8,2) NULL,
    report_month      VARCHAR(10)
);

INSERT INTO fact_tickets
SELECT DISTINCT
    "Source",
    "Ticket_ID",
    "Created_Date"::TIMESTAMP,
    "Closed_Date"::TIMESTAMP,
    "Priority",
    "Status",
    "Region",
    "Agent",
    "SLA_Target_Hrs"::NUMERIC(6,2),
    "TAT_Hrs"::NUMERIC(8,2),
    "SLA_Status",
    "TAT_Variance_Hrs"::NUMERIC(8,2),
    "Month"
FROM stg_tickets;

-- SELECT COUNT(*) FROM fact_tickets; -- expect 440

-- ============================================================
-- STAGE 3a: SLA Compliance % by Department / Region / Month
-- ============================================================
CREATE OR REPLACE VIEW vw_sla_compliance AS
SELECT
    department,
    region,
    report_month,
    COUNT(*) AS total_tickets,
    SUM(CASE WHEN sla_status = 'Met'      THEN 1 ELSE 0 END) AS met_count,
    SUM(CASE WHEN sla_status = 'Breached' THEN 1 ELSE 0 END) AS breached_count,
    SUM(CASE WHEN sla_status = 'Open'     THEN 1 ELSE 0 END) AS open_count,
    ROUND(
        100.0 * SUM(CASE WHEN sla_status = 'Met' THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN sla_status IN ('Met','Breached') THEN 1 ELSE 0 END), 0)
    , 1) AS sla_compliance_pct
FROM fact_tickets
GROUP BY department, region, report_month;

-- ============================================================
-- STAGE 3b: TAT & Variance by Department / Priority / Month
-- ============================================================
CREATE OR REPLACE VIEW vw_tat_variance AS
SELECT
    department,
    priority,
    report_month,
    COUNT(*) AS closed_tickets,
    ROUND(AVG(tat_hrs)::numeric, 2)          AS avg_tat_hrs,
    ROUND(AVG(sla_target_hrs)::numeric, 2)   AS avg_sla_target_hrs,
    ROUND(AVG(tat_variance_hrs)::numeric, 2) AS avg_variance_hrs,
    ROUND(MAX(tat_variance_hrs)::numeric, 2) AS worst_variance_hrs
FROM fact_tickets
WHERE sla_status IN ('Met', 'Breached')
GROUP BY department, priority, report_month;

-- ============================================================
-- STAGE 3c: Agent-level performance
-- ============================================================
CREATE OR REPLACE VIEW vw_agent_performance AS
SELECT
    agent,
    department,
    COUNT(*) AS tickets_handled,
    ROUND(AVG(tat_hrs)::numeric, 2) AS avg_tat_hrs,
    SUM(CASE WHEN sla_status = 'Breached' THEN 1 ELSE 0 END) AS breaches,
    ROUND(
        100.0 * SUM(CASE WHEN sla_status = 'Met' THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN sla_status IN ('Met','Breached') THEN 1 ELSE 0 END), 0)
    , 1) AS sla_compliance_pct
FROM fact_tickets
WHERE sla_status IN ('Met', 'Breached')
GROUP BY agent, department;

-- ============================================================
-- STAGE 3d: Monthly trend
-- ============================================================
CREATE OR REPLACE VIEW vw_monthly_trend AS
SELECT
    report_month,
    COUNT(*) AS total_tickets,
    ROUND(AVG(tat_hrs)::numeric, 2) AS avg_tat_hrs,
    ROUND(
        100.0 * SUM(CASE WHEN sla_status = 'Met' THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN sla_status IN ('Met','Breached') THEN 1 ELSE 0 END), 0)
    , 1) AS sla_compliance_pct
FROM fact_tickets
GROUP BY report_month
ORDER BY report_month;

-- ============================================================
-- VALIDATION (expected: Operations ~80.4%, Finance ~72.9%, IT ~70.7%)
-- ============================================================
-- SELECT * FROM vw_sla_compliance  ORDER BY report_month, department;
-- SELECT * FROM vw_tat_variance    ORDER BY report_month, department, priority;
-- SELECT * FROM vw_agent_performance ORDER BY sla_compliance_pct;
-- SELECT * FROM vw_monthly_trend;
