from datetime import datetime
from pathlib import Path
import os
from urllib.parse import quote_plus

import pandas as pd

from airflow import DAG
from airflow.operators.python import PythonOperator
from sqlalchemy import create_engine, engine


BASE_DIR = Path("/opt/airflow/data")

CSV_PATH = (
    BASE_DIR
    / "raw"
    / "powerplants (global) - global_power_plants.csv"
)

DB_USER = os.getenv("POSTGRES_USER")
DB_PASSWORD = os.getenv("POSTGRES_PASSWORD")
DB_HOST = os.getenv("POSTGRES_HOST", "host.docker.internal")
DB_PORT = os.getenv("POSTGRES_PORT", "5432")

if not DB_USER or not DB_PASSWORD:
    raise RuntimeError(
        "PostgreSQL credentials are not available in the Airflow container"
    )

DB_URL = (
    f"postgresql+psycopg2://{quote_plus(DB_USER)}:"
    f"{quote_plus(DB_PASSWORD)}@{DB_HOST}:{DB_PORT}/poweratlas"
)

def ingest_power_plants():
    if not CSV_PATH.exists():
        raise FileNotFoundError(f"CSV not found: {CSV_PATH}")

    df = pd.read_csv(CSV_PATH)

    expected_columns = [
        "country code",
        "country_long",
        "name of powerplant",
        "capacity in MW",
        "latitude",
        "longitude",
        "primary_fuel",
        "secondary fuel",
        "other_fuel2",
        "other_fuel3",
        "start date",
        "owner of plant",
        "generation_gwh_2021",
        "geolocation_source",
        "estimated_generation_gwh_2021",
    ]

    missing = set(expected_columns) - set(df.columns)

    if missing:
        raise ValueError(f"Missing columns: {sorted(missing)}")

    df = df.rename(
        columns={
            "country code": "country_code",
            "name of powerplant": "plant_name",
            "capacity in MW": "capacity_mw",
            "secondary fuel": "secondary_fuel",
            "start date": "start_year_raw",
            "owner of plant": "owner",
            "generation_gwh_2021": "generation_gwh_2021",
            "estimated_generation_gwh_2021": "estimated_generation_gwh_2021",
        }
    )

    df["source_file"] = CSV_PATH.name

    columns = [
        "country_code",
        "country_long",
        "plant_name",
        "capacity_mw",
        "latitude",
        "longitude",
        "primary_fuel",
        "secondary_fuel",
        "other_fuel2",
        "other_fuel3",
        "start_year_raw",
        "owner",
        "generation_gwh_2021",
        "geolocation_source",
        "estimated_generation_gwh_2021",
        "source_file",
 
    ]

    df = df[columns]

    engine = create_engine(DB_URL)

    with engine.begin() as conn:
      conn.exec_driver_sql(
        "TRUNCATE TABLE raw.power_plants RESTART IDENTITY"
    )

    df.to_sql(
    "power_plants",
    engine,
    schema="raw",
    if_exists="append",
    index=False,
    method="multi",
    )

    engine.dispose()

    print(f"Ingested {len(df):,} rows into raw.power_plants")


with DAG(
    dag_id="poweratlas_ingestion",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["poweratlas", "ingestion"],
) as dag:

    ingest = PythonOperator(
        task_id="ingest_power_plants",
        python_callable=ingest_power_plants,
    )