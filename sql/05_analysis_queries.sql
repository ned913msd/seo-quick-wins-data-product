-- ============================================================================
-- 05_analysis_queries.sql
-- SEO Quick Wins — Data Product | Queries de análisis ad-hoc
-- Portable: PostgreSQL y SQLite (sintaxis compatible).
-- Orden sugerido: ejecutar 01, 02 y 03 antes de usar estas queries.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Q1. Top 10 quick wins priorizados (la query estrella del producto)
-- ----------------------------------------------------------------------------
SELECT
    keyword,
    url,
    position,
    previous_position,
    position_delta,
    monthly_search_volume,
    ROUND(ice_score, 2)   AS ice,
    priority_tier
FROM vw_quick_wins_priority
ORDER BY ice_score DESC
LIMIT 10;

-- ----------------------------------------------------------------------------
-- Q2. Keywords "casi ganando": posición 4-10 con volumen alto
--     (subir de página 2 a top 3 suele multiplicar el CTR por 3-5x)
-- ----------------------------------------------------------------------------
SELECT
    k.keyword,
    p.url,
    f.position,
    k.monthly_search_volume,
    f.clicks_30d,
    f.impressions_30d
FROM fact_keyword_position f
JOIN dim_keyword k ON k.keyword_id = f.keyword_id
JOIN dim_page p    ON p.page_id    = f.page_id
WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_keyword_position)
  AND f.position BETWEEN 4 AND 10
  AND k.monthly_search_volume >= 2000
ORDER BY k.monthly_search_volume DESC;

-- ----------------------------------------------------------------------------
-- Q3. Decay de contenido: keywords que han perdido >= 3 posiciones
--     (decay = position empeora: el numero de posicion sube)
-- ----------------------------------------------------------------------------
SELECT
    k.keyword,
    p.url,
    f.previous_position AS pos_antes,
    f.position          AS pos_ahora,
    f.position - f.previous_position AS caida,
    k.monthly_search_volume
FROM fact_keyword_position f
JOIN dim_keyword k ON k.keyword_id = f.keyword_id
JOIN dim_page p    ON p.page_id    = f.page_id
WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_keyword_position)
  AND (f.position - f.previous_position) >= 3
ORDER BY (f.position - f.previous_position) DESC;

-- ----------------------------------------------------------------------------
-- Q4. Impacto de errores técnicos: tráfico en riesgo por tipo de issue
-- ----------------------------------------------------------------------------
SELECT
    issue_type,
    severity,
    COUNT(*)                       AS n_issues,
    SUM(traffic_at_risk)           AS trafico_en_riesgo
FROM fact_technical_issue
WHERE status IN ('open', 'in_progress')
GROUP BY issue_type, severity
ORDER BY trafico_en_riesgo DESC;

-- ----------------------------------------------------------------------------
-- Q5. Páginas con risk de noindex que siguen recibiendo impresiones
--     (el quick win más rápido que existe: quitar el noindex)
-- ----------------------------------------------------------------------------
SELECT
    p.url,
    p.indexable,
    SUM(f.impressions_30d) AS impresiones_30d,
    SUM(f.clicks_30d)      AS clicks_30d,
    COUNT(DISTINCT k.keyword_id) AS keywords_asociadas
FROM dim_page p
LEFT JOIN fact_keyword_position f ON f.page_id = p.page_id
LEFT JOIN dim_keyword k           ON k.keyword_id = f.keyword_id
WHERE p.indexable = 0
GROUP BY p.page_id, p.url, p.indexable
HAVING SUM(f.impressions_30d) > 0;

-- ----------------------------------------------------------------------------
-- Q6. Canibalización de keywords: mismo keyword posicionando en 2+ páginas
-- ----------------------------------------------------------------------------
SELECT
    k.keyword,
    COUNT(DISTINCT f.page_id) AS n_paginas_compitiendo,
    GROUP_CONCAT(p.url, ' | ') AS urls
FROM fact_keyword_position f
JOIN dim_keyword k ON k.keyword_id = f.keyword_id
JOIN dim_page p    ON p.page_id    = f.page_id
WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_keyword_position)
  AND f.position > 0
GROUP BY k.keyword_id, k.keyword
HAVING COUNT(DISTINCT f.page_id) > 1;

-- ----------------------------------------------------------------------------
-- Q7. Oportunidades de CTR: posiciones buenas pero CTR por debajo del benchmark
--     (suele indicar title/meta poco atractivos)
-- ----------------------------------------------------------------------------
SELECT
    k.keyword,
    p.url,
    f.position,
    f.impressions_30d,
    ROUND(f.ctr_30d * 100, 2) AS ctr_pct,
    /* Benchmark de CTR medio por posición (estimación industria) */
    CASE
        WHEN f.position <= 1 THEN 28.0
        WHEN f.position <= 3 THEN 15.0
        WHEN f.position <= 5 THEN 8.0
        WHEN f.position <= 10 THEN 4.0
        ELSE 1.5
    END AS ctr_benchmark_pct
FROM fact_keyword_position f
JOIN dim_keyword k ON k.keyword_id = f.keyword_id
JOIN dim_page p    ON p.page_id    = f.page_id
WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_keyword_position)
  AND f.impressions_30d > 500
  AND f.ctr_30d * 100 < CASE
        WHEN f.position <= 1 THEN 28.0
        WHEN f.position <= 3 THEN 15.0
        WHEN f.position <= 5 THEN 8.0
        WHEN f.position <= 10 THEN 4.0
        ELSE 1.5
    END
ORDER BY f.impressions_30d DESC;

-- ----------------------------------------------------------------------------
-- Q8. Backlink gaps: keywords posicionadas en páginas sin backlinks
-- ----------------------------------------------------------------------------
SELECT
    k.keyword,
    p.url,
    f.position,
    k.keyword_difficulty,
    (SELECT COUNT(*) FROM fact_backlink b WHERE b.page_id = p.page_id) AS backlinks
FROM fact_keyword_position f
JOIN dim_keyword k ON k.keyword_id = f.keyword_id
JOIN dim_page p    ON p.page_id    = f.page_id
WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_keyword_position)
  AND f.position BETWEEN 5 AND 20
  AND NOT EXISTS (SELECT 1 FROM fact_backlink b WHERE b.page_id = p.page_id)
ORDER BY k.monthly_search_volume DESC;

-- ----------------------------------------------------------------------------
-- Q9. Evolución semanal de clicks por site (tendencia)
-- ----------------------------------------------------------------------------
SELECT
    s.domain,
    f.snapshot_date,
    SUM(f.clicks_30d)      AS clicks_30d,
    SUM(f.impressions_30d) AS impressions_30d,
    ROUND(
        CASE WHEN SUM(f.impressions_30d) > 0
             THEN SUM(f.clicks_30d) * 100.0 / SUM(f.impressions_30d)
             ELSE 0 END, 2
    ) AS ctr_pct
FROM fact_keyword_position f
JOIN dim_page p ON p.page_id = f.page_id
JOIN dim_site s ON s.site_id = p.site_id
GROUP BY s.domain, f.snapshot_date
ORDER BY s.domain, f.snapshot_date;

-- ----------------------------------------------------------------------------
-- Q10. Resumen ejecutivo (para la slide 1 del dashboard)
-- ----------------------------------------------------------------------------
SELECT * FROM vw_executive_summary;

-- ----------------------------------------------------------------------------
-- Q11. Score de salud SEO por página (0-100)
--      50% posiciones + 30% velocidad + 20% ausencia de issues
-- ----------------------------------------------------------------------------
SELECT
    p.url,
    p.page_speed_score,
    COUNT(DISTINCT k.keyword_id) AS keywords_posicionadas,
    ROUND(AVG(CASE WHEN f.position > 0 THEN (11 - MIN(f.position, 10)) * 10.0 END), 1) AS score_posiciones,
    ROUND(AVG(CASE WHEN f.position > 0 THEN (11 - MIN(f.position, 10)) * 10.0 END) * 0.5
        + COALESCE(p.page_speed_score, 0) * 0.3
        + (100 - MIN(COALESCE((
            SELECT SUM(CASE WHEN i.status IN ('open','in_progress') THEN 20 ELSE 0 END)
            FROM fact_technical_issue i WHERE i.page_id = p.page_id
          ), 0), 100)) * 0.2
    , 1) AS health_score
FROM dim_page p
LEFT JOIN fact_keyword_position f ON f.page_id = p.page_id
LEFT JOIN dim_keyword k           ON k.keyword_id = f.keyword_id
GROUP BY p.page_id, p.url, p.page_speed_score
ORDER BY health_score DESC;
