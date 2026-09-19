{{
    config(
        materialized='table',
        description='Modelo que identifica Quick Wins en SEO basado en posición, dificultad y tráfico potencial'
    )
}}

WITH keyword_performance_ranked AS (
    SELECT
        k.keyword_id,
        k.keyword_text,
        k.search_intent,
        k.category,
        f.date_id,
        f.current_position,
        f.search_volume,
        f.keyword_difficulty,
        f.estimated_traffic,
        f.estimated_ctr,
        RANK() OVER (PARTITION BY f.date_id ORDER BY f.estimated_traffic DESC) AS traffic_rank,
        ROW_NUMBER() OVER (PARTITION BY f.date_id ORDER BY f.current_position ASC) AS position_rank
    FROM {{ ref('stg_fact_keyword_performance') }} f
    JOIN {{ source('legacy', 'dim_keyword') }} k ON f.keyword_id = k.keyword_id
)

SELECT
    keyword_id,
    keyword_text,
    search_intent,
    category,
    date_id,
    current_position,
    search_volume,
    keyword_difficulty,
    estimated_traffic,
    estimated_ctr,
    traffic_rank,
    position_rank,
    CASE
        WHEN current_position BETWEEN 4 AND 10 AND keyword_difficulty < 50 THEN '🎯 QUICK WIN'
        WHEN current_position <= 3 THEN '✅ YA POSICIONADO'
        ELSE '⚠️ NECESITA TRABAJO'
    END AS classification,
    ROUND((estimated_traffic * 5) - estimated_traffic, 0) AS oportunidad_mejora,
    CASE
        WHEN current_position BETWEEN 4 AND 10 AND keyword_difficulty < 50
        THEN (estimated_traffic * 5) - estimated_traffic
        ELSE 0
    END AS prioridad_score
FROM keyword_performance_ranked
