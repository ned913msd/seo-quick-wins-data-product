# Data Dictionary — SEO Quick Wins Data Product

Convenciones generales:

- Todas las fechas se almacenan como `TEXT` en formato **ISO 8601** (`YYYY-MM-DD`) para portabilidad entre PostgreSQL y SQLite.
- Los flags booleanos son `INTEGER` con dominio `{0, 1}`.
- Una **posición 0** en `fact_keyword_position` significa *no posiciona en el top 100*.
- La PK de cada tabla es sustituta (entero secuencial); las claves naturales se marcan con `UNIQUE`.

---

## Dimensiones

### `dim_site` — sitios web del portfolio

| Columna | Tipo | Nulo | Descripción |
|---------|------|------|-------------|
| `site_id` | INTEGER | No | PK |
| `domain` | TEXT | No | Dominio canónico, único (`tienda-demo.com`) |
| `site_name` | TEXT | No | Nombre legible del sitio |
| `language` | TEXT | No | Idioma principal (ISO 639-1). Default `es` |
| `country` | TEXT | No | País objetivo (ISO 3166-1). Default `ES` |
| `is_active` | INTEGER | No | `1` = sitio en scope del producto |

### `dim_keyword` — keywords trackeadas

| Columna | Tipo | Nulo | Descripción |
|---------|------|------|-------------|
| `keyword_id` | INTEGER | No | PK |
| `keyword` | TEXT | No | Keyword normalizada en minúsculas, única |
| `category` | TEXT | No | `transaccional` \| `comercial` \| `informativo` |
| `search_intent` | TEXT | No | Intent en inglés: `transactional` \| `commercial` \| `informational` |
| `monthly_search_volume` | INTEGER | No | Búsquedas mensuales medias. `>= 0` |
| `keyword_difficulty` | INTEGER | No | Dificultad SEO 0-100 (mayor = más difícil) |
| `current_url_target` | TEXT | Sí | URL que *debería* posicionar (para detectar canibalización) |

### `dim_page` — páginas conocidas

| Columna | Tipo | Nulo | Descripción |
|---------|------|------|-------------|
| `page_id` | INTEGER | No | PK |
| `site_id` | INTEGER | No | FK → `dim_site` |
| `url` | TEXT | No | URL absoluta, única |
| `title` | TEXT | Sí | `<title>` actual |
| `meta_description` | TEXT | Sí | Meta description actual |
| `h1` | TEXT | Sí | Primer H1 |
| `word_count` | INTEGER | Sí | Palabras indexables del contenido principal |
| `indexable` | INTEGER | No | `1` = indexable (robots, canonical y noindex OK). Default `1` |
| `page_speed_score` | INTEGER | Sí | Score Lighthouse 0-100 |
| `last_crawled_at` | TEXT | Sí | Fecha ISO del último crawl |

---

## Hechos

### `fact_keyword_position` — snapshot de posiciones (grano: keyword × página × fecha)

| Columna | Tipo | Nulo | Descripción |
|---------|------|------|-------------|
| `position_id` | INTEGER | No | PK |
| `keyword_id` | INTEGER | No | FK → `dim_keyword` |
| `page_id` | INTEGER | No | FK → `dim_page` |
| `snapshot_date` | TEXT | No | Fecha del snapshot. `UNIQUE(keyword_id, page_id, snapshot_date)` |
| `position` | INTEGER | No | Posición media en Google. **0 = no posiciona (top 100)** |
| `previous_position` | INTEGER | Sí | Posición del snapshot anterior (para deltas) |
| `clicks_30d` | INTEGER | No | Clicks en los últimos 30 días (GSC). Default `0` |
| `impressions_30d` | INTEGER | No | Impresiones en los últimos 30 días. Siempre `>= clicks_30d` |
| `ctr_30d` | REAL | Sí | CTR = `clicks_30d / impressions_30d`, dominio `[0, 1]` |

### `fact_technical_issue` — issues técnicos y de contenido

| Columna | Tipo | Nulo | Descripción |
|---------|------|------|-------------|
| `issue_id` | INTEGER | No | PK |
| `site_id` | INTEGER | No | FK → `dim_site` |
| `page_id` | INTEGER | Sí | FK → `dim_page`. **NULL = issue de todo el sitio** (p.ej. sitemap 404) |
| `issue_type` | TEXT | No | `noindex` \| `slow_lcp` \| `meta_description_missing` \| `content_decay` \| `canonical_conflict` \| `sitemap_404` \| `title_too_long` \| `stale_seasonal_content` \| `internal_links_broken` \| `image_alt_missing` |
| `severity` | TEXT | No | `critical` \| `high` \| `medium` \| `low` |
| `traffic_at_risk` | INTEGER | No | Visitas/mes estimadas en riesgo. Default `0` |
| `detected_at` | TEXT | No | Fecha ISO de detección |
| `resolved_at` | TEXT | Sí | Fecha ISO de resolución |
| `status` | TEXT | No | `open` \| `in_progress` \| `resolved` \| `wont_fix`. Default `open` |

### `fact_backlink` — backlinks por página (grano: página × dominio referente)

| Columna | Tipo | Nulo | Descripción |
|---------|------|------|-------------|
| `backlink_id` | INTEGER | No | PK |
| `page_id` | INTEGER | No | FK → `dim_page` |
| `referring_domain` | TEXT | No | Dominio del enlace entrante. `UNIQUE(page_id, referring_domain)` |
| `domain_authority` | INTEGER | Sí | Autoridad del dominio referente 0-100 |
| `link_type` | TEXT | Sí | `editorial` \| `directory` \| `forum` \| ... |
| `first_seen_at` | TEXT | Sí | Fecha ISO de primera detección |

---

## Staging (zona de aterrizaje del ETL)

### `stg_keywords_raw`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `load_id` | TEXT | Identificador del lote de carga |
| `keyword` | TEXT | Keyword tal cual llega de la fuente (sin normalizar) |
| `category` | TEXT | Categoría de negocio |
| `search_intent` | TEXT | Intent declarado por la fuente |
| `monthly_search_volume` | INTEGER | Volumen mensual |
| `keyword_difficulty` | INTEGER | Dificultad 0-100 |

### `stg_pages_raw`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `load_id` | TEXT | Identificador del lote |
| `url` | TEXT | URL del crawl |
| `title` | TEXT | `<title>` |
| `h1` | TEXT | Primer H1 |
| `word_count` | INTEGER | Palabras |
| `indexable` | INTEGER | Flag de indexabilidad (0/1) |
| `page_speed_score` | INTEGER | Score Lighthouse |
| `loaded_at` | TEXT | Timestamp ISO de la carga |

### `stg_positions_raw` (creada por `04_etl_pipeline.sql`)

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `load_id` | TEXT | Identificador del lote |
| `keyword` | TEXT | Keyword (se resuelve contra `dim_keyword`) |
| `url` | TEXT | URL (se resuelve contra `dim_page`) |
| `snapshot_date` | TEXT | Fecha del snapshot |
| `position` | INTEGER | Posición (0 = no posiciona) |

---

## Log operativo

### `etl_run_log`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `run_id` | INTEGER | PK |
| `started_at` | TEXT | Inicio del run (ISO) |
| `finished_at` | TEXT | Fin del run (NULL mientras corre) |
| `status` | TEXT | `running` \| `success` \| `failed` |
| `rows_extracted` | INTEGER | Filas leídas de las fuentes |
| `rows_loaded` | INTEGER | Filas efectivamente cargadas |
| `message` | TEXT | Nota libre (incluye errores de calidad si los hubo) |

---

## Vistas de consumo

| Vista | Grano | Uso principal |
|-------|-------|---------------|
| `vw_quick_wins_priority` | 1 fila por keyword × página activa (posiciones 4-30) | Backlog priorizado por ICE. Columnas clave: `ice_score`, `priority_tier` (P1 ≥ 7, P2 ≥ 4, P3 ≥ 2) |
| `vw_position_changes` | keyword × página × snapshot | Detección de decay/mejoras. `trend` ∈ {new, improved, declined, stable} |
| `vw_category_summary` | dominio × categoría | Mix de keywords, posición media, CTR por categoría |
| `vw_indexation_health` | página | Issues abiertos + tráfico en riesgo + velocidad por página |
| `vw_backlink_gaps` | página | Páginas que posicionan sin backlinks (oportunidad de link building) |
| `vw_executive_summary` | dominio | KPIs para dirección: páginas, keywords, top3/top10, clicks, issues |

### Métricas derivadas clave

- **ICE score** = `Impacto × Confianza × Facilidad / 100`, con Impacto = `1 + 9 × log10(volumen)/log10(100000)` (capado a 10), Confianza = `1 + 9 × (100 − dificultad)/100`, Facilidad = `1 + 9 × (31 − posición)/30`.
- **position_delta** = `previous_position − position` (positivo = mejora).
- **traffic_at_risk** = visitas mensuales que se perderían si el issue persiste.
- **health_score** (Q11 de análisis) = `50% score_posiciones + 30% page_speed + 20% (100 − penalización_issues)`.
