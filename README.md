# 🏦 IDE-001 — FinTrust Data Platform

<div align="center">

![Python](https://img.shields.io/badge/Python-3.11-3776AB?style=for-the-badge&logo=python&logoColor=white)
![DuckDB](https://img.shields.io/badge/DuckDB-0.10-FFF000?style=for-the-badge&logo=duckdb&logoColor=black)
![SQL](https://img.shields.io/badge/SQL-BigQuery_Compatible-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)
![BigQuery](https://img.shields.io/badge/GCP-BigQuery-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)
![Status](https://img.shields.io/badge/Pipeline-✓_Passing-28a745?style=for-the-badge)

**Solución analítica de punta a punta para FinTrust — Caso Práctico Ingeniero de Datos**

*Ingesta · Transformación · Calidad de Datos · Data Mart · BI Ready*

</div>

---

## 📋 Contenido

- [Contexto](#-contexto)
- [Arquitectura](#-arquitectura)
- [Estructura del Repositorio](#-estructura-del-repositorio)
- [Stack Tecnológico](#-stack-tecnológico)
- [Instalación y Ejecución](#-instalación-y-ejecución)
- [Preguntas de Negocio](#-preguntas-de-negocio)
- [Calidad de Datos](#-calidad-de-datos)
- [Incrementalidad](#-incrementalidad)
- [Bonus LLM](#-bonus-llm)
- [Decisiones Técnicas](#-decisiones-técnicas)

---

## 🎯 Contexto

**FinTrust** es una fintech de crédito de consumo que otorga microcréditos a clientes de nómina y canales digitales. El equipo financiero tardaba **1-2 días** en consolidar indicadores diarios de originación, recaudo y mora, descargando reportes manualmente y corrigiendo inconsistencias en hojas de cálculo.

Esta solución automatiza el pipeline completo de datos, desde las fuentes operativas hasta una capa analítica lista para consumo en **Power BI, Tableau o Looker**.

| Fuente | Descripción | Registros |
|--------|-------------|-----------|
| `raw_fintrust.customers` | Clientes de FinTrust | 35 |
| `raw_fintrust.loans` | Créditos otorgados | 45 |
| `raw_fintrust.installments` | Cuotas programadas | 135 |
| `raw_fintrust.payments` | Pagos recibidos | 107 |

---

## 🏗 Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                    FUENTES OPERATIVAS                        │
│              CSV / API / Sistema transaccional               │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   CAPA RAW  (raw_fintrust)                   │
│   Datos exactamente como llegan · Sin transformaciones       │
│   customers · loans · installments · payments                │
└──────────────────────────┬──────────────────────────────────┘
                           │  ETL/ELT — Python + SQL
                           ▼
┌─────────────────────────────────────────────────────────────┐
│               CAPA STAGING  (staging_fintrust)               │
│   Limpieza · Estandarización · Validación · Enriquecimiento  │
│   stg_customers · stg_loans · stg_installments · stg_payments│
└──────────────────────────┬──────────────────────────────────┘
                           │  Transformaciones analíticas
                           ▼
┌─────────────────────────────────────────────────────────────┐
│             CAPA ANALYTICS  (analytics_fintrust)             │
│                                                              │
│   dm_cartera_diaria     ← Data Mart principal               │
│   vw_desembolso_diario  ← Originación por día/ciudad        │
│   vw_recaudo_diario     ← Recaudo con desglose de mora      │
│   vw_cartera_por_cohorte← Análisis de cohortes              │
│   vw_dataset_bi         ← Vista maestra para BI             │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
              Power BI · Tableau · Looker
```

---

## 📁 Estructura del Repositorio

```
IDE-001-fintrust/
│
├── 📄 README.md                          # Este archivo
├── 📄 .gitignore
│
├── 📁 docs/
│   ├── decisiones-tecnicas.md           # Supuestos, diseño y riesgos
│   └── evidencia-calidad-datos.md       # Validaciones y resultados (auto-generado)
│
├── 📁 sql/
│   ├── 01-raw/
│   │   └── create_raw_tables.sql        # DDL + datos de muestra
│   ├── 02-staging/
│   │   ├── stg_customers.sql
│   │   ├── stg_loans.sql
│   │   ├── stg_installments.sql
│   │   └── stg_payments.sql
│   ├── 03-analytics/
│   │   ├── dm_cartera_diaria.sql        # Data Mart principal
│   │   └── vw_dataset_bi.sql            # Vista maestra BI
│   └── 04-queries-negocio/
│       ├── q01_desembolso_diario.sql
│       ├── q02_recaudo_diario.sql
│       ├── q03_cartera_por_cohorte.sql
│       ├── q04_top_atraso.sql
│       └── q05_dataset_bi.sql
│
├── 📁 python/
│   ├── pipeline.py                      # Orquestador ETL principal
│   ├── validations.py                   # Módulo de calidad de datos
│   └── requirements.txt
│
└── 📁 bonus/
    └── llm_proposal.md                  # Propuesta de uso de LLMs
```

---

## 🛠 Stack Tecnológico

| Componente | Tecnología | Equivalente GCP |
|------------|-----------|-----------------|
| Data Warehouse | **DuckDB** (simulación local) | BigQuery |
| Orquestación ETL | **Python 3.11** | Cloud Run / Cloud Composer |
| Transformaciones | **SQL estándar** | BigQuery SQL |
| Calidad de datos | **Python + SQL** | Dataplex |
| Visualización | Compatible con | Power BI · Tableau · Looker |
| Incrementalidad | **Watermark `loaded_at`** | BigQuery MERGE |

> **¿Por qué DuckDB?** Es un motor OLAP columnar embebido, compatible en >95% con BigQuery Standard SQL (soporta `WITH`, window functions, `DATE_TRUNC`, `QUALIFY`, particiones). La migración a BigQuery real es directa: cambiar la conexión y ajustar 4 funciones de fecha. Ver [decisiones-tecnicas.md](docs/decisiones-tecnicas.md).

---

## 🚀 Instalación y Ejecución

### 1. Clonar el repositorio

```bash
git clone https://github.com/JrGustavo/IDE-001-fintrust.git
cd IDE-001-fintrust
```

### 2. Crear entorno virtual e instalar dependencias

```bash
python -m venv venv
source venv/bin/activate        # Mac/Linux
# venv\Scripts\activate         # Windows

pip install -r python/requirements.txt
```

### 3. Ejecutar el pipeline completo

```bash
cd python
python pipeline.py
```

**Salida esperada:**

```
🚀 FINTRUST DATA PIPELINE - INICIO
============================================================
PASO 1-2: Carga de datos RAW
  ✓ create_raw_tables.sql completado
    raw_fintrust.customers:    35 registros
    raw_fintrust.loans:        45 registros
    raw_fintrust.installments: 135 registros
    raw_fintrust.payments:     107 registros

PASO 3: Validaciones de Calidad de Datos
  Resultado: 30/30 validaciones pasaron ✓

PASO 4: Transformaciones Staging
  ✓ stg_customers.sql     → 35 registros
  ✓ stg_loans.sql         → 45 registros
  ✓ stg_installments.sql  → 134 registros
  ✓ stg_payments.sql      → 104 registros

PASO 5-6: Data Mart y Vistas Analíticas
  ✓ dm_cartera_diaria: 42 créditos

PASO 7: Carga Incremental
  ✓ Watermark guardado

PASO 8: KPIs de Cartera
  Créditos activos:  42
  Cartera total:     $854,500,000
  Total mora:        $57,089,000
  Créditos en mora:  32

✅ Pipeline completado — Tiempo total: 0.74s
```

### 4. Comandos adicionales

```bash
# Solo validaciones de calidad
python pipeline.py --validate-only

# Solo carga incremental de pagos
python pipeline.py --incremental

# Exportar dataset BI a CSV (para Power BI Desktop)
python pipeline.py --export-csv
```

---

## 📊 Preguntas de Negocio

Todas respondidas mediante vistas y queries SQL en `sql/04-queries-negocio/`:

### Q1 — Desembolso total por día, ciudad y segmento
```sql
SELECT fecha_desembolso, ciudad, segmento, num_creditos, total_desembolsado
FROM analytics_fintrust.vw_desembolso_diario
ORDER BY fecha_desembolso DESC, total_desembolsado DESC;
```

### Q2 — Recaudo diario total y aplicado a cuotas vencidas
```sql
SELECT fecha_recaudo, total_recaudado, recaudo_en_mora, pct_recaudo_mora
FROM analytics_fintrust.vw_recaudo_diario
ORDER BY fecha_recaudo DESC;
```

### Q3 — Cartera al día vs mora por cohorte de originación
```sql
SELECT cohort_mes, cartera_vigente, cartera_mora, pct_mora, clasificacion_cohorte
FROM analytics_fintrust.vw_cartera_por_cohorte
ORDER BY cohort_mes;
```

### Q4 — Top 10 créditos con mayor atraso
```sql
SELECT loan_id, nombre_cliente, saldo_mora, max_dias_atraso, bucket_mora
FROM analytics_fintrust.dm_cartera_diaria
WHERE en_mora = TRUE
ORDER BY max_dias_atraso DESC
LIMIT 10;
```

### Q5 — Dataset listo para BI
```sql
SELECT * FROM analytics_fintrust.vw_dataset_bi;
```

---

## ✅ Calidad de Datos

El módulo `validations.py` ejecuta **30 validaciones** organizadas por tabla:

| Categoría | Validaciones |
|-----------|-------------|
| **Completitud** | PKs no nulas en las 4 tablas |
| **Unicidad** | PKs únicas en las 4 tablas |
| **Integridad referencial** | FKs: loans→customers, installments→loans, payments→loans |
| **Validez de valores** | Segmentos, estados, tasas, montos en rango |
| **Consistencia cruzada** | Recaudo no supera capital, cuotas CLOSED pagadas |

**Casos de calidad documentados y tratados:**

| ID | Problema | Acción |
|----|----------|--------|
| P101 | `installment_id = I999` inexistente | Excluido del análisis de cuotas |
| P102 | `payment_channel = NULL` | Reemplazado por `'UNKNOWN'` |
| P103 | `payment_status = 'REVERSED'` | Excluido del recaudo efectivo |
| P105 | `payment_status = 'PENDING'` | Excluido del recaudo efectivo |
| P106 | `payment_amount = 0` | Excluido como inválido |
| I135 | `installment_number = 99` outlier | Excluido de cálculos de mora |

> El reporte completo se genera automáticamente en `docs/evidencia-calidad-datos.md` al ejecutar el pipeline.

---

## 🔄 Incrementalidad

La tabla `raw_fintrust.payments` incluye el campo `loaded_at TIMESTAMP` que actúa como **watermark** para carga incremental:

```
1ª ejecución:  procesa TODOS los pagos → guarda MAX(loaded_at) en watermark.json
2ª ejecución:  procesa solo pagos con loaded_at > watermark → reconstruye staging y data mart
```

**En BigQuery real:**
```sql
MERGE INTO staging_fintrust.stg_payments AS target
USING (SELECT * FROM raw_fintrust.payments WHERE loaded_at > @watermark) AS source
ON target.payment_id = source.payment_id
WHEN NOT MATCHED THEN INSERT (...)
WHEN MATCHED THEN UPDATE SET ...
```

---

## 🤖 Bonus LLM

Propuesta de **Text-to-SQL con contexto del schema** para permitir consultas en lenguaje natural sobre el data mart:

```
Analista: "¿Cuáles son las 3 ciudades con mayor cartera en mora?"
    ↓
Claude (LLM) genera SQL usando el schema del data mart
    ↓
BigQuery/DuckDB ejecuta la query
    ↓
Claude explica el resultado en lenguaje de negocio
```

Ver propuesta completa en [`bonus/llm_proposal.md`](bonus/llm_proposal.md).

---

## 📐 Decisiones Técnicas

Ver documento completo en [`docs/decisiones-tecnicas.md`](docs/decisiones-tecnicas.md).

**Resumen:**

- **DuckDB sobre BigQuery real:** reproducibilidad sin credenciales GCP, migración directa
- **Arquitectura Medallion (RAW → Staging → Analytics):** separación clara de responsabilidades
- **Full refresh en staging para loans/installments:** cambios de estado requieren actualizar registros existentes
- **Watermark incremental para payments:** es la tabla de mayor volumen y frecuencia de actualización
- **Exclusión explícita de datos sucios:** documentada con supuestos claros, no silenciosa

---

## 👤 Autor

**Gustavo Adolfo** · Candidato Ingeniero de Datos Semi-Senior  
Caso Práctico — Ceiba Software

> Este proyecto fue desarrollado con asistencia de Claude (Anthropic) para estructuración de documentación y revisión de lógica SQL. Todos los scripts, decisiones de arquitectura y lógica de negocio fueron diseñados y validados manualmente.
