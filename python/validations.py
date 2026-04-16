"""
validations.py
==============
Módulo de validaciones de calidad de datos para FinTrust.

Aplica controles de:
  - Completitud (nulls en campos obligatorios)
  - Unicidad (duplicados en PKs)
  - Integridad referencial (FKs entre tablas)
  - Validez de valores (rangos, enumerados)
  - Consistencia entre tablas

Uso:
  python validations.py                   # Ejecutar validaciones standalone
  from validations import run_all_validations  # Importar en pipeline
"""

import duckdb
import logging
import sys
from pathlib import Path
from datetime import datetime

log = logging.getLogger(__name__)

DB_PATH = Path(__file__).parent.parent / "fintrust.duckdb"


# =============================================================================
# INFRAESTRUCTURA DE VALIDACIONES
# =============================================================================

class ValidationResult:
    def __init__(self, name: str, table: str, passed: bool, count: int, detail: str):
        self.name = name
        self.table = table
        self.passed = passed
        self.count = count      # Nº de registros que FALLAN la validación
        self.detail = detail

    def __repr__(self):
        status = "✓ PASS" if self.passed else "⚠ WARN"
        return f"[{status}] {self.table}.{self.name}: {self.detail} (afecta {self.count} registros)"


def run_check(
    conn: duckdb.DuckDBPyConnection,
    name: str,
    table: str,
    sql: str,
    threshold: int = 0
) -> ValidationResult:
    """
    Ejecuta una validación SQL que cuenta registros que NO cumplen la regla.
    threshold: cantidad máxima de registros fallidos permitida (0 = ninguno).
    """
    try:
        result = conn.execute(sql).fetchone()
        count = result[0] if result else 0
        passed = count <= threshold
        detail = f"{count} registros con problema"
        return ValidationResult(name, table, passed, count, detail)
    except Exception as e:
        return ValidationResult(name, table, False, -1, f"ERROR: {e}")


# =============================================================================
# VALIDACIONES POR TABLA
# =============================================================================

def validate_customers(conn) -> list:
    checks = []

    # C1: Sin customer_id nulo
    checks.append(run_check(conn, "pk_no_nula", "customers",
        "SELECT COUNT(*) FROM raw_fintrust.customers WHERE customer_id IS NULL OR TRIM(customer_id)=''"))

    # C2: customer_id único
    checks.append(run_check(conn, "pk_unica", "customers",
        """
        SELECT COUNT(*) FROM (
            SELECT customer_id, COUNT(*) AS cnt
            FROM raw_fintrust.customers
            GROUP BY customer_id
            HAVING cnt > 1
        )
        """))

    # C3: Segmento en valores válidos
    checks.append(run_check(conn, "segmento_valido", "customers",
        """
        SELECT COUNT(*) FROM raw_fintrust.customers
        WHERE segment NOT IN ('Mass Market','Premium','SME')
        """))

    # C4: Ingreso mensual positivo
    checks.append(run_check(conn, "ingreso_positivo", "customers",
        "SELECT COUNT(*) FROM raw_fintrust.customers WHERE monthly_income IS NULL OR monthly_income <= 0"))

    # C5: Ciudad no nula
    checks.append(run_check(conn, "ciudad_no_nula", "customers",
        "SELECT COUNT(*) FROM raw_fintrust.customers WHERE city IS NULL OR TRIM(city) = ''"))

    return checks


def validate_loans(conn) -> list:
    checks = []

    # L1: PK no nula
    checks.append(run_check(conn, "pk_no_nula", "loans",
        "SELECT COUNT(*) FROM raw_fintrust.loans WHERE loan_id IS NULL OR TRIM(loan_id)=''"))

    # L2: PK única
    checks.append(run_check(conn, "pk_unica", "loans",
        """
        SELECT COUNT(*) FROM (
            SELECT loan_id, COUNT(*) AS cnt
            FROM raw_fintrust.loans GROUP BY loan_id HAVING cnt > 1
        )
        """))

    # L3: FK customer_id existe
    checks.append(run_check(conn, "fk_customer_existe", "loans",
        """
        SELECT COUNT(*) FROM raw_fintrust.loans l
        WHERE l.customer_id NOT IN (SELECT customer_id FROM raw_fintrust.customers)
        """))

    # L4: Monto positivo
    checks.append(run_check(conn, "monto_positivo", "loans",
        "SELECT COUNT(*) FROM raw_fintrust.loans WHERE principal_amount IS NULL OR principal_amount <= 0"))

    # L5: Tasa anual en rango razonable (0 a 100%)
    checks.append(run_check(conn, "tasa_en_rango", "loans",
        "SELECT COUNT(*) FROM raw_fintrust.loans WHERE annual_rate IS NULL OR annual_rate <= 0 OR annual_rate > 1"))

    # L6: Estado de crédito válido
    checks.append(run_check(conn, "status_valido", "loans",
        "SELECT COUNT(*) FROM raw_fintrust.loans WHERE UPPER(loan_status) NOT IN ('ACTIVE','CLOSED','DEFAULT')"))

    # L7: Plazo > 0
    checks.append(run_check(conn, "plazo_positivo", "loans",
        "SELECT COUNT(*) FROM raw_fintrust.loans WHERE term_months IS NULL OR term_months <= 0"))

    return checks


def validate_installments(conn) -> list:
    checks = []

    # I1: PK no nula
    checks.append(run_check(conn, "pk_no_nula", "installments",
        "SELECT COUNT(*) FROM raw_fintrust.installments WHERE installment_id IS NULL OR TRIM(installment_id)=''"))

    # I2: PK única
    checks.append(run_check(conn, "pk_unica", "installments",
        """
        SELECT COUNT(*) FROM (
            SELECT installment_id, COUNT(*) AS cnt
            FROM raw_fintrust.installments GROUP BY installment_id HAVING cnt > 1
        )
        """))

    # I3: FK loan_id existe
    checks.append(run_check(conn, "fk_loan_existe", "installments",
        """
        SELECT COUNT(*) FROM raw_fintrust.installments i
        WHERE i.loan_id NOT IN (SELECT loan_id FROM raw_fintrust.loans)
        """))

    # I4: Estado válido
    checks.append(run_check(conn, "status_valido", "installments",
        """
        SELECT COUNT(*) FROM raw_fintrust.installments
        WHERE UPPER(installment_status) NOT IN ('PAID','DUE','LATE','PARTIAL')
        """))

    # I5: Cuota outlier (número 99) - registrar como warning
    checks.append(run_check(conn, "cuota_numero_outlier", "installments",
        "SELECT COUNT(*) FROM raw_fintrust.installments WHERE installment_number = 99",
        threshold=1))  # Se permite hasta 1 (el conocido I135) como warning

    # I6: Valores de cuota no negativos
    checks.append(run_check(conn, "montos_no_negativos", "installments",
        """
        SELECT COUNT(*) FROM raw_fintrust.installments
        WHERE principal_due < 0 OR interest_due < 0
        """))

    # I7: Crédito sin cuotas asociadas
    checks.append(run_check(conn, "creditos_sin_cuotas", "loans",
        """
        SELECT COUNT(*) FROM raw_fintrust.loans l
        WHERE l.loan_status IN ('ACTIVE','DEFAULT')
          AND l.loan_id NOT IN (SELECT DISTINCT loan_id FROM raw_fintrust.installments)
        """))

    return checks


def validate_payments(conn) -> list:
    checks = []

    # P1: PK no nula
    checks.append(run_check(conn, "pk_no_nula", "payments",
        "SELECT COUNT(*) FROM raw_fintrust.payments WHERE payment_id IS NULL OR TRIM(payment_id)=''"))

    # P2: PK única
    checks.append(run_check(conn, "pk_unica", "payments",
        """
        SELECT COUNT(*) FROM (
            SELECT payment_id, COUNT(*) AS cnt
            FROM raw_fintrust.payments GROUP BY payment_id HAVING cnt > 1
        )
        """))

    # P3: FK loan_id existe
    checks.append(run_check(conn, "fk_loan_existe", "payments",
        """
        SELECT COUNT(*) FROM raw_fintrust.payments p
        WHERE p.loan_id NOT IN (SELECT loan_id FROM raw_fintrust.loans)
        """))

    # P4: installment_id huérfano (FK blanda)
    checks.append(run_check(conn, "installment_huerfano", "payments",
        """
        SELECT COUNT(*) FROM raw_fintrust.payments p
        WHERE p.installment_id NOT IN (SELECT installment_id FROM raw_fintrust.installments)
        """,
        threshold=1))   # P101 (I999) conocido como warning

    # P5: Monto = 0 o negativo
    checks.append(run_check(conn, "monto_invalido", "payments",
        "SELECT COUNT(*) FROM raw_fintrust.payments WHERE payment_amount IS NULL OR payment_amount <= 0",
        threshold=1))   # P106 = 0 conocido

    # P6: Canal NULL
    checks.append(run_check(conn, "canal_nulo", "payments",
        "SELECT COUNT(*) FROM raw_fintrust.payments WHERE payment_channel IS NULL",
        threshold=1))   # P102 conocido

    # P7: Status inválido
    checks.append(run_check(conn, "status_valido", "payments",
        """
        SELECT COUNT(*) FROM raw_fintrust.payments
        WHERE UPPER(payment_status) NOT IN ('CONFIRMED','REVERSED','PENDING')
        """))

    # P8: Pagos REVERSED y PENDING (informativo)
    checks.append(run_check(conn, "pagos_no_confirmados", "payments",
        """
        SELECT COUNT(*) FROM raw_fintrust.payments
        WHERE UPPER(payment_status) IN ('REVERSED','PENDING')
        """,
        threshold=5))   # Se esperan algunos, threshold razonable

    # P9: Pagos al mismo crédito e installment el mismo día (posible duplicado)
    checks.append(run_check(conn, "posible_duplicado", "payments",
        """
        SELECT COUNT(*) FROM (
            SELECT loan_id, installment_id, payment_date, COUNT(*) AS cnt
            FROM raw_fintrust.payments
            WHERE UPPER(payment_status) = 'CONFIRMED'
            GROUP BY loan_id, installment_id, payment_date
            HAVING cnt > 1
        )
        """,
        threshold=2))   # P104/P042 sobre L014/I046

    return checks


# =============================================================================
# VALIDACIONES CRUZADAS
# =============================================================================

def validate_cross_table(conn) -> list:
    checks = []

    # X1: Recaudo total no supera monto desembolsado por crédito
    checks.append(run_check(conn, "recaudo_no_supera_capital", "cross",
        """
        SELECT COUNT(*) FROM (
            SELECT
                l.loan_id,
                l.principal_amount,
                COALESCE(SUM(p.payment_amount), 0) AS total_recaudado
            FROM raw_fintrust.loans l
            LEFT JOIN raw_fintrust.payments p
                ON l.loan_id = p.loan_id
               AND UPPER(p.payment_status) = 'CONFIRMED'
               AND p.payment_amount > 0
            GROUP BY l.loan_id, l.principal_amount
            HAVING total_recaudado > l.principal_amount * 1.5  -- margen de 50% por intereses
        )
        """))

    # X2: Cuotas de crédito CLOSED deben estar en PAID
    checks.append(run_check(conn, "cuotas_closed_no_pagadas", "cross",
        """
        SELECT COUNT(*) FROM raw_fintrust.installments i
        JOIN raw_fintrust.loans l ON i.loan_id = l.loan_id
        WHERE UPPER(l.loan_status) = 'CLOSED'
          AND UPPER(i.installment_status) NOT IN ('PAID')
          AND i.installment_number != 99
        """,
        threshold=2))  # Algunos pueden tener cuotas futuras aún DUE

    return checks


# =============================================================================
# RUNNER PRINCIPAL
# =============================================================================

def run_all_validations(conn: duckdb.DuckDBPyConnection) -> dict:
    """
    Ejecuta todas las validaciones y retorna un dict con resultados.
    Llamado desde pipeline.py o standalone.
    """
    log.info("Iniciando validaciones de calidad de datos...")

    all_checks = []
    all_checks.extend(validate_customers(conn))
    all_checks.extend(validate_loans(conn))
    all_checks.extend(validate_installments(conn))
    all_checks.extend(validate_payments(conn))
    all_checks.extend(validate_cross_table(conn))

    passed = sum(1 for c in all_checks if c.passed)
    failed = len(all_checks) - passed

    log.info(f"\n  Resultado: {passed}/{len(all_checks)} validaciones pasaron")
    if failed > 0:
        log.warning(f"  ⚠ {failed} validaciones con observaciones:")

    results = {}
    for check in all_checks:
        key = f"{check.table}.{check.name}"
        results[key] = {
            "passed": check.passed,
            "count": check.count,
            "detail": check.detail
        }
        log.info(f"    {check}")

    # Guardar resultado en archivo
    output_path = Path(__file__).parent.parent / "docs" / "evidencia-calidad-datos.md"
    _write_evidence_report(all_checks, output_path)

    return results


def _write_evidence_report(checks: list, output_path: Path) -> None:
    """Genera el documento de evidencia de calidad de datos."""
    lines = [
        "# Evidencia de Validaciones de Calidad de Datos",
        "",
        f"**Fecha de ejecución:** {datetime.now():%Y-%m-%d %H:%M:%S}",
        "",
        "## Resumen",
        "",
        f"| Total checks | Pasaron | Con observaciones |",
        f"|---|---|---|",
    ]

    passed = sum(1 for c in checks if c.passed)
    failed = len(checks) - passed
    lines.append(f"| {len(checks)} | {passed} | {failed} |")
    lines.append("")
    lines.append("## Detalle por Tabla")
    lines.append("")
    lines.append("| Tabla | Validación | Estado | Registros afectados | Detalle |")
    lines.append("|---|---|---|---|---|")

    for check in checks:
        status = "✅ PASS" if check.passed else "⚠️ WARN"
        lines.append(
            f"| {check.table} | {check.name} | {status} | {check.count} | {check.detail} |"
        )

    lines.append("")
    lines.append("## Casos de Calidad Documentados")
    lines.append("")
    lines.append("""
| ID | Tabla | Tipo | Descripción | Acción en Staging |
|---|---|---|---|---|
| P101 | payments | FK huérfana | Referencia I999 que no existe en installments | Excluido del análisis de cuotas, cuenta para recaudo total |
| P102 | payments | Canal NULL | payment_channel = NULL | Reemplazado por 'UNKNOWN' |
| P103 | payments | REVERSED | Pago revertido | Excluido del recaudo efectivo |
| P104 | payments | Posible duplicado | Mismo loan+installment+fecha que P042 | Mantenido con flag; investigar |
| P105 | payments | PENDING | Pago no confirmado | Excluido del recaudo efectivo |
| P106 | payments | Monto = 0 | payment_amount = 0 | Excluido como inválido |
| I135 | installments | Outlier | installment_number = 99 en L003 | Excluido de cálculos de mora |
| P107 | payments | FK a cuota fantasma | Pago aplicado a I135 (cuota #99) | Excluido del análisis de cuotas |
""")

    output_path.parent.mkdir(exist_ok=True)
    output_path.write_text("\n".join(lines), encoding="utf-8")
    log.info(f"  ✓ Evidencia de calidad guardada en: {output_path}")


# =============================================================================
# MAIN (ejecución standalone)
# =============================================================================

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[logging.StreamHandler(sys.stdout)]
    )

    conn = duckdb.connect(str(DB_PATH))
    try:
        results = run_all_validations(conn)
        failed = sum(1 for v in results.values() if not v["passed"])
        if failed > 0:
            log.warning(f"Pipeline completado con {failed} observaciones de calidad")
        else:
            log.info("Todas las validaciones pasaron ✓")
    finally:
        conn.close()
