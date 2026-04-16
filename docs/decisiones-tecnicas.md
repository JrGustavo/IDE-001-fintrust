# Decisiones Técnicas, Supuestos y Riesgos

## 1. Motor SQL: DuckDB como simulación de BigQuery

### Decisión
Se usa **DuckDB** en lugar de BigQuery real.

### Justificación
- DuckDB es un motor OLAP columnar embebido, diseñado exactamente para análisis del tipo que pide el caso.
- Su SQL es compatible en >95% con BigQuery Standard SQL: soporta `WITH`, `WINDOW FUNCTIONS`, `QUALIFY`, `DATE_TRUNC`, `DATE_DIFF`, `CURRENT_DATE`, particiones, etc.
- Permite ejecutar el pipeline completo sin credenciales GCP, sin costos y de forma reproducible.
- La migración a BigQuery real es mecánica: cambiar la conexión en `pipeline.py` a `google-cloud-bigquery` y ajustar tipos (`STRING` → `STRING`, `INT64` → `INT64`, `NUMERIC` → `NUMERIC`, `TIMESTAMP` → `TIMESTAMP`).

### Diferencias menores a ajustar en BigQuery real
| DuckDB | BigQuery |
|--------|----------|
| `CREATE SCHEMA` | `CREATE SCHEMA IF NOT EXISTS project.dataset` |
| `CREATE OR REPLACE VIEW` | igual |
| `CURRENT_TIMESTAMP` | `CURRENT_TIMESTAMP()` |
| `strftime(col, '%Y-%m')` | `FORMAT_DATE('%Y-%m', col)` |
| `EPOCH` / interval | `DATE_DIFF(date1, date2, DAY)` |

---

## 2. Arquitectura en capas (Medallion)

Se implementó una arquitectura de **3 capas**:

### RAW (`raw_fintrust`)
- Datos exactamente como llegan de la fuente operativa.
- Sin transformaciones ni validaciones.
- Solo se agregan metadatos de carga (`_loaded_at`).
- **Supuesto:** Las fuentes entregan archivos CSV/JSON diariamente a un bucket GCS.

### Staging (`staging_fintrust`)
- Limpieza y estandarización de tipos.
- Normalización de strings (TRIM, UPPER/LOWER donde aplica).
- Aplicación de reglas de negocio básicas.
- Exclusión de registros inválidos (documentados).
- Adición de columnas derivadas (`dias_atraso`, `cohort_mes`, etc.).

### Analytics (`analytics_fintrust`)
- Data Mart (`dm_cartera_diaria`) con métricas consolidadas por crédito.
- Vistas (`vw_*`) optimizadas para consumo directo por BI.
- Todas las métricas calculadas aquí, el BI solo visualiza.

---

## 3. Supuestos de negocio aplicados

### Pagos
- Solo se procesan pagos con `payment_status = 'CONFIRMED'`. Los `PENDING` y `REVERSED` se excluyen del recaudo efectivo.
- `payment_amount = 0` se considera registro inválido (encontrado en P106).
- `payment_channel = NULL` se reemplaza por `'UNKNOWN'` (encontrado en P102).
- Pagos con `installment_id` que no existe en `installments` se marcan como **huérfanos** y se excluyen del análisis de cuotas, pero sí cuentan para recaudo total del crédito (e.g., P101 referencia I999 inexistente).

### Cuotas
- `installment_number = 99` es un outlier (I135 en L003). Se marca como cuota fantasma/error y se excluye del análisis de mora.
- Los estados válidos son: `PAID`, `DUE`, `LATE`, `PARTIAL`.
- Una cuota está en mora si `installment_status IN ('LATE', 'PARTIAL')` **y** `due_date < CURRENT_DATE`.
- `dias_atraso` se calcula como `CURRENT_DATE - due_date` solo para cuotas con `due_date < CURRENT_DATE` y status no `PAID`.

### Créditos
- `loan_status = 'DEFAULT'` se trata como cartera en mora severa (>90 días implícito).
- `loan_status = 'CLOSED'` excluye el crédito de cálculos de cartera vigente.
- El `saldo_pendiente` por crédito = suma de `(principal_due + interest_due)` de cuotas no `PAID`.

### Clientes
- `city` y `segment` se normalizan a TRIM + título (e.g., `'Bogota '` → `'Bogota'`).
- Se asume un cliente por `customer_id` (no hay duplicados en el set de muestra).

### Cohortes
- La cohorte de originación se define como `FORMAT('%Y-%m', origination_date)` del crédito (año-mes de desembolso).

---

## 4. Estrategia de Incrementalidad

### Pagos (tabla con mayor frecuencia de actualización)
- Campo watermark: `loaded_at TIMESTAMP`.
- En cada ejecución, el pipeline lee el `MAX(loaded_at)` ya procesado en staging y solo procesa registros con `loaded_at > watermark`.
- Esto evita reprocesar el historial completo y es O(nuevos registros).

### Otras tablas (customers, loans, installments)
- Estrategia **full refresh con deduplicación**: se trunca y recarga daily.
- Justificación: el volumen es pequeño (35/45/135 registros) y los cambios de estado (`loan_status`, `installment_status`) requieren actualizar registros existentes, no solo insertar nuevos. Un merge por PK sería equivalente pero más complejo para el alcance del caso.

### En producción BigQuery
- Para `payments`: `MERGE INTO staging WHERE payment_id NOT IN (SELECT payment_id FROM staging)` o usar `loaded_at` watermark con tabla de control.
- Para `loans/installments`: `MERGE INTO staging ON loan_id/installment_id WHEN MATCHED THEN UPDATE WHEN NOT MATCHED THEN INSERT`.

---

## 5. Manejo de Errores y Monitoreo

### Implementado
- Validaciones de calidad antes de staging (ver `validations.py`).
- Logging estructurado con timestamps en cada paso del pipeline.
- El pipeline falla con código de salida != 0 si hay errores críticos.

### En producción GCP
- **Cloud Logging**: capturar logs del pipeline en Cloud Run / Composer.
- **Cloud Monitoring**: alertas si el pipeline no corre en ventana esperada.
- **Dataplex Data Quality**: validaciones declarativas sobre tablas BigQuery.
- **Dead Letter Queue**: pagos con errores van a tabla `raw_fintrust.payments_errors` para revisión manual.
- **Alertas de negocio**: si recaudo del día = 0 o desembolso = 0, alerta automática al equipo financiero.

---

## 6. Riesgos Conocidos

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| Pagos duplicados (mismo pago registrado dos veces) | Media | Alto | Deduplicar por `payment_id` en staging |
| Cuotas sin crédito padre (FK roto) | Baja | Medio | Validación de integridad referencial en staging |
| Cambio de `loan_status` retroactivo | Media | Alto | Registrar historial de estados en tabla de auditoría |
| Crédito activo sin cuotas generadas | Baja | Medio | Alerta si loan tiene 0 cuotas asociadas |
| Pagos en `payment_channel` no estándar | Alta | Bajo | Normalización en staging + tabla maestra de canales |
| `installment_number = 99` (datos sucios) | Confirmado | Medio | Exclusión explícita con flag en staging |

---

## 7. Escalabilidad a producción GCP

```
GCS Bucket (landing)
    │
    ▼
Cloud Run Job (pipeline.py)  ←── Cloud Scheduler (diario 6am)
    │
    ├── raw_fintrust (BigQuery dataset, particionado por fecha)
    ├── staging_fintrust (BigQuery dataset)
    └── analytics_fintrust (BigQuery dataset, tablas materializadas)
                │
                ▼
        Looker / Looker Studio / Power BI (DirectQuery)
```

- Tablas BigQuery particionadas por `origination_date` / `payment_date` para optimizar costos de query.
- Clustering por `city`, `segment` en la tabla de cartera para acelerar filtros del dashboard.
- Scheduled Queries de BigQuery como alternativa a Cloud Run para las transformaciones SQL puras.
