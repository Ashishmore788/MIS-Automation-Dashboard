"""
MIS Automation Dashboard — Data Consolidation Pipeline
========================================================
Consolidates ticket/request exports from three departments (Operations,
Finance, IT) — each in a different schema and date format, simulating
real multi-system MIS feeds — into one clean fact table with calculated
TAT (Turnaround Time) and SLA compliance, ready for the SQL/Power BI layer.

Usage:
    python consolidate_mis_data.py --input Raw_Data_Exports.xlsx --output Master_Data.csv
"""

import argparse
import pandas as pd

# Each source sheet maps its own column names onto one standard schema.
# Adding a new department later only means adding one entry here.
SOURCE_SCHEMAS = {
    "Operations_Export": {
        "source_label": "Operations",
        "columns": {
            "Ticket_ID": "Ticket_ID", "Request_Date": "Created_Date",
            "Closure_Date": "Closed_Date", "Priority": "Priority",
            "Status": "Status", "Region": "Region", "Assigned_To": "Agent",
            "SLA_Target_Hrs": "SLA_Target_Hrs",
        },
        "date_format": None,  # already native datetime
    },
    "Finance_Export": {
        "source_label": "Finance",
        "columns": {
            "Req_ID": "Ticket_ID", "Date_Raised": "Created_Date",
            "Date_Closed": "Closed_Date", "Priority_Level": "Priority",
            "Current_Status": "Status", "Branch": "Region", "Owner": "Agent",
            "SLA_Hrs_Target": "SLA_Target_Hrs",
        },
        "date_format": "%d-%m-%Y %H:%M",  # exported as text, dd-mm-yyyy
    },
    "IT_Export": {
        "source_label": "IT",
        "columns": {
            "TicketNo": "Ticket_ID", "Created_On": "Created_Date",
            "Resolved_On": "Closed_Date", "Priority": "Priority",
            "Status": "Status", "Location": "Region", "Handled_By": "Agent",
            "SLA(Hrs)": "SLA_Target_Hrs",
        },
        "date_format": None,
    },
}

STANDARD_COLS = ["Source", "Ticket_ID", "Created_Date", "Closed_Date", "Priority",
                  "Status", "Region", "Agent", "SLA_Target_Hrs"]


def load_source(xl: pd.ExcelFile, sheet_name: str, schema: dict) -> pd.DataFrame:
    """Read one source sheet and standardize it to the common schema."""
    df = xl.parse(sheet_name)

    if schema["date_format"]:
        for col in ("Date_Raised", "Date_Closed") if sheet_name == "Finance_Export" else []:
            pass  # explicit per-sheet handling below covers this case generically
        for raw_col, std_col in schema["columns"].items():
            if std_col in ("Created_Date", "Closed_Date"):
                df[raw_col] = pd.to_datetime(df[raw_col], format=schema["date_format"], errors="coerce")

    df = df.rename(columns=schema["columns"])[list(schema["columns"].values())]
    df.insert(0, "Source", schema["source_label"])
    return df[STANDARD_COLS]


def clean(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize text fields and handle missing agents."""
    df["Status"] = df["Status"].astype(str).str.strip().str.title()
    df["Region"] = df["Region"].astype(str).str.strip()
    df["Priority"] = df["Priority"].astype(str).str.strip()
    df["Agent"] = df["Agent"].astype(str).str.strip().replace({"nan": "Unassigned", "": "Unassigned"})
    return df


def calculate_kpis(df: pd.DataFrame) -> pd.DataFrame:
    """Add TAT (hrs), SLA status (Met/Breached/Open), and variance vs SLA target."""
    df["TAT_Hrs"] = ((df["Closed_Date"] - df["Created_Date"]).dt.total_seconds() / 3600).round(2)

    def sla_status(row):
        if pd.isna(row["Closed_Date"]):
            return "Open"
        return "Met" if row["TAT_Hrs"] <= row["SLA_Target_Hrs"] else "Breached"

    df["SLA_Status"] = df.apply(sla_status, axis=1)
    df["TAT_Variance_Hrs"] = (df["TAT_Hrs"] - df["SLA_Target_Hrs"]).round(2)
    df.loc[df["Closed_Date"].isna(), ["TAT_Hrs", "TAT_Variance_Hrs"]] = None
    df["Month"] = df["Created_Date"].dt.to_period("M").astype(str)
    return df


def build_master(input_path: str) -> pd.DataFrame:
    xl = pd.ExcelFile(input_path)
    frames = [load_source(xl, sheet, schema) for sheet, schema in SOURCE_SCHEMAS.items()]
    master = pd.concat(frames, ignore_index=True)
    master = clean(master)
    master = calculate_kpis(master)
    return master


def print_summary(df: pd.DataFrame) -> None:
    closed = df[df["SLA_Status"].isin(["Met", "Breached"])]
    overall_pct = round(100 * (closed["SLA_Status"] == "Met").mean(), 1)
    print(f"Total records: {len(df)}")
    print(f"Overall SLA compliance: {overall_pct}%")
    print("\nBy department:")
    print((closed.groupby("Source")["SLA_Status"]
           .apply(lambda s: round(100 * (s == "Met").mean(), 1))))
    print("\nAvg TAT by priority (hrs):")
    print(closed.groupby("Priority")["TAT_Hrs"].mean().round(2))


def main():
    parser = argparse.ArgumentParser(description="Consolidate MIS ticket exports into a clean fact table.")
    parser.add_argument("--input", default="Raw_Data_Exports.xlsx", help="Path to multi-sheet raw export workbook")
    parser.add_argument("--output", default="Master_Data.csv", help="Path for the consolidated output CSV")
    args = parser.parse_args()

    master = build_master(args.input)
    master.to_csv(args.output, index=False)
    print(f"Wrote {len(master)} rows to {args.output}\n")
    print_summary(master)


if __name__ == "__main__":
    main()
