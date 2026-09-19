-- ============================================================================
-- 04_etl_pipeline.sql
-- SEO Quick Wins — Data Product | Pipeline ETL 100% SQL (fallback sin Python)
-- Portable: PostgreSQL y SQLite.
--
-- Contrato de entrada (tablas de staging, alimentadas por extracciones):
--   * stg_keywords_raw  -> keywords nuevas a incorporar a dim_keyword
--   * stg_pages_raw     -> paginas nuevas/actualizadas para dim_page
--   * stg_positions_raw -> snapshots de posiciones (opcional; si el motor no
--                          tiene esa tabla se ignora el bloque con un guard)
--
-- Patrones usados:
--   * Upsert portable con LEFT JOIN anti-join (compatible SQLite/PostgreSQL)
--   * Carga por lotes con load_id para trazabilidad
--   * Log de ejecucion en etl_run_log
--
-- Uso en SQLite:  sqlite3 seo_warehouse.db < 04_etl_pipeline.sql
-- Uso en Postgres: psql -d seo_dw -f 04_etl_pipeline.sql
-- ============================================================================

-- Configuracion para ejecucion script (ignora errores menores de sesion)
-- SQLite: .bail off  |  PostgreSQL: ON_ERROR_STOP off (por defecto)

-- ----------------------------------------------------------------------------
-- Paso 0: abrir run en el log
-- ----------------------------------------------------------------------------
INSERT INTO etl_run_log (run_id, started_at, status, message)
SELECT
    COALESCE(MAX(run_id), 0) + 1,
    'now',
    'running',
    'ETL SQL-only: lote staging -> core'
FROM etl_run_log;

-- Guardamos el run_id en uso para el cierre del log
-- (en SQLite se recupera con last_insert_rowid(); en PG con currval, aqui lo
-- recalculamos al final para mantener portabilidad)

-- ----------------------------------------------------------------------------
-- Paso 1: dim_keyword <- stg_keywords_raw (insert solo de keywords nuevas)
-- ----------------------------------------------------------------------------
INSERT INTO dim_keyword (
    keyword_id, keyword, category, search_intent,
    monthly_search_volume, keyword_difficulty, current_url_target
)
SELECT
    COALESCE((SELECT MAX(keyword_id) FROM dim_keyword), 0)
      + ROW_NUMBER() OVER (ORDER BY k.keyword),
    TRIM(LOWER(k.keyword)),
    COALESCE(NULLIF(TRIM(k.category), ''), 'informativo'),
    COALESCE(NULLIF(TRIM(k.search_intent), ''), 'informational'),
    COALESCE(k.monthly_search_volume, 0),
    COALESCE(k.keyword_difficulty, 50),
    NULL
FROM stg_keywords_raw k
LEFT JOIN dim_keyword dk
       ON LOWER(dk.keyword) = TRIM(LOWER(k.keyword))
WHERE dk.keyword_id IS NULL
  AND TRIM(COALESCE(k.keyword, '')) <> '';

-- ----------------------------------------------------------------------------
-- Paso 2: dim_page <- stg_pages_raw (insert de paginas nuevas; update de cambios)
-- ----------------------------------------------------------------------------
-- 2a. Insert de paginas que no existen (asumimos site_id = 1 si no se puede
--     inferir el dominio desde la URL; ajustar si hay multi-sitio)
INSERT INTO dim_page (
    page_id, site_id, url, title, h1, word_count,
    indexable, page_speed_score, last_crawled_at
)
SELECT
    COALESCE((SELECT MAX(page_id) FROM dim_page), 0)
      + ROW_NUMBER() OVER (ORDER BY p.url),
    1,  -- TODO multi-sitio: derivar site_id del dominio de la URL
    TRIM(p.url),
    TRIM(p.title),
    TRIM(p.h1),
    COALESCE(p.word_count, 0),
    COALESCE(p.indexable, 1),
    p.page_speed_score,
    COALESCE(SUBSTR(p.loaded_at, 1, 10), DATE('now'))
FROM stg_pages_raw p
LEFT JOIN dim_page dp ON dp.url = TRIM(p.url)
WHERE dp.page_id IS NULL
  AND TRIM(COALESCE(p.url, '')) <> '';

-- 2b. Update de paginas existentes con datos frescos del staging
UPDATE dim_page
SET title            = (SELECT TRIM(p.title) FROM stg_pages_raw p WHERE p.url = dim_page.url AND TRIM(p.title) IS NOT NULL),
    h1               = (SELECT TRIM(p.h1)    FROM stg_pages_raw p WHERE p.url = dim_page.url AND TRIM(p.h1)    IS NOT NULL),
    word_count       = COALESCE((SELECT p.word_count FROM stg_pages_raw p WHERE p.url = dim_page.url), dim_page.word_count),
    indexable        = COALESCE((SELECT p.indexable  FROM stg_pages_raw p WHERE p.url = dim_page.url), dim_page.indexable),
    page_speed_score = COALESCE((SELECT p.page_speed_score FROM stg_pages_raw p WHERE p.url = dim_page.url), dim_page.page_speed_score),
    last_crawled_at  = COALESCE((SELECT SUBSTR(p.loaded_at, 1, 10) FROM stg_pages_raw p WHERE p.url = dim_page.url), dim_page.last_crawled_at)
WHERE url IN (SELECT TRIM(url) FROM stg_pages_raw WHERE TRIM(COALESCE(url, '')) <> '');

-- ----------------------------------------------------------------------------
-- Paso 3: snapshot de posiciones <- stg_positions_raw (si existe)
--   Estructura esperada: load_id, keyword, url, snapshot_date, position
--   En SQLite, si la tabla no existe, este bloque falla suave y el ETL sigue.
-- ----------------------------------------------------------------------------
-- SQLite: la tabla puede no existir; creamos la tabla staging si falta.
CREATE TABLE IF NOT EXISTS stg_positions_raw (
    load_id       TEXT,
    keyword       TEXT,
    url           TEXT,
    snapshot_date TEXT,
    position      INTEGER
);

INSERT INTO fact_keyword_position (
    position_id, keyword_id, page_id, snapshot_date,
    position, previous_position, clicks_30d, impressions_30d, ctr_30d
)
SELECT
    COALESCE((SELECT MAX(position_id) FROM fact_keyword_position), 0)
      + ROW_NUMBER() OVER (ORDER BY sp.keyword, sp.url),
    dk.keyword_id,
    dp.page_id,
    sp.snapshot_date,
    COALESCE(sp.position, 0),
    -- previous_position: ultima posicion conocida antes de este snapshot
    (SELECT f2.position
       FROM fact_keyword_position f2
      WHERE f2.keyword_id = dk.keyword_id
        AND f2.page_id    = dp.page_id
        AND f2.snapshot_date < sp.snapshot_date
      ORDER BY f2.snapshot_date DESC
      LIMIT 1),
    0,
    0,
    NULL
FROM stg_positions_raw sp
JOIN dim_keyword dk ON LOWER(dk.keyword) = TRIM(LOWER(sp.keyword))
JOIN dim_page dp    ON dp.url = TRIM(sp.url)
LEFT JOIN fact_keyword_position f
       ON f.keyword_id    = dk.keyword_id
      AND f.page_id       = dp.page_id
      AND f.snapshot_date = sp.snapshot_date
WHERE f.position_id IS NULL
  AND sp.snapshot_date IS NOT NULL;

-- ----------------------------------------------------------------------------
-- Paso 4: reglas de negocio automaticas (deteccion de issues)
-- ----------------------------------------------------------------------------
-- 4a. Paginas no indexables con keywords posicionando -> issue noindex
INSERT INTO fact_technical_issue (issue_id, site_id, page_id, issue_type, severity, traffic_at_risk, detected_at, status)
SELECT
    COALESCE((SELECT MAX(issue_id) FROM fact_technical_issue), 0)
      + ROW_NUMBER() OVER (ORDER BY p.page_id),
    p.site_id,
    p.page_id,
    'noindex',
    'critical',
    0,
    DATE('now'),
    'open'
FROM dim_page p
WHERE p.indexable = 0
  AND EXISTS (SELECT 1 FROM fact_keyword_position f WHERE f.page_id = p.page_id AND f.position > 0)
  AND NOT EXISTS (
      SELECT 1 FROM fact_technical_issue i
       WHERE i.page_id = p.page_id
         AND i.issue_type = 'noindex'
         AND i.status IN ('open', 'in_progress')
  );

-- 4b. Decay de contenido: keyword que cayo >= 5 posiciones en el ultimo snapshot
--     (decay = position empeora: el numero de posicion sube)
INSERT INTO fact_technical_issue (issue_id, site_id, page_id, issue_type, severity, traffic_at_risk, detected_at, status)
SELECT
    COALESCE((SELECT MAX(issue_id) FROM fact_technical_issue), 0)
      + ROW_NUMBER() OVER (ORDER BY f.keyword_id),
    p.site_id,
    f.page_id,
    'content_decay',
    CASE WHEN f.position - f.previous_position >= 8 THEN 'high' ELSE 'medium' END,
    0,
    DATE('now'),
    'open'
FROM fact_keyword_position f
JOIN dim_page p ON p.page_id = f.page_id
WHERE f.position > 0
  AND f.previous_position IS NOT NULL
  AND (f.position - f.previous_position) >= 5   -- mejoraba antes, empeora ahora
  AND NOT EXISTS (
      SELECT 1 FROM fact_technical_issue i
       WHERE i.page_id = f.page_id
         AND i.issue_type = 'content_decay'
         AND i.detected_at = DATE('now')
  );

-- ----------------------------------------------------------------------------
-- Paso 5: cierre del run en el log
-- ----------------------------------------------------------------------------
UPDATE etl_run_log
SET finished_at    = 'now',
    status         = 'success',
    rows_extracted = (SELECT (SELECT COUNT(*) FROM stg_keywords_raw) + (SELECT COUNT(*) FROM stg_pages_raw) + (SELECT COUNT(*) FROM stg_positions_raw)),
    rows_loaded    = (SELECT changes()),
    message        = 'ETL SQL-only completado'
WHERE run_id = (SELECT MAX(run_id) FROM etl_run_log WHERE status = 'running');

-- ----------------------------------------------------------------------------
-- Verificacion rapida (opcional, descomentar para probar)
-- ----------------------------------------------------------------------------
-- SELECT 'dim_keyword' AS tabla, COUNT(*) AS filas FROM dim_keyword
-- UNION ALL SELECT 'dim_page',  COUNT(*) FROM dim_page
-- UNION ALL SELECT 'fact_keyword_position', COUNT(*) FROM fact_keyword_position
-- UNION ALL SELECT 'fact_technical_issue', COUNT(*) FROM fact_technical_issue
-- UNION ALL SELECT 'etl_run_log', COUNT(*) FROM etl_run_log;
