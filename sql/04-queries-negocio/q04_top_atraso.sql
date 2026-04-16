-- =============================================================================
-- q04_top_atraso.sql
-- Pregunta 4: Top 10 créditos con mayor atraso y saldo pendiente
-- =============================================================================

SELECT
    ROW_NUMBER() OVER (ORDER BY max_dias_atraso DESC, saldo_mora DESC) AS ranking,
    loan_id,
    nombre_cliente,
    ciudad,
    segmento,
    tipo_producto,
    estado_credito,
    monto_desembolsado,
    saldo_mora,
    saldo_pendiente,
    max_dias_atraso,
    bucket_mora,
    cuotas_en_mora,
    total_cuotas,
    ultimo_pago_fecha,
    -- Días sin pago
    CASE
        WHEN ultimo_pago_fecha IS NOT NULL
        THEN CAST(CURRENT_DATE - ultimo_pago_fecha AS INTEGER)
        ELSE NULL
    END                                             AS dias_sin_pago,
    -- Ratio de exposición vs mora
    ROUND(saldo_mora / NULLIF(monto_desembolsado, 0) * 100, 2)
                                                    AS pct_monto_en_mora
FROM analytics_fintrust.dm_cartera_diaria
WHERE en_mora = TRUE
ORDER BY max_dias_atraso DESC, saldo_mora DESC
LIMIT 10;
