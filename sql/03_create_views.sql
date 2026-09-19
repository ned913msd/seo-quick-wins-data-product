-- ============================================================================
-- 03_create_views.sql
-- SEO Quick Wins — Data Product | Capa semántica (vistas de consumo)
-- Requiere: 01_create_tables.sql + 02_insert_only si aplica datos reales
-- Portable: PostgreSQL y SQLite.
-- ============================================================================

-- Limpieza idempotente: las vistas dependientes se eliminan primero
-- (PostgreSQL 15+ usa RESTRICT por defecto en DROP; con orden correcto no hace falta CASCADE)
DROP VIEW IF EXISTS vw_backlink_gaps;
DROP VIEW IF EXISTS vw_executive_summary;
DROP VIEW IF EXISTS vw_quick_wins_priority;
DROP VIEW IF EXISTS vw_position_changes;
DROP VIEW IF EXISTS vw_category_summary;
DROP VIEW IF EXISTS vw_indexation_health;

-- ----------------------------------------------------------------------------
-- vw_quick_wins_priority
-- Corazón del producto: prioriza oportunidades con el modelo ICE.
-- ICE = Impacto (1-10) × Confianza (1-10) × Facilidad (1-10) / 100
-- Impacto   → volumen de la keyword (escala logarítmica)
-- Confianza → inversa de la keyword difficulty
-- Facilidad → inversa de la posición actual (mejor posición = menos trabajo)
-- Solo considera keywords posicionadas en 4..30 (zona de quick win).
-- ----------------------------------------------------------------------------
CREATE VIEW vw_quick_wins_priority AS
WITH latest AS (
    SELECT fkp.*,
           ROW_NUMBER() OVER (
               PARTITION BY fkp.keyword_id, fkp.page_id
               ORDER BY fkp.snapshot_date DESC
           ) AS rn
    FROM fact_keyword_position fkp
)
SELECT
    k.keyword_id,
    k.keyword,
    k.category,
    p.page_id,
    p.url,
    s.domain,
    l.snapshot_date,
    l.position,
    l.previous_position,
    (l.previous_position - l.position) AS position_delta,
    k.monthly_search_volume,
    k.keyword_difficulty,
    l.clicks_30d,
    l.impressions_30d,
    /* Impacto: volumen normalizado 1-10 (log10, tope 100k búsquedas) */
    CAST(ROUND(
        MIN(10.0,
            1.0 + (LOG10(MAX(k.monthly_search_volume, 1.0)) / LOG10(100000.0)) * 9.0
        )
    , 2) AS REAL) AS impact_score,
    /* Confianza: dificultad baja = más confianza 1-10 */
    CAST(ROUND(((100 - k.keyword_difficulty) / 100.0) * 9.0 + 1.0, 2) AS REAL) AS confidence_score,
    /* Facilidad: posición cercana a página 1 = más fácil 1-10 */
    CAST(ROUND(MAX(1.0, ((31 - l.position) / 30.0) * 9.0 + 1.0), 2) AS REAL) AS ease_score,
    CAST(ROUND(
        MIN(10.0,
            1.0 + (LOG10(MAX(k.monthly_search_volume, 1.0)) / LOG10(100000.0)) * 9.0
        )
        * (((100 - k.keyword_difficulty) / 100.0) * 9.0 + 1.0)
        * MAX(1.0, ((31 - l.position) / 30.0) * 9.0 + 1.0)
        / 100.0
    , 2) AS REAL) AS ice_score,
    CASE
        WHEN MIN(10.0, 1.0 + (LOG10(MAX(k.monthly_search_volume, 1.0)) / LOG10(100000.0)) * 9.0)
             * (((100 - k.keyword_difficulty) / 100.0) * 9.0 + 1.0)
             * MAX(1.0, ((31 - l.position) / 30.0) * 9.0 + 1.0)
             / 100.0 >= 7.0 THEN 'P1 - Critical'
        WHEN MIN(10.0, 1.0 + (LOG10(MAX(k.monthly_search_volume, 1.0)) / LOG10(100000.0)) * 9.0)
             * (((100 - k.keyword_difficulty) / 100.0) * 9.0 + 1.0)
             * MAX(1.0, ((31 - l.position) / 30.0) * 9.0 + 1.0)
             / 100.0 >= 4.0 THEN 'P2 - High'
        WHEN MIN(10.0, 1.0 + (LOG10(MAX(k.monthly_search_volume, 1.0)) / LOG10(100000.0)) * 9.0)
             * (((100 - k.keyword_difficulty) / 100.0) * 9.0 + 1.0)
             * MAX(1.0, ((31 - l.position) / 30.0) * 9.0 + 1.0)
             / 100.0 >= 2.0 THEN 'P3 - Medium'
        ELSE 'P4 - Low'
    END AS priority_tier
FROM latest l
JOIN dim_keyword k ON k.keyword_id = l.keyword_id
JOIN dim_page p    ON p.page_id    = l.page_id
JOIN dim_site s    ON s.site_id    = p.site_id
WHERE l.rn = 1
  AND l.position BETWEEN 4 AND 30;   -- zona de oportunidad realista

-- ----------------------------------------------------------------------------
-- vw_position_changes
-- Histórico de movimientos de posición snapshot a snapshot (detección de decay)
-- ----------------------------------------------------------------------------
CREATE VIEW vw_position_changes AS
SELECT
    s.domain,
    k.keyword,
    k.category,
    p.url,
    f.snapshot_date,
    f.position,
    f.previous_position,
    (f.previous_position - f.position) AS position_delta,
    CASE
        WHEN f.previous_position IS NULL THEN 'new'
        WHEN f.position < f.previous_position THEN 'improved'
        WHEN f.position > f.previous_position THEN 'declined'
        ELSE 'stable'
    END AS trend,
    f.clicks_30d,
    f.impressions_30d
FROM fact_keyword_position f
JOIN dim_keyword k ON k.keyword_id = f.keyword_id
JOIN dim_page p    ON p.page_id    = f.page_id
JOIN dim_site s    ON s.site_id    = p.site_id
ORDER BY f.snapshot_date DESC, position_delta ASC;

-- ----------------------------------------------------------------------------
-- vw_category_summary
-- Resumen por categoría de keyword: nº keywords, posición media, clicks
-- ----------------------------------------------------------------------------
CREATE VIEW vw_category_summary AS
SELECT
    s.domain,
    k.category,
    COUNT(DISTINCT k.keyword_id)                    AS n_keywords,
    ROUND(AVG(NULLIF(f.position, 0)), 2)            AS avg_position,
    SUM(f.clicks_30d)                               AS total_clicks_30d,
    SUM(f.impressions_30d)                          AS total_impressions_30d,
    ROUND(
        CASE WHEN SUM(f.impressions_30d) > 0
             THEN SUM(f.clicks_30d) * 1.0 / SUM(f.impressions_30d)
             ELSE 0 END
    , 4)                                            AS avg_ctr
FROM fact_keyword_position f
JOIN dim_keyword k ON k.keyword_id = f.keyword_id
JOIN dim_page p    ON p.page_id    = f.page_id
JOIN dim_site s    ON s.site_id    = p.site_id
WHERE f.snapshot_date = (
    SELECT MAX(snapshot_date) FROM fact_keyword_position
)
GROUP BY s.domain, k.category;

-- ----------------------------------------------------------------------------
-- vw_indexation_health
-- Salud de indexación: páginas no indexables, issues abiertos y velocidad
-- ----------------------------------------------------------------------------
CREATE VIEW vw_indexation_health AS
SELECT
    s.domain,
    p.page_id,
    p.url,
    p.indexable,
    p.page_speed_score,
    COUNT(i.issue_id)                                   AS open_issues,
    COALESCE(SUM(CASE WHEN i.status IN ('open','in_progress')
                      THEN i.traffic_at_risk ELSE 0 END), 0) AS traffic_at_risk
FROM dim_page p
JOIN dim_site s ON s.site_id = p.site_id
LEFT JOIN fact_technical_issue i
       ON i.page_id = p.page_id
      AND i.status IN ('open', 'in_progress')
GROUP BY s.domain, p.page_id, p.url, p.indexable, p.page_speed_score;

-- ----------------------------------------------------------------------------
-- vw_backlink_gaps
-- Páginas con autoridad baja: keywords posicionadas pero pocos backlinks
-- ----------------------------------------------------------------------------
CREATE VIEW vw_backlink_gaps AS
SELECT
    p.page_id,
    s.domain,
    p.url,
    COUNT(DISTINCT k.keyword_id)                    AS n_keywords_ranking,
    COUNT(DISTINCT b.referring_domain)              AS n_referring_domains,
    ROUND(AVG(NULLIF(f.position, 0)), 2)            AS avg_position,
    COALESCE(ROUND(AVG(b.domain_authority), 1), 0)  AS avg_domain_authority
FROM dim_page p
JOIN dim_site s ON s.site_id = p.site_id
LEFT JOIN fact_keyword_position f ON f.page_id = p.page_id AND f.position > 0
LEFT JOIN dim_keyword k           ON k.keyword_id = f.keyword_id
LEFT JOIN fact_backlink b         ON b.page_id = p.page_id
GROUP BY p.page_id, s.domain, p.url
HAVING COUNT(DISTINCT k.keyword_id) > 0;

-- ----------------------------------------------------------------------------
-- vw_executive_summary
-- Vista de dirección: 1 fila por site con KPIs agregados
-- ----------------------------------------------------------------------------
CREATE VIEW vw_executive_summary AS
SELECT
    s.domain,
    COUNT(DISTINCT p.page_id)                                        AS n_pages,
    COUNT(DISTINCT k.keyword_id)                                     AS n_keywords,
    SUM(CASE WHEN f.position BETWEEN 1 AND 3 THEN 1 ELSE 0 END)      AS keywords_top3,
    SUM(CASE WHEN f.position BETWEEN 4 AND 10 THEN 1 ELSE 0 END)     AS keywords_top10,
    SUM(f.clicks_30d)                                                AS total_clicks_30d,
    SUM(f.impressions_30d)                                           AS total_impressions_30d,
    (SELECT COUNT(*) FROM fact_technical_issue i
      WHERE i.site_id = s.site_id AND i.status IN ('open','in_progress')) AS open_issues,
    (SELECT COALESCE(SUM(i.traffic_at_risk), 0) FROM fact_technical_issue i
      WHERE i.site_id = s.site_id AND i.status IN ('open','in_progress')) AS traffic_at_risk
FROM dim_site s
LEFT JOIN dim_page p    ON p.site_id    = s.site_id
LEFT JOIN fact_keyword_position f ON f.page_id = p.page_id
LEFT JOIN dim_keyword k ON k.keyword_id = f.keyword_id
GROUP BY s.site_id, s.domain;
