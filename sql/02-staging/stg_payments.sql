-- =============================================================================
-- 02-staging/stg_payments.sql
-- Staging de Pagos: limpieza, normalización de canal, exclusión de inválidos
-- Implementa lógica de carga incremental basada en loaded_at watermark
-- =============================================================================

CREATE OR REPLACE TABLE staging_fintrust.stg_payments AS

WITH source AS (
    -- En producción BigQuery:
    -- DECLARE watermark TIMESTAMP DEFAULT (
    --   SELECT COALESCE(MAX(_loaded_at_raw), TIMESTAMP('2000-01-01'))
    --   FROM staging_fintrust.stg_payments
    -- );
    -- WHERE loaded_at > watermark
    --
    -- En DuckDB local, procesamos todo el set de muestra:
    SELECT * FROM raw_fintrust.payments
),

cleaned AS (
    SELECT
        TRIM(payment_id)                            AS payment_id,
        TRIM(loan_id)                               AS loan_id,
        TRIM(installment_id)                        AS installment_id,
        payment_date,
        payment_amount,

        -- Normalización de canal: NULL → 'UNKNOWN'
        COALESCE(TRIM(payment_channel), 'UNKNOWN')  AS payment_channel,
        -- Supuesto: P102 tiene canal NULL; se asigna 'UNKNOWN' para no perder el pago

        UPPER(TRIM(payment_status))                 AS payment_status,
        loaded_at,

        -- Flags de calidad de datos
        CASE
            WHEN payment_id IS NULL OR TRIM(payment_id) = '' THEN TRUE ELSE FALSE
        END                                         AS _flag_sin_id,

        CASE
            WHEN payment_amount IS NULL OR payment_amount <= 0 THEN TRUE ELSE FALSE
        END                                         AS _flag_monto_invalido,
        -- ⚠ P106 tiene payment_amount = 0: se excluye

        CASE
            WHEN UPPER(TRIM(payment_status)) NOT IN ('CONFIRMED','REVERSED','PENDING') THEN TRUE ELSE FALSE
        END                                         AS _flag_status_invalido,

        CASE
            WHEN UPPER(TRIM(payment_status)) = 'REVERSED' THEN TRUE ELSE FALSE
        END                                         AS _flag_reversed,
        -- ⚠ P103 REVERSED: se excluye del recaudo efectivo

        CASE
            WHEN UPPER(TRIM(payment_status)) = 'PENDING' THEN TRUE ELSE FALSE
        END                                         AS _flag_pending,
        -- ⚠ P105 PENDING: no confirmado, no cuenta como recaudo

        -- Pago huérfano: installment_id no existe en installments
        -- (se resuelve con LEFT JOIN posterior, aquí se marca el flag)
        CASE
            WHEN TRIM(installment_id) NOT IN (
                SELECT installment_id FROM raw_fintrust.installments
            ) THEN TRUE ELSE FALSE
        END                                         AS _flag_installment_huerfano,
        -- ⚠ P101 referencia I999 que no existe

        loaded_at                                   AS _loaded_at_raw,
        CURRENT_TIMESTAMP                           AS _staged_at

    FROM source
),

-- Solo pagos CONFIRMED con monto > 0 son recaudo efectivo
valid AS (
    SELECT *
    FROM cleaned
    WHERE _flag_sin_id = FALSE
      AND _flag_monto_invalido = FALSE
      AND _flag_status_invalido = FALSE
      AND _flag_reversed = FALSE
      AND _flag_pending = FALSE
)

SELECT
    payment_id,
    loan_id,
    installment_id,
    payment_date,
    payment_amount,
    payment_channel,
    payment_status,
    _flag_installment_huerfano,     -- Mantener para auditoría
    _loaded_at_raw,
    _staged_at
FROM valid;
