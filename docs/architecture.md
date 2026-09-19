# Architecture — SEO Quick Wins Data Product

## 1. Visión general

```
┌─────────────────────────┐   ┌─────────────────────────┐   ┌──────────────────────────┐
│         FUENTES         │   │        PIPELINE         │   │         CONSUMO          │
│                         │   │                         │   │                          │
│  Google Search Console  │──▶│  EXTRACT                │   │  Vistas semánticas       │
│  (exports CSV / API)    │   │    ├── keywords.csv     │   │   ├── vw_quick_wins_*    │
│                         │   │    ├── pages.csv        │   │   ├── vw_position_*      │
│  Crawler (Screaming     │──▶│    └── positions.csv    │   │   └── vw_executive_*     │
│  Frog / Sitebulb)       │   │                         │   │                          │
│                         │   │  TRANSFORM              │   │  Queries ad-hoc          │
│  Keyword tools          │──▶│    ├── validación       │   │  (05_analysis_queries)   │
│  (Ahrefs / Semrush)     │   │    ├── normalización    │   │                          │
│                         │   │    └── deduplicación    │   │  Dashboards              │
│  Seed demo dataset      │──▶│                         │   │  (Looker Studio/Metabase)│
│  (--full-refresh)       │   │  LOAD                   │   │                          │
│                         │   │    ├── SQLite (default) │   │  Jupyter / notebooks     │
│                         │   │    └── PostgreSQL (opt) │   │                          │
└─────────────────────────┘   └─────────────────────────┘   └──────────────────────────┘
```

## 2. Capas del modelo (arquitectura medallion simplificada)

| Capa | Objetos | Responsabilidad |
|------|---------|-----------------|
| **Landing / Staging** | `stg_keywords_raw`, `stg_pages_raw`, `stg_positions_raw` | Copia fiel de la fuente, con `load_id` para trazabilidad. Sin transformaciones |
| **Core (dimensional)** | `dim_site`, `dim_keyword`, `dim_page` + `fact_keyword_position`, `fact_technical_issue`, `fact_backlink` | Modelo estrella. Historial de posiciones por snapshot |
| **Semantic (vistas)** | `vw_*` (6 vistas) | Reglas de negocio: ICE, decay, salud de indexación. Único punto de consumo |

**Regla de oro**: las reglas de negocio viven en la capa semántica (vistas), nunca en los dashboards. Así el KPI "quick win" significa lo mismo en Metabase, en Jupyter y en el informe mensual.

## 3. Pipeline ETL

### 3.1 Modos de ejecución

| Modo | Comando | Cuándo usarlo |
|------|---------|---------------|
| Demo (seed determinista) | `python etl_seo_pipeline.py --full-refresh` | Onboarding, tests, demos |
| CSV reales | `python etl_seo_pipeline.py --csv-dir ./exports` | Ingesta semanal manual |
| Solo verificación | `python etl_seo_pipeline.py --verify` | Post-carga / CI |

### 3.2 Contratos y calidad de datos

La capa `transform()` valida:

- **Keywords**: no vacías, `difficulty ∈ [0,100]`, `volume ≥ 0`, categoría conocida.
- **Páginas**: URL absoluta `http(s)`, `word_count ≥ 0`, `page_speed ∈ [0,100]`.
- **Posiciones**: `position ≥ 0`, integridad referencial (keyword y URL deben existir), `impressions ≥ clicks`, CTR recalculado en carga.
- Deduplicación por clave natural antes de insertar (upsert idempotente: recargar el mismo CSV no duplica filas).

Las filas inválidas **no bloquean el pipeline**: se descartan y se reportan en el log (`etl_run_log.message`).

### 3.3 Fallback SQL-only

`sql/04_etl_pipeline.sql` implementa el mismo flujo (staging → core + reglas de negocio automáticas) en SQL puro, para entornos sin Python o para ejecutarlo dentro del motor (p.ej. con `psql` en cron). Ambos caminos producen el mismo estado en el core.

## 4. Decisiones técnicas (ADRs resumidos)

| # | Decisión | Alternativa descartada | Motivo |
|---|----------|------------------------|--------|
| 1 | SQLite por defecto, PostgreSQL opcional vía `PG_HOST` | Solo PostgreSQL | Cero fricción para probar el producto; PG disponible para escala |
| 2 | SQL portable (sin dialecto) con `TEXT` para fechas | Tipos `DATE` nativos | Los mismos scripts corren en SQLite y PostgreSQL |
| 3 | Modelo ICE sobre fórmula simple logarítmica | ML de predicción de tráfico | Interpretable y defendible en negocio; ML queda para fase 3 |
| 4 | Vistas en vez de tablas materializadas | Tablas `mart_*` | Datos pequeños (miles de filas); las vistas evitan refrescos y divergencia |
| 5 | Staging con `load_id` en vez de CDC | Debezium / CDC | Simplicidad: la fuente es un export batch, no un stream |
| 6 | Idempotencia por clave natural (upsert anti-join) | `MERGE` nativo | `MERGE` no es portable; el anti-join funciona igual en ambos motores |
| 7 | Rutas canónicas centralizadas en `seo_config.py` (BD en `Desktop\BASES DE DATOS DE PRUEBAS`, scripts en `Desktop\SCRIPTS PYTHON`) | Rutas relativas al proyecto | Entorno unificado del usuario; overrides por CLI (`--db`) y variables de entorno (`SEO_*`) conservan la portabilidad |

## 5. Operación

### 5.1 Frecuencia y SLA

- **Carga**: semanal (los rankings no cambian intradía de forma relevante para el modelo).
- **Ventana**: madrugada del lunes; duración esperada < 2 min con dataset de ~50k filas.
- **SLA de frescura**: datos ≤ 8 días. El check `--verify` forma parte del runbook post-carga.

### 5.2 Monitoreo

- `etl_run_log`: estado, duración y filas por run; alertar si `status = 'failed'` o `rows_extracted` cae > 50% intersemanal.
- `--verify` como gate: CTR fuera de dominio, huérfanas, flags binarios.

### 5.3 Escalado posterior

1. **Ingesta automática** via API de GSC + crawler en CI → sustituye los CSV.
2. **PostgreSQL gestionado** (Cloud SQL / RDS) cuando el histórico supere ~1M filas.
3. **dbt** para gestionar la capa semántica si el número de vistas/modelos crece.
4. **Orquestador** (Airflow/Prefect/Dagster) si se añaden más fuentes y dependencias.

## 6. Seguridad y gobernanza

- Sin PII: los datos son públicos (posiciones, URLs, volúmenes). No se almacenan queries de usuarios.
- Credenciales de base de datos por variables de entorno (`PG_*`), nunca en el repo. Soporte opcional de `.env` via `python-dotenv`.
- Acceso de lectura para consumo vía vistas; escritura solo para el rol del ETL.
