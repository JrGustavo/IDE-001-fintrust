-- =============================================================================
-- 02-staging/stg_installments.sql
-- Staging de Cuotas: limpieza, exclusión de outliers, cálculo de mora
-- =============================================================================

CREATE OR REPLACE TABLE staging_fintrust.stg_installments AS

WITH source AS (
    SELECT * FROM raw_fintrust.installments
),

cleaned AS (
    SELECT
        TRIM(installment_id)                        AS installment_id,
        TRIM(loan_id)                               AS loan_id,
        installment_number,
        due_date,
        principal_due,
        interest_due,
        COALESCE(principal_due, 0)
            + COALESCE(interest_due, 0)             AS total_due,
        UPPER(TRIM(installment_status))             AS installment_status,

        -- Días de atraso: solo para cuotas vencidas y no pagadas
        CASE
            WHEN UPPER(TRIM(installment_status)) NOT IN ('PAID')
             AND due_date < CURRENT_DATE
            THEN CAST(CURRENT_DATE - due_date AS INTEGER)
            ELSE 0
        END                                         AS dias_atraso,

        -- Indicador de mora: cuota vencida no pagada
        CASE
            WHEN UPPER(TRIM(installment_status)) IN ('LATE', 'PARTIAL')
              OR (UPPER(TRIM(installment_status)) = 'DUE' AND due_date < CURRENT_DATE)
            THEN TRUE
            ELSE FALSE
        END                                         AS en_mora,

        -- Bucket de mora (días de atraso)
        CASE
            WHEN UPPER(TRIM(installment_status)) = 'PAID' THEN 'Al dia'
            WHEN CAST(CURRENT_DATE - due_date AS INTEGER) BETWEEN 1 AND 30 THEN '1-30 dias'
            WHEN CAST(CURRENT_DATE - due_date AS INTEGER) BETWEEN 31 AND 60 THEN '31-60 dias'
            WHEN CAST(CURRENT_DATE - due_date AS INTEGER) BETWEEN 61 AND 90 THEN '61-90 dias'
            WHEN CAST(CURRENT_DATE - due_date AS INTEGER) > 90 THEN '+90 dias'
            ELSE 'Por vencer'
        END                                         AS bucket_mora,

        -- Flags de calidad
        CASE
            WHEN installment_id IS NULL OR TRIM(installment_id) = '' THEN TRUE ELSE FALSE
        END                                         AS _flag_sin_id,

        CASE
            WHEN installment_number = 99 THEN TRUE ELSE FALSE
        END                                         AS _flag_cuota_outlier,
        -- ⚠ Supuesto: installment_number=99 es un error de datos (I135/L003)

        CASE
            WHEN loan_id IS NULL OR TRIM(loan_id) = '' THEN TRUE ELSE FALSE
        END                                         AS _flag_sin_credito,

        CASE
            WHEN UPPER(TRIM(installment_status)) NOT IN ('PAID','DUE','LATE','PARTIAL') THEN TRUE ELSE FALSE
        END                                         AS _flag_status_invalido,

        CURRENT_TIMESTAMP                           AS _staged_at

    FROM source
),

valid AS (
    SELECT *
    FROM cleaned
    WHERE _flag_sin_id = FALSE
      AND _flag_sin_credito = FALSE
      AND _flag_status_invalido = FALSE
      AND _flag_cuota_outlier = FALSE  -- Excluir cuota fantasma #99
)

SELECT
    installment_id,
    loan_id,
    installment_number,
    due_date,
    principal_due,
    interest_due,
    total_due,
    installment_status,
    dias_atraso,
    en_mora,
    bucket_mora,
    _staged_at
FROM valid;
