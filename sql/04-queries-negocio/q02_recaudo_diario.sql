-- =============================================================================
-- q02_recaudo_diario.sql
-- Pregunta 2: Recaudo diario total y recaudo aplicado a cuotas vencidas
-- =============================================================================

SELECT
    fecha_recaudo,
    num_pagos,
    total_recaudado,
    recaudo_en_mora,
    recaudo_al_dia,
    pct_recaudo_mora,
    -- Recaudo acumulado (running total)
    SUM(total_recaudado) OVER (
        ORDER BY fecha_recaudo
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                               AS recaudo_acumulado,
    -- Promedio móvil 7 días
    AVG(total_recaudado) OVER (
        ORDER BY fecha_recaudo
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )                                               AS promedio_movil_7d
FROM analytics_fintrust.vw_recaudo_diario
ORDER BY fecha_recaudo DESC;
