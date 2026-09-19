-- ============================================================================
-- 02_insert_sample_data.sql
-- SEO Quick Wins — Data Product | Datos de ejemplo (demos y pruebas)
-- Rerunnable: borra y recarga el dataset semilla completo.
-- Historia de negocio incluida:
--   * zapatillas running      → casi-ganando en pos. 11 (quick win clásico)
--   * como elegir zapatillas  → posición 3 sostenida
--   * mejores zapatillas 2026 → decay (de 9 a 14)
--   * ofertas deportivas      → página con noindex accidental (pos. 0)
--   * herramientas seo gratis → decay fuerte (de 8 a 16)
--   * canibalización          → kw1 y kw4 con dos páginas compitiendo
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Limpieza (hijos primero, padres después)
-- ----------------------------------------------------------------------------
DELETE FROM fact_keyword_position;
DELETE FROM fact_technical_issue;
DELETE FROM fact_backlink;
DELETE FROM stg_pages_raw;
DELETE FROM stg_keywords_raw;
DELETE FROM dim_page;
DELETE FROM dim_keyword;
DELETE FROM dim_site;
DELETE FROM etl_run_log;

-- ----------------------------------------------------------------------------
-- dim_site
-- ----------------------------------------------------------------------------
INSERT INTO dim_site (site_id, domain, site_name, language, country, is_active) VALUES
(1, 'tienda-demo.com', 'Tienda Demo', 'es', 'ES', 1),
(2, 'blog-demo.com',   'Blog Demo',   'es', 'MX', 1);

-- ----------------------------------------------------------------------------
-- dim_keyword
-- ----------------------------------------------------------------------------
INSERT INTO dim_keyword (keyword_id, keyword, category, search_intent, monthly_search_volume, keyword_difficulty, current_url_target) VALUES
(1,  'zapatillas running',           'transaccional', 'transactional', 14800, 45, 'https://tienda-demo.com/zapatillas-running'),
(2,  'zapatillas running hombre',    'transaccional', 'transactional',  8100, 40, 'https://tienda-demo.com/zapatillas-running-hombre'),
(3,  'mejores zapatillas running 2026', 'comercial',  'commercial',     6600, 52, 'https://tienda-demo.com/blog/como-elegir-zapatillas-running'),
(4,  'como elegir zapatillas running',  'informativo','informational',  5400, 30, 'https://tienda-demo.com/blog/como-elegir-zapatillas-running'),
(5,  'auriculares bluetooth',        'transaccional', 'transactional', 22200, 60, 'https://tienda-demo.com/auriculares'),
(6,  'ofertas deportivas',           'transaccional', 'transactional',  3600, 25, 'https://tienda-demo.com/ofertas'),
(7,  'black friday deportivo',       'transaccional', 'transactional',  9900, 48, 'https://tienda-demo.com/landing-black-friday-2024'),
(8,  'auditoria seo',                'informativo',   'informational',  4400, 38, 'https://blog-demo.com/audit-seo'),
(9,  'seo tecnico',                  'informativo',   'informational',  2900, 42, 'https://blog-demo.com/seo-tecnico'),
(10, 'herramientas seo gratis',      'comercial',     'commercial',    12000, 35, 'https://blog-demo.com/post-viejo');

-- ----------------------------------------------------------------------------
-- dim_page
-- ----------------------------------------------------------------------------
INSERT INTO dim_page (page_id, site_id, url, title, meta_description, h1, word_count, indexable, page_speed_score, last_crawled_at) VALUES
(1,  1, 'https://tienda-demo.com/',                                   'Zapatillas y ropa deportiva | Tienda Demo', 'Todo el deporte en un solo sitio: zapatillas, ropa y accesorios con envío en 24h.', 'Deporte para todos',                 850,  1, 72, '2026-09-10'),
(2,  1, 'https://tienda-demo.com/zapatillas-running',                 'Zapatillas running | Tienda Demo',          'Las mejores zapatillas running al mejor precio. Nike, Adidas, Asics y más.',        'Zapatillas running',                1200,  1, 65, '2026-09-10'),
(3,  1, 'https://tienda-demo.com/zapatillas-running-hombre',          'Zapatillas running hombre | Tienda Demo',   'Encuentra tus zapatillas de running para hombre por talla, marca y tipo de pisada.', 'Zapatillas running para hombre',     950,  1, 61, '2026-09-10'),
(4,  1, 'https://tienda-demo.com/auriculares',                        'Auriculares | Tienda Demo',                 'Auriculares bluetooth con cancelación de ruido y los mejores precios del mercado.',  'Auriculares',                        700,  1, 58, '2026-09-10'),
(5,  1, 'https://tienda-demo.com/blog/como-elegir-zapatillas-running','Cómo elegir zapatillas running: guía 2026', 'Guía completa para elegir zapatillas de running según pisada, peso y distancia.',    'Cómo elegir zapatillas de running', 2100,  1, 80, '2026-09-10'),
(6,  1, 'https://tienda-demo.com/ofertas',                            'Ofertas | Tienda Demo',                     'Las mejores ofertas en material deportivo actualizadas cada semana.',                'Ofertas de la semana',               300,  0, 45, '2026-09-10'),
(7,  1, 'https://tienda-demo.com/landing-black-friday-2024',          'Black Friday 2024 | Tienda Demo',           'Chollos del Black Friday en material deportivo.',                                    'Black Friday 2024',                  450,  1, 55, '2026-09-10'),
(8,  2, 'https://blog-demo.com/seo-tecnico',                          'Guía de SEO técnico para 2026',             'Todo lo que necesitas saber sobre indexación, Core Web Vitals y rastreo.',           'SEO técnico: la guía definitiva',   1800,  1, 77, '2026-09-11'),
(9,  2, 'https://blog-demo.com/audit-seo',                            'Cómo hacer una auditoría SEO paso a paso',  'Plantilla y checklist para auditar cualquier web en menos de 10 horas.',             'Auditoría SEO paso a paso',         2400,  1, 74, '2026-09-11'),
(10, 2, 'https://blog-demo.com/post-viejo',                           '10 herramientas SEO de 2021',               'Las herramientas SEO imprescindibles (artículo de 2021, desactualizado).',           '10 herramientas SEO',                800,  1, 50, '2026-09-11');

-- ----------------------------------------------------------------------------
-- fact_keyword_position (snapshot 2026-09-10)
-- position = 0 significa "no posiciona en top 100"
-- ----------------------------------------------------------------------------
INSERT INTO fact_keyword_position (position_id, keyword_id, page_id, snapshot_date, position, previous_position, clicks_30d, impressions_30d, ctr_30d) VALUES
(1,  1, 2,  '2026-09-10', 11, 14,   210, 6200, 0.0339),
(2,  2, 3,  '2026-09-10',  9, 12,   340, 5100, 0.0667),
(3,  3, 5,  '2026-09-10', 14,  9,    95, 3100, 0.0306),
(4,  4, 5,  '2026-09-10',  3,  4,   480, 4100, 0.1171),
(5,  5, 4,  '2026-09-10', 18, 16,    60, 4400, 0.0136),
(6,  6, 6,  '2026-09-10',  0,  0,     0,  300, 0.0000),
(7,  7, 7,  '2026-09-10', 27, 21,    30,  900, 0.0333),
(8,  8, 9,  '2026-09-10',  6,  6,   390, 5200, 0.0750),
(9,  9, 8,  '2026-09-10',  7,  5,   260, 3900, 0.0667),
(10, 10, 10, '2026-09-10', 16,  8,    70, 3400, 0.0206),
(11, 1, 3,  '2026-09-10', 21, 19,    25, 1200, 0.0208),
(12, 4, 2,  '2026-09-10', 35, 33,     5,  800, 0.0063);

-- ----------------------------------------------------------------------------
-- fact_technical_issue
-- ----------------------------------------------------------------------------
INSERT INTO fact_technical_issue (issue_id, site_id, page_id, issue_type, severity, traffic_at_risk, detected_at, resolved_at, status) VALUES
(1,  1, 6,    'noindex',                   'critical', 2400, '2026-08-28', NULL,        'open'),
(2,  1, 3,    'slow_lcp',                  'high',     1800, '2026-09-01', NULL,        'in_progress'),
(3,  1, 2,    'meta_description_missing',  'medium',    900, '2026-08-20', NULL,        'open'),
(4,  1, 7,    'stale_seasonal_content',    'medium',   1100, '2026-09-05', NULL,        'open'),
(5,  1, 2,    'title_too_long',            'medium',    700, '2026-09-02', NULL,        'open'),
(6,  2, 10,   'content_decay',             'high',     1500, '2026-09-08', NULL,        'open'),
(7,  2, 8,    'canonical_conflict',        'high',      800, '2026-08-30', NULL,        'open'),
(8,  2, 9,    'image_alt_missing',         'low',       200, '2026-08-15', '2026-08-25','resolved'),
(9,  1, NULL, 'sitemap_404',               'high',     2200, '2026-09-10', NULL,        'open'),
(10, 1, 5,    'internal_links_broken',     'medium',    400, '2026-09-03', NULL,        'open');

-- ----------------------------------------------------------------------------
-- fact_backlink
-- ----------------------------------------------------------------------------
INSERT INTO fact_backlink (backlink_id, page_id, referring_domain, domain_authority, link_type, first_seen_at) VALUES
(1, 2,  'runningnews.es',   54, 'editorial', '2025-11-02'),
(2, 2,  'deporweb.com',     61, 'editorial', '2026-01-15'),
(3, 3,  'runnerstore.mx',   32, 'directory', '2026-02-10'),
(4, 4,  'audioguides.io',   28, 'forum',     '2025-09-30'),
(5, 5,  'marketingtoday.es',58, 'editorial', '2026-03-21'),
(6, 5,  'seotips.blog',     41, 'editorial', '2025-12-05'),
(7, 9,  'growthlab.io',     63, 'editorial', '2026-04-11');

-- ----------------------------------------------------------------------------
-- Staging de ejemplo (para demostrar el pipeline SQL-only de 04_etl_pipeline.sql)
-- ----------------------------------------------------------------------------
INSERT INTO stg_pages_raw (load_id, url, title, h1, word_count, indexable, page_speed_score, loaded_at) VALUES
('seed-2026-09-10', 'https://tienda-demo.com/ofertas', 'Ofertas | Tienda Demo', 'Ofertas de la semana', 300, 0, 45, '2026-09-10T08:00:00Z'),
('seed-2026-09-10', 'https://blog-demo.com/post-viejo', '10 herramientas SEO de 2021', '10 herramientas SEO', 800, 1, 50, '2026-09-10T08:00:00Z');

INSERT INTO stg_keywords_raw (load_id, keyword, category, search_intent, monthly_search_volume, keyword_difficulty) VALUES
('seed-2026-09-10', 'ofertas deportivas',      'transaccional', 'transactional',  3600, 25),
('seed-2026-09-10', 'herramientas seo gratis', 'comercial',     'commercial',    12000, 35);

-- ----------------------------------------------------------------------------
-- Registro de la carga semilla
-- ----------------------------------------------------------------------------
INSERT INTO etl_run_log (run_id, started_at, finished_at, status, rows_extracted, rows_loaded, message) VALUES
(1, '2026-09-12T09:00:00Z', '2026-09-12T09:00:41Z', 'success', 49, 49, 'Carga semilla de demo (02_insert_sample_data.sql)');
