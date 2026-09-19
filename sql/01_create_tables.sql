-- ============================================================================
-- 01_create_tables.sql
-- SEO Quick Wins — Data Product | Capa: DDL (dimensiones, hechos, staging, log)
-- Sintaxis portable: funciona en PostgreSQL y en SQLite (motor del ETL Python)
-- Uso: psql -d seo_dw -f 01_create_tables.sql
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Limpieza idempotente (orden inverso de dependencias)
-- ----------------------------------------------------------------------------
DROP VIEW  IF EXISTS vw_quick_wins_priority;
DROP VIEW  IF EXISTS vw_position_changes;
DROP VIEW  IF EXISTS vw_category_summary;
DROP VIEW  IF EXISTS vw_indexation_health;
DROP VIEW  IF EXISTS vw_backlink_gaps;
DROP VIEW  IF EXISTS vw_executive_summary;

DROP TABLE IF EXISTS fact_keyword_position;
DROP TABLE IF EXISTS fact_technical_issue;
DROP TABLE IF EXISTS fact_backlink;
DROP TABLE IF EXISTS etl_run_log;
DROP TABLE IF EXISTS stg_pages_raw;
DROP TABLE IF EXISTS stg_keywords_raw;
DROP TABLE IF EXISTS dim_page;
DROP TABLE IF EXISTS dim_keyword;
DROP TABLE IF EXISTS dim_site;

-- ----------------------------------------------------------------------------
-- Dimensiones
-- ----------------------------------------------------------------------------
CREATE TABLE dim_site (
    site_id     INTEGER PRIMARY KEY,
    domain      TEXT    NOT NULL UNIQUE,
    site_name   TEXT    NOT NULL,
    language    TEXT    NOT NULL DEFAULT 'es',
    country     TEXT    NOT NULL DEFAULT 'ES',
    is_active   INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

CREATE TABLE dim_keyword (
    keyword_id            INTEGER PRIMARY KEY,
    keyword               TEXT    NOT NULL UNIQUE,
    category              TEXT    NOT NULL,              -- transaccional | comercial | informativo
    search_intent         TEXT    NOT NULL,
    monthly_search_volume INTEGER NOT NULL CHECK (monthly_search_volume >= 0),
    keyword_difficulty    INTEGER NOT NULL CHECK (keyword_difficulty BETWEEN 0 AND 100),
    current_url_target    TEXT
);

CREATE TABLE dim_page (
    page_id          INTEGER PRIMARY KEY,
    site_id          INTEGER NOT NULL REFERENCES dim_site(site_id),
    url              TEXT    NOT NULL UNIQUE,
    title            TEXT,
    meta_description TEXT,
    h1               TEXT,
    word_count       INTEGER,
    indexable        INTEGER NOT NULL DEFAULT 1 CHECK (indexable IN (0, 1)),
    page_speed_score INTEGER CHECK (page_speed_score BETWEEN 0 AND 100),
    last_crawled_at  TEXT                                   -- ISO 8601 (YYYY-MM-DD)
);

-- ----------------------------------------------------------------------------
-- Tablas de hechos
-- ----------------------------------------------------------------------------
CREATE TABLE fact_keyword_position (
    position_id       INTEGER PRIMARY KEY,
    keyword_id        INTEGER NOT NULL REFERENCES dim_keyword(keyword_id),
    page_id           INTEGER NOT NULL REFERENCES dim_page(page_id),
    snapshot_date     TEXT    NOT NULL,                    -- ISO 8601 (YYYY-MM-DD)
    position          INTEGER NOT NULL CHECK (position >= 0),   -- 0 = no posiciona
    previous_position INTEGER,                                  -- posición del snapshot anterior
    clicks_30d        INTEGER NOT NULL DEFAULT 0,
    impressions_30d   INTEGER NOT NULL DEFAULT 0,
    ctr_30d           REAL,
    UNIQUE (keyword_id, page_id, snapshot_date)
);

CREATE TABLE fact_technical_issue (
    issue_id        INTEGER PRIMARY KEY,
    site_id         INTEGER NOT NULL REFERENCES dim_site(site_id),
    page_id         INTEGER REFERENCES dim_page(page_id),  -- NULL = afecta a todo el sitio
    issue_type      TEXT    NOT NULL,  -- noindex | slow_lcp | meta_description_missing | ...
    severity        TEXT    NOT NULL CHECK (severity IN ('critical', 'high', 'medium', 'low')),
    traffic_at_risk INTEGER NOT NULL DEFAULT 0,           -- visitas/mes estimadas en riesgo
    detected_at     TEXT    NOT NULL,
    resolved_at     TEXT,
    status          TEXT    NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open', 'in_progress', 'resolved', 'wont_fix'))
);

CREATE TABLE fact_backlink (
    backlink_id      INTEGER PRIMARY KEY,
    page_id          INTEGER NOT NULL REFERENCES dim_page(page_id),
    referring_domain TEXT    NOT NULL,
    domain_authority INTEGER CHECK (domain_authority BETWEEN 0 AND 100),
    link_type        TEXT,                                 -- editorial | directory | forum | ...
    first_seen_at    TEXT,
    UNIQUE (page_id, referring_domain)
);

-- ----------------------------------------------------------------------------
-- Staging (zona de aterrizaje del ETL)
-- ----------------------------------------------------------------------------
CREATE TABLE stg_pages_raw (
    load_id          TEXT,
    url              TEXT,
    title            TEXT,
    h1               TEXT,
    word_count       INTEGER,
    indexable        INTEGER,
    page_speed_score INTEGER,
    loaded_at        TEXT
);

CREATE TABLE stg_keywords_raw (
    load_id               TEXT,
    keyword               TEXT,
    category              TEXT,
    search_intent         TEXT,
    monthly_search_volume INTEGER,
    keyword_difficulty    INTEGER
);

-- ----------------------------------------------------------------------------
-- Log de ejecución del pipeline
-- ----------------------------------------------------------------------------
CREATE TABLE etl_run_log (
    run_id         INTEGER PRIMARY KEY,
    started_at     TEXT NOT NULL,
    finished_at    TEXT,
    status         TEXT NOT NULL DEFAULT 'running'
                   CHECK (status IN ('running', 'success', 'failed')),
    rows_extracted INTEGER,
    rows_loaded    INTEGER,
    message        TEXT
);

-- ----------------------------------------------------------------------------
-- Índices de apoyo
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_fkp_keyword    ON fact_keyword_position(keyword_id);
CREATE INDEX IF NOT EXISTS idx_fkp_page       ON fact_keyword_position(page_id);
CREATE INDEX IF NOT EXISTS idx_fkp_date       ON fact_keyword_position(snapshot_date);
CREATE INDEX IF NOT EXISTS idx_issue_page     ON fact_technical_issue(page_id);
CREATE INDEX IF NOT EXISTS idx_issue_site     ON fact_technical_issue(site_id);
CREATE INDEX IF NOT EXISTS idx_backlink_page  ON fact_backlink(page_id);
