-- =============================================================================
-- 02-staging/stg_customers.sql
-- Staging de Clientes: limpieza y estandarización
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging_fintrust;

CREATE OR REPLACE TABLE staging_fintrust.stg_customers AS

WITH source AS (
    SELECT * FROM raw_fintrust.customers
),

cleaned AS (
    SELECT
        -- Clave primaria
        TRIM(customer_id)                           AS customer_id,

        -- Normalización de nombre: TRIM de espacios
        TRIM(full_name)                             AS full_name,

        -- Normalización de ciudad: TRIM + título consistente
        -- Supuesto: ciudades válidas son las que aparecen en el set de datos
        TRIM(city)                                  AS city,

        -- Segmento estandarizado a valores conocidos
        -- Valores válidos: 'Mass Market', 'Premium', 'SME'
        TRIM(segment)                               AS segment,

        -- Ingreso mensual: debe ser > 0
        monthly_income,

        -- Fecha de creación como está (DATE ya limpio)
        created_at,

        -- Flags de calidad
        CASE
            WHEN customer_id IS NULL OR TRIM(customer_id) = '' THEN TRUE
            ELSE FALSE
        END                                         AS _flag_sin_id,

        CASE
            WHEN monthly_income IS NULL OR monthly_income <= 0 THEN TRUE
            ELSE FALSE
        END                                         AS _flag_ingreso_invalido,

        CASE
            WHEN TRIM(segment) NOT IN ('Mass Market','Premium','SME') THEN TRUE
            ELSE FALSE
        END                                         AS _flag_segmento_invalido,

        -- Metadatos de pipeline
        CURRENT_TIMESTAMP                           AS _staged_at

    FROM source
),

-- Solo registros válidos pasan a staging
valid AS (
    SELECT *
    FROM cleaned
    WHERE _flag_sin_id = FALSE
      AND _flag_ingreso_invalido = FALSE
      AND _flag_segmento_invalido = FALSE
)

SELECT
    customer_id,
    full_name,
    city,
    segment,
    monthly_income,
    created_at,
    _staged_at
FROM valid;

-- Verificación rápida post-carga
-- SELECT COUNT(*) AS total, COUNT(DISTINCT customer_id) AS unicos FROM staging_fintrust.stg_customers;
