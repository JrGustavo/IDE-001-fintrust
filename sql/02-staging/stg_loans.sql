-- =============================================================================
-- 02-staging/stg_loans.sql
-- Staging de Créditos: limpieza, enriquecimiento y validación
-- =============================================================================

CREATE OR REPLACE TABLE staging_fintrust.stg_loans AS

WITH source AS (
    SELECT * FROM raw_fintrust.loans
),

cleaned AS (
    SELECT
        TRIM(loan_id)                               AS loan_id,
        TRIM(customer_id)                           AS customer_id,
        origination_date,
        principal_amount,
        annual_rate,
        term_months,

        -- Estandarizar loan_status a mayúsculas
        UPPER(TRIM(loan_status))                    AS loan_status,

        -- Estandarizar product_type
        TRIM(product_type)                          AS product_type,

        -- Columnas derivadas de negocio
        -- Cohorte de originación: año-mes para análisis de comportamiento
        strftime(origination_date, '%Y-%m')         AS cohort_mes,
        -- BigQuery equivalente: FORMAT_DATE('%Y-%m', origination_date)

        -- Tasa mensual efectiva
        ROUND(annual_rate / 12, 6)                  AS monthly_rate,

        -- Cuota teórica mensual (fórmula francesa de amortización)
        ROUND(
            principal_amount
            * (annual_rate / 12)
            / (1 - POWER(1 + annual_rate / 12, -term_months)),
            0
        )                                           AS cuota_teorica,

        -- Flags de calidad
        CASE
            WHEN loan_id IS NULL OR TRIM(loan_id) = '' THEN TRUE ELSE FALSE
        END                                         AS _flag_sin_id,

        CASE
            WHEN customer_id IS NULL OR TRIM(customer_id) = '' THEN TRUE ELSE FALSE
        END                                         AS _flag_sin_cliente,

        CASE
            WHEN principal_amount IS NULL OR principal_amount <= 0 THEN TRUE ELSE FALSE
        END                                         AS _flag_monto_invalido,

        CASE
            WHEN annual_rate IS NULL OR annual_rate <= 0 OR annual_rate > 1 THEN TRUE ELSE FALSE
        END                                         AS _flag_tasa_invalida,

        CASE
            WHEN term_months IS NULL OR term_months <= 0 THEN TRUE ELSE FALSE
        END                                         AS _flag_plazo_invalido,

        CASE
            WHEN UPPER(TRIM(loan_status)) NOT IN ('ACTIVE','CLOSED','DEFAULT') THEN TRUE ELSE FALSE
        END                                         AS _flag_status_invalido,

        CURRENT_TIMESTAMP                           AS _staged_at

    FROM source
),

valid AS (
    SELECT *
    FROM cleaned
    WHERE _flag_sin_id = FALSE
      AND _flag_sin_cliente = FALSE
      AND _flag_monto_invalido = FALSE
      AND _flag_tasa_invalida = FALSE
      AND _flag_plazo_invalido = FALSE
      AND _flag_status_invalido = FALSE
)

SELECT
    loan_id,
    customer_id,
    origination_date,
    principal_amount,
    annual_rate,
    monthly_rate,
    term_months,
    loan_status,
    product_type,
    cohort_mes,
    cuota_teorica,
    _staged_at
FROM valid;
