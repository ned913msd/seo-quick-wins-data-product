# SEO Quick Wins — Data Product

Producto de datos end-to-end que identifica y prioriza **quick wins de SEO** (oportunidades de mejora rápidas y de alto impacto) a partir de datos del sitio web, y los expone como vistas analíticas listas para consumir en dashboards.

## 🎯 Objetivo de negocio

Reducir el tiempo entre "detectar un problema de SEO" y "ejecutar la mejora", priorizando acciones por **impacto estimado de tráfico** vs. **esfuerzo de implementación**.

## 📊 Modelo de priorización (ICE)

Cada oportunidad se puntúa con la fórmula:

```
ICE = Impacto (1-10) × Confianza (1-10) × Facilidad (1-10) / 100
```

| Rango ICE | Prioridad | Acción sugerida |
|-----------|-----------|-----------------|
| ≥ 7.0 | 🔴 P1 — Crítica | Ejecutar esta semana |
| 4.0 – 6.9 | 🟠 P2 — Alta | Ejecutar este sprint |
| 2.0 – 3.9 | 🟡 P3 — Media | Backlog |
| < 2.0 | ⚪ P4 — Baja | Solo si sobra capacidad |

## 📁 Estructura del proyecto

```
seo-quick-wins-data-product/
│
├── README.md
│
├── sql/
│   ├── 01_create_tables.sql     # DDL: tablas core + staging
│   ├── 02_insert_sample_data.sql# Datos de ejemplo para demos y tests
│   ├── 03_create_views.sql      # Vistas analíticas de consumo
│   ├── 04_etl_pipeline.sql      # Procedimiento ETL SQL-only (fallback)
   ├── 05_analysis_queries.sql   # Queries de análisis ad-hoc
│
├── python/
│   ├── etl_seo_pipeline.py      # ETL principal (extract → transform → load)
│   └── requirements.txt
│
├── docs/
│   ├── business_case.md         # Caso de negocio y ROI
│   ├── data_dictionary.md       # Diccionario de datos completo
│   └── architecture.md          # Arquitectura y flujo de datos
│
└── images/
    ├── schema_diagram.png       # Diagrama ER del modelo
    ├── dashboard_preview.png    # Preview del dashboard de quick wins
    └── etl_flow.png             # Flujo del pipeline ETL
```

## 🚀 Inicio rápido

### Opción A — Solo SQL (PostgreSQL)

```bash
psql -U postgres -d seo_dw -f sql/01_create_tables.sql
psql -U postgres -d seo_dw -f sql/02_insert_sample_data.sql
psql -U postgres -d seo_dw -f sql/03_create_views.sql
```

### Opción B — Pipeline Python completo

```bash
cd python
pip install -r requirements.txt
python etl_seo_pipeline.py --full-refresh
```

Por defecto el ETL usa SQLite (`seo_warehouse.db`) para que funcione sin servidor de base de datos. Para PostgreSQL configura las variables `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER` y `PG_PASSWORD`.

### 🗂️ Despliegue unificado en este equipo

Los scripts y la base de datos viven en carpetas dedicadas del Escritorio:

| Recurso | Ruta |
|---------|------|
| Scripts Python + SQL | `C:\Users\LENOVO\Desktop\SCRIPTS PYTHON` |
| Warehouse SQLite | `C:\Users\LENOVO\Desktop\BASES DE DATOS DE PRUEBAS\seo_warehouse.db` |

```bash
# Ejecutar desde la carpeta de scripts (crea/actualiza y verifica el warehouse)
cd "C:\Users\LENOVO\Desktop\SCRIPTS PYTHON"
python etl_seo_pipeline.py --full-refresh --verify
```

Las rutas se configuran en `seo_config.py` y admiten overrides: `--db <ruta>` (CLI), `SEO_DB_PATH` (warehouse), `SEO_SCRIPTS_DIR` / `SEO_DATABASES_DIR` / `SEO_SQL_DIR` (carpetas). El proyecto sigue siendo portable: si la carpeta canónica no existe, el ETL cae a un `seo_warehouse.db` local junto al script.

## 🔍 Consultas clave

```sql
-- Top 10 quick wins priorizados
SELECT * FROM vw_quick_wins_priority LIMIT 10;

-- Resumen ejecutivo por categoría
SELECT * FROM vw_category_summary;

-- Tendencia de posiciones semana a semana
SELECT * FROM vw_position_trends;
```

## 📈 Métricas que responde el producto

- ¿Qué páginas tienen mayor pérdida de tráfico potencial?
- ¿Qué keywords estamos "casi ganando" (posiciones 4–15)?
- ¿Qué errores técnicos bloquean el indexado?
- ¿Dónde está el mayor ROI por hora de trabajo invertida?

## 🧪 Validación

```bash
cd python && pytest -v
```

## 📄 Licencia

MIT
