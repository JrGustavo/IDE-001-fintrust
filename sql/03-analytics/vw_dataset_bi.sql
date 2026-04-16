-- =============================================================================
-- 03-analytics/vw_dataset_bi.sql
-- Vista maestra lista para conectar directamente a Power BI / Tableau / Looker
-- Contiene todas las dimensiones y métricas necesarias en una sola tabla plana
-- =============================================================================

CREATE OR REPLACE VIEW analytics_fintrust.vw_dataset_bi AS

SELECT
    -- =========================================================================
    -- DIMENSIONES TEMPORALES
    -- =========================================================================
    fecha_corte,
    fecha_originacion,
    cohort_mes,
    EXTRACT(YEAR FROM fecha_originacion)            AS anio_originacion,
    EXTRACT(MONTH FROM fecha_originacion)           AS mes_originacion,
    EXTRACT(QUARTER FROM fecha_originacion)         AS trimestre_originacion,

    -- =========================================================================
    -- DIMENSIONES DE NEGOCIO
    -- =========================================================================
    loan_id,
    customer_id,
    nombre_cliente,
    ciudad,
    segmento,
    tipo_producto,
    estado_credito,
    en_mora,
    bucket_mora,

    -- =========================================================================
    -- MÉTRICAS DE ORIGINACIÓN
    -- =========================================================================
    monto_desembolsado,
    tasa_anual,
    ROUND(tasa_anual * 100, 2)                      AS tasa_anual_pct,
    plazo_meses,
    ingreso_mensual_cliente,
    -- Ratio de endeudamiento: cuota teórica vs ingreso
    ROUND(
        (monto_desembolsado / plazo_meses)
        / NULLIF(ingreso_mensual_cliente, 0) * 100, 2
    )                                               AS ratio_endeudamiento_pct,

    -- =========================================================================
    -- MÉTRICAS DE CARTERA
    -- =========================================================================
    total_cuotas,
    cuotas_pagadas,
    cuotas_en_mora,
    cuotas_por_vencer,
    ROUND(cuotas_pagadas::FLOAT / NULLIF(total_cuotas, 0) * 100, 2)
                                                    AS pct_avance_pago,

    saldo_pendiente,
    saldo_mora,
    saldo_vigente,
    capital_recuperado_estimado,
    ROUND(
        capital_recuperado_estimado
        / NULLIF(monto_desembolsado, 0) * 100, 2
    )                                               AS pct_recuperacion,

    -- =========================================================================
    -- MÉTRICAS DE MORA
    -- =========================================================================
    max_dias_atraso,
    CASE
        WHEN max_dias_atraso = 0 THEN 0
        WHEN max_dias_atraso BETWEEN 1 AND 30 THEN 1
        WHEN max_dias_atraso BETWEEN 31 AND 60 THEN 2
        WHEN max_dias_atraso BETWEEN 61 AND 90 THEN 3
        ELSE 4
    END                                             AS bucket_mora_orden,
    -- (útil para ordenar correctamente en BI sin depender del texto)

    -- =========================================================================
    -- MÉTRICAS DE RECAUDO
    -- =========================================================================
    total_pagos_recibidos,
    total_recaudado,
    recaudo_en_mora,
    ultimo_pago_fecha,
    pct_mora_cubierta_por_recaudo,

    -- Días desde último pago (indicador de inactividad de pago)
    CASE
        WHEN ultimo_pago_fecha IS NOT NULL
        THEN CAST(CURRENT_DATE - ultimo_pago_fecha AS INTEGER)
        ELSE NULL
    END                                             AS dias_sin_pago

FROM analytics_fintrust.dm_cartera_diaria;

-- =============================================================================
-- NOTA PARA CONEXIÓN BI:
-- Power BI: Conector BigQuery → Seleccionar analytics_fintrust.vw_dataset_bi
-- Tableau: Conector BigQuery → Live Connection → analytics_fintrust.vw_dataset_bi
-- Looker: LookML model apuntando a analytics_fintrust como dataset
--
-- En DuckDB local: exportar a CSV con:
-- COPY (SELECT * FROM analytics_fintrust.vw_dataset_bi) TO 'dataset_bi.csv' (HEADER, DELIMITER ',');
-- =============================================================================
