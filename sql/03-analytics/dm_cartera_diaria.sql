-- =============================================================================
-- 03-analytics/dm_cartera_diaria.sql
-- Data Mart de Cartera: tabla analítica principal por crédito
-- Consolida estado actual de cada crédito con todas sus métricas
-- Lista para consumo directo desde Power BI / Tableau / Looker
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS analytics_fintrust;

CREATE OR REPLACE TABLE analytics_fintrust.dm_cartera_diaria AS

WITH

-- 1. Base: créditos activos y en default (excluir CLOSED)
loans AS (
    SELECT
        l.loan_id,
        l.customer_id,
        l.origination_date,
        l.principal_amount,
        l.annual_rate,
        l.monthly_rate,
        l.term_months,
        l.loan_status,
        l.product_type,
        l.cohort_mes,
        l.cuota_teorica,
        -- Dimensiones del cliente
        c.full_name,
        c.city,
        c.segment,
        c.monthly_income
    FROM staging_fintrust.stg_loans l
    LEFT JOIN staging_fintrust.stg_customers c
        ON l.customer_id = c.customer_id
    WHERE l.loan_status IN ('ACTIVE', 'DEFAULT')
),

-- 2. Métricas de cuotas por crédito
cuotas_agg AS (
    SELECT
        loan_id,
        COUNT(*)                                                AS total_cuotas,
        COUNT(CASE WHEN installment_status = 'PAID' THEN 1 END) AS cuotas_pagadas,
        COUNT(CASE WHEN en_mora = TRUE THEN 1 END)              AS cuotas_en_mora,
        COUNT(CASE WHEN installment_status = 'DUE'
                    AND due_date >= CURRENT_DATE THEN 1 END)    AS cuotas_por_vencer,

        -- Saldo pendiente = suma de cuotas no pagadas
        SUM(CASE WHEN installment_status != 'PAID'
                 THEN total_due ELSE 0 END)                     AS saldo_pendiente_total,

        -- Saldo en mora = cuotas LATE o PARTIAL vencidas
        SUM(CASE WHEN en_mora = TRUE
                 THEN total_due ELSE 0 END)                     AS saldo_en_mora,

        -- Saldo vigente = cuotas DUE no vencidas
        SUM(CASE WHEN installment_status IN ('DUE')
                  AND due_date >= CURRENT_DATE
                 THEN total_due ELSE 0 END)                     AS saldo_vigente,

        -- Máximo atraso en días
        MAX(dias_atraso)                                        AS max_dias_atraso,

        -- Cuota con mayor atraso
        MAX(CASE WHEN dias_atraso > 0 THEN installment_number END) AS num_cuota_mayor_atraso

    FROM staging_fintrust.stg_installments
    GROUP BY loan_id
),

-- 3. Recaudo total por crédito
pagos_agg AS (
    SELECT
        loan_id,
        COUNT(*)                        AS total_pagos,
        SUM(payment_amount)             AS total_recaudado,
        MAX(payment_date)               AS ultimo_pago_fecha,
        -- Recaudo aplicado a cuotas en mora
        SUM(CASE WHEN _flag_installment_huerfano = FALSE
                  AND installment_id IN (
                      SELECT installment_id
                      FROM staging_fintrust.stg_installments
                      WHERE en_mora = TRUE
                  )
                 THEN payment_amount ELSE 0 END) AS recaudo_aplicado_mora

    FROM staging_fintrust.stg_payments
    GROUP BY loan_id
),

-- 4. Consolidación final
cartera AS (
    SELECT
        -- Identificadores
        l.loan_id,
        l.customer_id,
        l.full_name                                     AS nombre_cliente,
        l.city                                          AS ciudad,
        l.segment                                       AS segmento,
        l.product_type                                  AS tipo_producto,

        -- Dimensiones del crédito
        l.origination_date                              AS fecha_originacion,
        l.cohort_mes,
        l.principal_amount                              AS monto_desembolsado,
        l.annual_rate                                   AS tasa_anual,
        l.term_months                                   AS plazo_meses,
        l.loan_status                                   AS estado_credito,
        l.monthly_income                                AS ingreso_mensual_cliente,

        -- Métricas de cuotas
        COALESCE(c.total_cuotas, 0)                     AS total_cuotas,
        COALESCE(c.cuotas_pagadas, 0)                   AS cuotas_pagadas,
        COALESCE(c.cuotas_en_mora, 0)                   AS cuotas_en_mora,
        COALESCE(c.cuotas_por_vencer, 0)                AS cuotas_por_vencer,

        -- Saldos
        COALESCE(c.saldo_pendiente_total, 0)            AS saldo_pendiente,
        COALESCE(c.saldo_en_mora, 0)                    AS saldo_mora,
        COALESCE(c.saldo_vigente, 0)                    AS saldo_vigente,

        -- Capital recuperado vs original
        l.principal_amount
            - COALESCE(c.saldo_pendiente_total, 0)      AS capital_recuperado_estimado,

        -- Mora
        COALESCE(c.max_dias_atraso, 0)                  AS max_dias_atraso,

        CASE
            WHEN COALESCE(c.max_dias_atraso, 0) = 0 THEN 'Al dia'
            WHEN COALESCE(c.max_dias_atraso, 0) BETWEEN 1 AND 30 THEN '1-30 dias'
            WHEN COALESCE(c.max_dias_atraso, 0) BETWEEN 31 AND 60 THEN '31-60 dias'
            WHEN COALESCE(c.max_dias_atraso, 0) BETWEEN 61 AND 90 THEN '61-90 dias'
            ELSE '+90 dias'
        END                                             AS bucket_mora,

        CASE
            WHEN l.loan_status = 'DEFAULT' THEN TRUE
            WHEN COALESCE(c.cuotas_en_mora, 0) > 0 THEN TRUE
            ELSE FALSE
        END                                             AS en_mora,

        -- Recaudo
        COALESCE(p.total_pagos, 0)                      AS total_pagos_recibidos,
        COALESCE(p.total_recaudado, 0)                  AS total_recaudado,
        COALESCE(p.recaudo_aplicado_mora, 0)            AS recaudo_en_mora,
        p.ultimo_pago_fecha,

        -- Ratio de cobertura de mora con recaudo
        CASE
            WHEN COALESCE(c.saldo_en_mora, 0) = 0 THEN NULL
            ELSE ROUND(
                COALESCE(p.recaudo_aplicado_mora, 0)
                / COALESCE(c.saldo_en_mora, 1) * 100, 2
            )
        END                                             AS pct_mora_cubierta_por_recaudo,

        -- Metadatos
        CURRENT_DATE                                    AS fecha_corte,
        CURRENT_TIMESTAMP                               AS _refreshed_at

    FROM loans l
    LEFT JOIN cuotas_agg c ON l.loan_id = c.loan_id
    LEFT JOIN pagos_agg p ON l.loan_id = p.loan_id
)

SELECT * FROM cartera;

-- =============================================================================
-- VISTAS ANALÍTICAS COMPLEMENTARIAS
-- =============================================================================

-- Vista: Desembolso diario por ciudad y segmento
CREATE OR REPLACE VIEW analytics_fintrust.vw_desembolso_diario AS
SELECT
    l.origination_date                              AS fecha_desembolso,
    c.city                                          AS ciudad,
    c.segment                                       AS segmento,
    l.product_type                                  AS tipo_producto,
    COUNT(l.loan_id)                                AS num_creditos,
    SUM(l.principal_amount)                         AS total_desembolsado,
    AVG(l.principal_amount)                         AS promedio_desembolso,
    MAX(l.principal_amount)                         AS max_desembolso,
    MIN(l.principal_amount)                         AS min_desembolso
FROM staging_fintrust.stg_loans l
LEFT JOIN staging_fintrust.stg_customers c
    ON l.customer_id = c.customer_id
GROUP BY
    l.origination_date,
    c.city,
    c.segment,
    l.product_type;


-- Vista: Recaudo diario con desagregación de mora
CREATE OR REPLACE VIEW analytics_fintrust.vw_recaudo_diario AS
WITH pagos_con_mora AS (
    SELECT
        p.payment_id,
        p.loan_id,
        p.payment_date,
        p.payment_amount,
        p.payment_channel,
        -- ¿Este pago fue aplicado a una cuota en mora?
        CASE
            WHEN i.en_mora = TRUE THEN TRUE ELSE FALSE
        END AS aplicado_a_mora,
        i.en_mora,
        i.installment_status
    FROM staging_fintrust.stg_payments p
    LEFT JOIN staging_fintrust.stg_installments i
        ON p.installment_id = i.installment_id
    WHERE p._flag_installment_huerfano = FALSE
)
SELECT
    payment_date                                    AS fecha_recaudo,
    COUNT(payment_id)                               AS num_pagos,
    SUM(payment_amount)                             AS total_recaudado,
    SUM(CASE WHEN aplicado_a_mora = TRUE
             THEN payment_amount ELSE 0 END)        AS recaudo_en_mora,
    SUM(CASE WHEN aplicado_a_mora = FALSE
             THEN payment_amount ELSE 0 END)        AS recaudo_al_dia,
    ROUND(
        SUM(CASE WHEN aplicado_a_mora = TRUE
                 THEN payment_amount ELSE 0 END)
        / NULLIF(SUM(payment_amount), 0) * 100, 2
    )                                               AS pct_recaudo_mora
FROM pagos_con_mora
GROUP BY payment_date;


-- Vista: Cartera por cohorte de originación
CREATE OR REPLACE VIEW analytics_fintrust.vw_cartera_por_cohorte AS
SELECT
    cohort_mes,
    COUNT(loan_id)                                  AS num_creditos,
    SUM(monto_desembolsado)                         AS total_desembolsado,
    SUM(saldo_vigente)                              AS cartera_vigente,
    SUM(saldo_mora)                                 AS cartera_mora,
    SUM(saldo_pendiente)                            AS cartera_total_pendiente,
    ROUND(
        SUM(saldo_mora)
        / NULLIF(SUM(saldo_pendiente), 0) * 100, 2
    )                                               AS pct_mora,
    MAX(max_dias_atraso)                            AS max_dias_atraso_cohorte,
    COUNT(CASE WHEN en_mora = TRUE THEN 1 END)      AS creditos_en_mora,
    ROUND(
        COUNT(CASE WHEN en_mora = TRUE THEN 1 END)::FLOAT
        / NULLIF(COUNT(loan_id), 0) * 100, 2
    )                                               AS pct_creditos_mora
FROM analytics_fintrust.dm_cartera_diaria
GROUP BY cohort_mes
ORDER BY cohort_mes;
