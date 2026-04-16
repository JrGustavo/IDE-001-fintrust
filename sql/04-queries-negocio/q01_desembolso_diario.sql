-- =============================================================================
-- q01_desembolso_diario.sql
-- Pregunta 1: Desembolso total por día, ciudad y segmento
-- =============================================================================

SELECT
    fecha_desembolso,
    ciudad,
    segmento,
    tipo_producto,
    num_creditos,
    total_desembolsado,
    promedio_desembolso,
    -- Acumulado por ciudad (window function)
    SUM(total_desembolsado) OVER (
        PARTITION BY ciudad
        ORDER BY fecha_desembolso
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                               AS desembolso_acum_ciudad,
    -- % sobre el total del día
    ROUND(
        total_desembolsado / SUM(total_desembolsado) OVER (
            PARTITION BY fecha_desembolso
        ) * 100, 2
    )                                               AS pct_del_dia
FROM analytics_fintrust.vw_desembolso_diario
ORDER BY fecha_desembolso DESC, total_desembolsado DESC;
