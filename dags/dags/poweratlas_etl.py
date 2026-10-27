"""PowerAtlas ETL logic (no Airflow imports, so it can be tested on its own)."""

import os
from pathlib import Path
from urllib.parse import quote_plus

import pandas as pd
from sqlalchemy import create_engine

DATA_DIR = Path(os.getenv("POWERATLAS_DATA_DIR", "/opt/airflow/data"))
SQL_DIR = Path(os.getenv("POWERATLAS_SQL_DIR", "/opt/airflow/database"))

CSV_PATH = DATA_DIR / "raw" / "powerplants (global) - global_power_plants.csv"

CSV_TO_RAW = {
    "country code": "country_code",
    "country_long": "country_long",
    "name of powerplant": "plant_name",
    "capacity in MW": "capacity_mw",
    "latitude": "latitude",
    "longitude": "longitude",
    "primary_fuel": "primary_fuel",
    "secondary fuel": "secondary_fuel",
    "other_fuel2": "other_fuel2",
    "other_fuel3": "other_fuel3",
    "start date": "start_year_raw",
    "owner of plant": "owner",
    "generation_gwh_2021": "generation_gwh_2021",
    "geolocation_source": "geolocation_source",
    "estimated_generation_gwh_2021": "estimated_generation_gwh_2021",
}


def get_engine():
    """Build the engine when a task runs, so a missing credential fails
    that task instead of breaking DAG parsing."""
    user = os.getenv("POSTGRES_USER")
    password = os.getenv("POSTGRES_PASSWORD")
    if not user or not password:
        raise RuntimeError("POSTGRES_USER / POSTGRES_PASSWORD are not set in the Airflow container")

    host = os.getenv("POSTGRES_HOST", "host.docker.internal")
    port = os.getenv("POSTGRES_PORT", "5432")
    db = os.getenv("POSTGRES_DB", "poweratlas")
    return create_engine(
        f"postgresql+psycopg2://{quote_plus(user)}:{quote_plus(password)}@{host}:{port}/{db}"
    )


def ingest_power_plants():
    """CSV -> raw.power_plants. Truncate and load share one transaction,
    so a failed load leaves the previous data in place."""
    if not CSV_PATH.exists():
        raise FileNotFoundError(f"CSV not found: {CSV_PATH}")

    df = pd.read_csv(CSV_PATH)

    missing = set(CSV_TO_RAW) - set(df.columns)
    if missing:
        raise ValueError(f"Missing columns: {sorted(missing)}")

    df = df.rename(columns=CSV_TO_RAW)[list(CSV_TO_RAW.values())]
    df["source_file"] = CSV_PATH.name

    engine = get_engine()
    try:
        with engine.begin() as conn:
            conn.exec_driver_sql("TRUNCATE TABLE raw.power_plants RESTART IDENTITY")
            df.to_sql("power_plants", conn, schema="raw", if_exists="append",
                      index=False, method="multi", chunksize=2000)
    finally:
        engine.dispose()

    print(f"Ingested {len(df):,} rows into raw.power_plants")
    return len(df)


def run_sql_file(relative_path):
    """Run a SQL file from the database/ folder. The files manage their own
    BEGIN/COMMIT, so the connection runs in autocommit mode."""
    path = SQL_DIR / relative_path
    if not path.exists():
        raise FileNotFoundError(f"SQL file not found: {path}")

    engine = get_engine()
    conn = engine.raw_connection()
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(path.read_text())
    finally:
        conn.close()
        engine.dispose()
    print(f"Ran {relative_path}")


def build_core():
    run_sql_file("transform/01_core.sql")


def build_analytics():
    run_sql_file("transform/02_analytics.sql")


def run_quality_checks():
    """Apply the quality rules, print the report, and fail only if rows were
    lost between raw and core (known source-data issues are reported, not fatal)."""
    run_sql_file("transform/03_quality.sql")

    engine = get_engine()
    try:
        with engine.connect() as conn:
            raw_n = conn.exec_driver_sql("SELECT COUNT(*) FROM raw.power_plants").scalar()
            core_n = conn.exec_driver_sql("SELECT COUNT(*) FROM core.plants").scalar()
            rejected = conn.exec_driver_sql(
                "SELECT COUNT(*) FROM core.data_quality_issues WHERE rule = 'rejected_invalid_row'"
            ).scalar()
            summary = conn.exec_driver_sql(
                "SELECT rule, severity, issue_count FROM analytics.dq_rule_summary"
            ).fetchall()
    finally:
        engine.dispose()

    print(f"raw={raw_n:,}  core.plants={core_n:,}  rejected={rejected:,}")
    for rule, severity, n in summary:
        print(f"  [{severity:7}] {rule}: {n}")

    if core_n + rejected != raw_n:
        raise ValueError(
            f"Row reconciliation failed: raw={raw_n}, core={core_n}, rejected={rejected}"
        )