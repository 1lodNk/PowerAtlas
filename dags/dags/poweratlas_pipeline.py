from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator

import poweratlas_etl as etl

with DAG(
    dag_id="poweratlas_pipeline",
    description="CSV -> raw -> core -> analytics, followed by data quality checks",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["poweratlas"],
) as dag:

    ingest = PythonOperator(task_id="ingest_raw", python_callable=etl.ingest_power_plants)
    core = PythonOperator(task_id="build_core", python_callable=etl.build_core)
    analytics = PythonOperator(task_id="build_analytics", python_callable=etl.build_analytics)
    quality = PythonOperator(task_id="quality_checks", python_callable=etl.run_quality_checks)

    ingest >> core >> analytics >> quality
