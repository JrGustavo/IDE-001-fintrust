"""
pipeline.py
===========
Orquestador ETL para FinTrust Data Platform.

Ejecuta en orden:
  1. Creación de esquemas y tablas RAW
  2. Inserción de datos de muestra
  3. Validaciones de calidad sobre datos RAW
  4. Transformaciones Staging
  5. Construcción del Data Mart analítico
  6. Generación de vistas de negocio
  7. Carga incremental de pagos (simulada)
  8. Reporte final de ejecución

Uso:
  python pipeline.py [--incremental] [--validate-only] [--export-csv]

Motor: DuckDB (simulación de BigQuery)
Para BigQuery real: reemplazar la conexión en get_connection()
"""

import duckdb
import logging
import sys
import os
import json
import argparse
from datetime import datetime
from pathlib import Path

# =============================================================================
# CONFIGURACIÓN
# =============================================================================

BASE_DIR = Path(__file__).parent.parent
SQL_DIR = BASE_DIR / "sql"
LOG_DIR = BASE_DIR / "logs"
DB_PATH = BASE_DIR / "fintrust.duckdb"      # Archivo persistente DuckDB
WATERMARK_FILE = BASE_DIR / "python" / "watermark.json"

LOG_DIR.mkdir(exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(LOG_DIR / f"pipeline_{datetime.now():%Y%m%d_%H%M%S}.log"),
    ],
)
log = logging.getLogger(__name__)


# =============================================================================
# CONEXIÓN
# =============================================================================

def get_connection() -> duckdb.DuckDBPyConnection:
    """
    Retorna conexión al motor de datos.

    Para migrar a BigQuery real, reemplazar con:
        from google.cloud import bigquery
        client = bigquery.Client(project="mi-proyecto-gcp")
        return client

    DuckDB es compatible en SQL con BigQuery para las queries de este pipeline.
    """
    conn = duckdb.connect(str(DB_PATH))
    log.info(f"Conectado a DuckDB: {DB_PATH}")
    return conn


def execute_sql_file(conn: duckdb.DuckDBPyConnection, path: Path) -> None:
    """Ejecuta un archivo SQL completo."""
    log.info(f"Ejecutando SQL: {path.name}")
    sql = path.read_text(encoding="utf-8")
    try:
        conn.execute(sql)
        log.info(f"  ✓ {path.name} completado")
    except Exception as e:
        log.error(f"  ✗ Error en {path.name}: {e}")
        raise


def execute_query(conn: duckdb.DuckDBPyConnection, sql: str, description: str = ""):
    """Ejecuta una query SQL y retorna resultados."""
    try:
        result = conn.execute(sql).fetchall()
        if description:
            log.info(f"  ✓ {description}")
        return result
    except Exception as e:
        log.error(f"  ✗ Error ejecutando query [{description}]: {e}")
        raise


# =============================================================================
# PASO 1 & 2: RAW
# =============================================================================

def step_raw(conn: duckdb.DuckDBPyConnection) -> None:
    """Crea tablas RAW y carga datos de muestra."""
    log.info("=" * 60)
    log.info("PASO 1-2: Carga de datos RAW")
    log.info("=" * 60)
    execute_sql_file(conn, SQL_DIR / "01-raw" / "create_raw_tables.sql")

    # Verificar registros cargados
    tables = ["customers", "loans", "installments", "payments"]
    for table in tables:
        count = execute_query(
            conn,
            f"SELECT COUNT(*) FROM raw_fintrust.{table}",
            f"raw_fintrust.{table}"
        )
        log.info(f"    raw_fintrust.{table}: {count[0][0]} registros")


# =============================================================================
# PASO 3: VALIDACIONES DE CALIDAD
# =============================================================================

def step_validate(conn: duckdb.DuckDBPyConnection) -> dict:
    """
    Ejecuta validaciones de calidad sobre datos RAW.
    Retorna dict con resultados para el reporte final.
    """
    log.info("=" * 60)
    log.info("PASO 3: Validaciones de Calidad de Datos")
    log.info("=" * 60)

    from validations import run_all_validations
    results = run_all_validations(conn)
    return results


# =============================================================================
# PASO 4: STAGING
# =============================================================================

def step_staging(conn: duckdb.DuckDBPyConnection) -> None:
    """Ejecuta transformaciones staging para las 4 tablas."""
    log.info("=" * 60)
    log.info("PASO 4: Transformaciones Staging")
    log.info("=" * 60)

    staging_files = [
        "stg_customers.sql",
        "stg_loans.sql",
        "stg_installments.sql",
        "stg_payments.sql",
    ]

    for fname in staging_files:
        execute_sql_file(conn, SQL_DIR / "02-staging" / fname)

    # Reporte de staging
    stg_tables = ["stg_customers", "stg_loans", "stg_installments", "stg_payments"]
    log.info("Registros en staging:")
    for table in stg_tables:
        count = execute_query(
            conn,
            f"SELECT COUNT(*) FROM staging_fintrust.{table}"
        )
        log.info(f"    staging_fintrust.{table}: {count[0][0]} registros")


# =============================================================================
# PASO 5 & 6: ANALYTICS
# =============================================================================

def step_analytics(conn: duckdb.DuckDBPyConnection) -> None:
    """Construye el data mart y vistas analíticas."""
    log.info("=" * 60)
    log.info("PASO 5-6: Data Mart y Vistas Analíticas")
    log.info("=" * 60)

    execute_sql_file(conn, SQL_DIR / "03-analytics" / "dm_cartera_diaria.sql")
    execute_sql_file(conn, SQL_DIR / "03-analytics" / "vw_dataset_bi.sql")

    count = execute_query(conn, "SELECT COUNT(*) FROM analytics_fintrust.dm_cartera_diaria")
    log.info(f"  dm_cartera_diaria: {count[0][0]} créditos")


# =============================================================================
# PASO 7: CARGA INCREMENTAL (simulada)
# =============================================================================

def get_watermark() -> str:
    """Lee el watermark de la última carga incremental."""
    if WATERMARK_FILE.exists():
        with open(WATERMARK_FILE) as f:
            data = json.load(f)
            return data.get("last_loaded_at", "2000-01-01T00:00:00")
    return "2000-01-01T00:00:00"


def save_watermark(conn: duckdb.DuckDBPyConnection) -> None:
    """Guarda el watermark de la carga actual."""
    result = execute_query(
        conn,
        "SELECT MAX(loaded_at)::VARCHAR FROM raw_fintrust.payments"
    )
    max_ts = result[0][0] if result and result[0][0] else "2000-01-01T00:00:00"
    with open(WATERMARK_FILE, "w") as f:
        json.dump({"last_loaded_at": max_ts, "updated_at": datetime.now().isoformat()}, f)
    log.info(f"  Watermark guardado: {max_ts}")


def run_incremental_payments(conn: duckdb.DuckDBPyConnection) -> None:
    """
    Simula una carga incremental de pagos basada en watermark loaded_at.

    En producción BigQuery:
    - Esta función correría en Cloud Run o Cloud Composer
    - Leería de GCS el archivo de pagos del día
    - Haría MERGE INTO raw_fintrust.payments WHERE payment_id NOT IN (SELECT payment_id FROM staging)
    - Luego ejecutaría solo stg_payments.sql para el nuevo rango
    """
    log.info("=" * 60)
    log.info("PASO 7: Lógica de Carga Incremental (Pagos)")
    log.info("=" * 60)

    watermark = get_watermark()
    log.info(f"  Watermark anterior: {watermark}")

    # Contar nuevos pagos desde el watermark
    new_payments = execute_query(
        conn,
        f"""
        SELECT COUNT(*) 
        FROM raw_fintrust.payments 
        WHERE loaded_at > TIMESTAMP '{watermark}'
        """
    )
    n_new = new_payments[0][0]
    log.info(f"  Nuevos pagos desde watermark: {n_new}")

    if n_new > 0:
        log.info(f"  Procesando {n_new} pagos nuevos...")
        # En producción: INSERT INTO staging solo los nuevos
        # Aquí: full refresh de stg_payments (volumen pequeño en demo)
        execute_sql_file(conn, SQL_DIR / "02-staging" / "stg_payments.sql")
        # Reconstruir Data Mart con los nuevos pagos
        execute_sql_file(conn, SQL_DIR / "03-analytics" / "dm_cartera_diaria.sql")
        log.info("  ✓ Carga incremental completada")
    else:
        log.info("  Sin nuevos pagos, saltando reproceso")

    save_watermark(conn)


# =============================================================================
# PASO 8: REPORTE FINAL
# =============================================================================

def step_report(conn: duckdb.DuckDBPyConnection, validation_results: dict) -> None:
    """Genera un resumen ejecutivo del pipeline."""
    log.info("=" * 60)
    log.info("PASO 8: Reporte Final del Pipeline")
    log.info("=" * 60)

    # KPIs del Data Mart
    kpis = execute_query(
        conn,
        """
        SELECT
            COUNT(loan_id)                                      AS creditos_activos,
            SUM(monto_desembolsado)                             AS cartera_total,
            SUM(saldo_mora)                                     AS total_mora,
            ROUND(SUM(saldo_mora)/SUM(saldo_pendiente)*100, 2)  AS indice_mora_pct,
            COUNT(CASE WHEN en_mora=TRUE THEN 1 END)            AS creditos_mora,
            MAX(max_dias_atraso)                                AS max_dias_atraso
        FROM analytics_fintrust.dm_cartera_diaria
        """
    )

    if kpis:
        row = kpis[0]
        log.info("\n  📊 KPIs de Cartera:")
        log.info(f"     Créditos activos:    {row[0]}")
        log.info(f"     Cartera total:       ${row[1]:,.0f}" if row[1] else "     Cartera total: N/A")
        log.info(f"     Total mora:          ${row[2]:,.0f}" if row[2] else "     Total mora: N/A")
        log.info(f"     Índice de mora:      {row[3]}%" if row[3] else "     Índice de mora: 0%")
        log.info(f"     Créditos en mora:    {row[4]}")
        log.info(f"     Máx días de atraso:  {row[5]}")

    # Resumen de validaciones
    log.info("\n  🔍 Resumen de Calidad de Datos:")
    if validation_results:
        for check, result in validation_results.items():
            status = "✓" if result.get("passed") else "⚠"
            log.info(f"     {status} {check}: {result.get('detail', '')}")

    log.info("\n  ✅ Pipeline completado exitosamente")
    log.info(f"     Base de datos: {DB_PATH}")
    log.info(f"     Tablas disponibles: raw_fintrust, staging_fintrust, analytics_fintrust")


# =============================================================================
# EXPORT CSV (opcional, para BI Desktop)
# =============================================================================

def export_to_csv(conn: duckdb.DuckDBPyConnection) -> None:
    """Exporta el dataset BI a CSV para uso en Power BI Desktop."""
    output_path = BASE_DIR / "fintrust_dataset_bi.csv"
    log.info(f"Exportando dataset BI a: {output_path}")
    conn.execute(f"""
        COPY (SELECT * FROM analytics_fintrust.vw_dataset_bi)
        TO '{output_path}'
        (HEADER, DELIMITER ',')
    """)
    log.info(f"  ✓ CSV exportado: {output_path}")


# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="FinTrust ETL Pipeline")
    parser.add_argument("--incremental", action="store_true",
                        help="Ejecutar solo carga incremental de pagos")
    parser.add_argument("--validate-only", action="store_true",
                        help="Ejecutar solo validaciones de calidad")
    parser.add_argument("--export-csv", action="store_true",
                        help="Exportar dataset BI a CSV al finalizar")
    args = parser.parse_args()

    start_time = datetime.now()
    log.info("=" * 60)
    log.info("🚀 FINTRUST DATA PIPELINE - INICIO")
    log.info(f"   Fecha/hora: {start_time:%Y-%m-%d %H:%M:%S}")
    log.info("=" * 60)

    conn = get_connection()
    validation_results = {}

    try:
        if args.validate_only:
            # Solo validaciones (útil para monitoreo)
            validation_results = step_validate(conn)
        elif args.incremental:
            # Solo carga incremental
            run_incremental_payments(conn)
        else:
            # Pipeline completo
            step_raw(conn)
            validation_results = step_validate(conn)
            step_staging(conn)
            step_analytics(conn)
            run_incremental_payments(conn)
            step_report(conn, validation_results)

        if args.export_csv:
            export_to_csv(conn)

    except Exception as e:
        log.error(f"💥 Pipeline fallido: {e}")
        conn.close()
        sys.exit(1)

    finally:
        elapsed = (datetime.now() - start_time).total_seconds()
        log.info(f"\n⏱  Tiempo total: {elapsed:.2f}s")
        conn.close()


if __name__ == "__main__":
    main()
