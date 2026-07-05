# 📊 MIS Automation Dashboard

> **End-to-end automated MIS reporting pipeline** — Python ETL · PostgreSQL · Power BI

![Python](https://img.shields.io/badge/Python-3.13-3776AB?style=flat&logo=python&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-4169E1?style=flat&logo=postgresql&logoColor=white)
![Power BI](https://img.shields.io/badge/Power%20BI-Dashboard-F2C811?style=flat&logo=powerbi&logoColor=black)
![pandas](https://img.shields.io/badge/pandas-ETL-150458?style=flat&logo=pandas&logoColor=white)

---

## 🧩 Problem Statement

Three departments (Operations, Finance, IT) each export daily ticket/service-request data in **completely different formats** — different column names, date formats, and status spellings. A manual analyst had to open three files, copy-paste into a master sheet, calculate turnaround time, check SLA targets, and rebuild charts — every single day.

This project **automates that entire cycle**: from raw multi-source exports to a live, interactive Power BI dashboard — with zero manual steps.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    RAW DATA SOURCES                     │
│  Operations_Export  │  Finance_Export  │  IT_Export     │
│  (native datetime)  │  (text dd-mm-yy) │  (SLA(Hrs) col)│
└────────────┬────────────────┬──────────────┬────────────┘
             │                │              │
             ▼                ▼              ▼
┌─────────────────────────────────────────────────────────┐
│           LAYER 1 — Python ETL Pipeline                 │
│           consolidate_mis_data.py                       │
│  • Config-driven schema mapping (SOURCE_SCHEMAS dict)   │
│  • Date parsing (native + text formats)                 │
│  • Text cleaning & normalisation                        │
│  • TAT calculation & SLA compliance flagging            │
│  → Output: Master_Data.csv (440 rows)                   │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│           LAYER 2 — PostgreSQL Data Model               │
│           SQL_KPI_Pipeline_Postgres.sql                 │
│  stg_tickets  →  fact_tickets  →  4 KPI Views           │
│  • vw_sla_compliance   (dept / region / month)          │
│  • vw_tat_variance     (priority / dept / month)        │
│  • vw_agent_performance (agent-level KPIs)              │
│  • vw_monthly_trend    (executive trend line)           │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│           LAYER 3 — Power BI Dashboard                  │
│           MIS_Dashboard.pbix                            │
│  • Executive Summary  • SLA Compliance                  │
│  • TAT & Variance     • Agent Performance               │
└─────────────────────────────────────────────────────────┘
```

---

## 📈 Key Results

| KPI | Value |
|---|---|
| Total Tickets Processed | **440** |
| Overall SLA Compliance | **74.9%** |
| Operations Compliance | **80.4%** ✅ |
| Finance Compliance | **72.9%** ⚠️ |
| IT Compliance | **70.7%** 🔴 |
| Dept Compliance Gap | **9.7 percentage points** |
| Avg TAT — P1 (Critical) | **3.89 hrs** (target: 4 hrs) |
| Avg TAT — P2 (High) | **7.67 hrs** (target: 8 hrs) |
| Avg TAT — P3 (Medium) | **23.61 hrs** (target: 24 hrs) |
| Avg TAT — P4 (Low) | **46.16 hrs** (target: 48 hrs) |

> IT North region recorded **37.5% SLA compliance** in January — the dashboard surfaces this kind of drill-down insight for stakeholder escalation.

---

## 📁 Project Structure

```
MIS-Automation-Dashboard/
│
├── 📄 consolidate_mis_data.py       # Python ETL pipeline (main script)
├── 📄 load_to_postgres.py           # PostgreSQL loader via SQLAlchemy
├── 📄 SQL_KPI_Pipeline_Postgres.sql # Full SQL pipeline (staging → fact → views)
│
├── 📊 Raw_Data_Exports.xlsx         # Simulated raw data (3 sheets, 3 formats)
├── 📊 Master_Data.csv               # Cleaned consolidated output (440 rows)
│
├── 🎨 MIS_Dashboard_Theme.json      # Power BI custom theme file
├── 📝 MIS_Automation_Dashboard_Report.docx  # Full technical report
└── 📄 VBA_Consolidation_Macro.bas   # Excel VBA equivalent (for MIS/Ops roles)
```

---

## 🚀 How to Run

### Prerequisites
```bash
pip install pandas openpyxl sqlalchemy psycopg2-binary
```

### Step 1 — Generate Master Data
```bash
python consolidate_mis_data.py --input Raw_Data_Exports.xlsx --output Master_Data.csv
```
Expected output:
```
Wrote 440 rows to Master_Data.csv

Total records: 440
Overall SLA compliance: 74.9%

By department:
Finance       72.9
IT            70.7
Operations    80.4
```

### Step 2 — Load to PostgreSQL
```bash
# Update password in load_to_postgres.py first
python load_to_postgres.py
```

### Step 3 — Run SQL Pipeline
Open `SQL_KPI_Pipeline_Postgres.sql` in pgAdmin 4 and execute. This creates:
- `stg_tickets` — raw staging table
- `fact_tickets` — typed, deduplicated fact table
- `vw_sla_compliance` — SLA % by dept/region/month
- `vw_tat_variance` — TAT vs target by priority
- `vw_agent_performance` — agent-level KPIs
- `vw_monthly_trend` — monthly executive trend

### Step 4 — Connect Power BI
- Power BI Desktop → Get Data → PostgreSQL
- Server: `localhost`, Database: `mis_dashboard`
- Select all 4 KPI views → Load
- Apply `MIS_Dashboard_Theme.json` via View → Themes → Browse

---

## 🗄️ SQL Data Model

```
stg_tickets (raw, all VARCHAR)
    ↓
fact_tickets (typed, PRIMARY KEY on ticket_id)
    ↓
┌─────────────────────┬──────────────────────┐
│  vw_sla_compliance  │  vw_tat_variance     │
│  vw_agent_performance│  vw_monthly_trend   │
└─────────────────────┴──────────────────────┘
```

The **staging → fact → views** pattern separates raw data ingestion from analytical logic. KPI definitions are centralised in views — updating a metric requires changing one view, not reloading data.

---

## 📊 Dashboard Pages

| Page | Visuals | Data Source |
|---|---|---|
| Executive Summary | KPI cards, trend line, donut | `vw_monthly_trend`, `vw_sla_compliance` |
| SLA Compliance | Clustered bar, stacked bar, table | `vw_sla_compliance` |
| TAT & Variance | Priority bar chart, worst-breach table | `vw_tat_variance` |
| Agent Performance | KPI table, department/month slicers | `vw_agent_performance` |

---

## 🔧 Technical Decisions

**Why config-driven schema mapping?**
The `SOURCE_SCHEMAS` dictionary means adding a 4th department requires one new dict entry — no changes to processing logic. This is the pattern that separates a script from a pipeline.

**Why staging → fact → views?**
- `stg_tickets`: preserves raw data for audit/replay
- `fact_tickets`: single typed, deduplicated source of truth
- Views: centralised KPI definitions that Power BI consumes — change a metric in one place

**Why `department` instead of `source`?**
`source` is a reserved word in PostgreSQL 18 — causes silent errors in `GROUP BY` clauses. Renamed at the fact table level.

---

## 📄 Technical Report

See [`MIS_Automation_Dashboard_Report.docx`](./MIS_Automation_Dashboard_Report.docx) for the full technical write-up covering methodology, results, discussion and references.

---

## 💼 Resume Bullet

```
MIS Automation Dashboard | Python, PostgreSQL, Power BI
• Built a config-driven Python (pandas) ETL pipeline consolidating
  heterogeneous multi-source ticket data, automating TAT calculation
  and SLA compliance flagging across 440 records (3 departments, Q1 2026)
• Designed a PostgreSQL data model (staging → fact → 4 KPI views) and
  Power BI dashboard tracking SLA compliance, TAT variance, and agent
  performance — surfacing a 9.7-point compliance gap between departments
  for stakeholder management
```

---

## 👤 Author

**Ashish More**
- GitHub: [@Ashishmore788](https://github.com/Ashishmore788)

---

*Data period: January – March 2026 | Records: 440 | Stack: Python · PostgreSQL · Power BI*
