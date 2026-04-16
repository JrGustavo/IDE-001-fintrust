-- =============================================================================
-- q05_dataset_bi.sql
-- Pregunta 5: Dataset / vista lista para conectar con Power BI, Tableau o Looker
-- Esta consulta genera el export final o se usa como fuente directa en BI
-- =============================================================================

-- Opción A: Consultar la vista maestra directamente (recomendado para BI live)
SELECT *
FROM analytics_fintrust.vw_dataset_bi
ORDER BY fecha_originacion DESC, monto_desembolsado DESC;

-- Opción B: En DuckDB, exportar a CSV para importar en Power BI Desktop
-- COPY (SELECT * FROM analytics_fintrust.vw_dataset_bi)
-- TO 'fintrust_dataset_bi.csv'
-- (HEADER, DELIMITER ',', QUOTECHAR '"');

-- Opción C: Resumen ejecutivo para tablero de cartera diario
SELECT
    fecha_corte,
    -- KPIs de originación
    COUNT(loan_id)                                  AS total_creditos_activos,
    SUM(monto_desembolsado)                         AS cartera_total,
    -- KPIs de mora
    SUM(saldo_mora)                                 AS total_cartera_mora,
    SUM(saldo_vigente)                              AS total_cartera_vigente,
    ROUND(SUM(saldo_mora) / NULLIF(SUM(saldo_pendiente), 0) * 100, 2)
                                                    AS indice_mora_pct,
    COUNT(CASE WHEN en_mora = TRUE THEN 1 END)      AS creditos_en_mora,
    -- KPIs de recaudo
    SUM(total_recaudado)                            AS recaudo_historico_total,
    -- Segmentación
    COUNT(DISTINCT ciudad)                          AS ciudades_activas,
    COUNT(DISTINCT segmento)                        AS segmentos_activos
FROM analytics_fintrust.vw_dataset_bi
GROUP BY fecha_corte;
