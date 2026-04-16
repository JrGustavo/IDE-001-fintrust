-- =============================================================================
-- q03_cartera_por_cohorte.sql
-- Pregunta 3: Cartera al día vs cartera en mora por cohorte de originación
-- =============================================================================

SELECT
    cohort_mes                                      AS cohorte,
    num_creditos,
    total_desembolsado,
    cartera_vigente,
    cartera_mora,
    cartera_total_pendiente,
    pct_mora,
    max_dias_atraso_cohorte,
    creditos_en_mora,
    pct_creditos_mora,
    -- Clasificación de deterioro de cohorte
    CASE
        WHEN pct_mora = 0 THEN 'Sana'
        WHEN pct_mora < 5 THEN 'Bajo riesgo'
        WHEN pct_mora < 15 THEN 'Riesgo moderado'
        WHEN pct_mora < 30 THEN 'Riesgo alto'
        ELSE 'Deterioro severo'
    END                                             AS clasificacion_cohorte
FROM analytics_fintrust.vw_cartera_por_cohorte
ORDER BY cohort_mes;
