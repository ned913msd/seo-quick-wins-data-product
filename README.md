# 🚀 SEO Quick Wins Engine | Data Product

[![CI](https://github.com/ned913msd/seo-quick-wins-data-product/actions/workflows/ci.yml/badge.svg)](https://github.com/ned913msd/seo-quick-wins-data-product/actions/workflows/ci.yml)
[![SQL](https://img.shields.io/badge/SQL-Advanced-blue)](https://www.sqlite.org/)
[![Python](https://img.shields.io/badge/Python-3%2B-green)](https://www.python.org/)
[![ETL](https://img.shields.io/badge/ETL-Automated-orange)]()

## 🎯 El Problema de Negocio

Los equipos de SEO y Marketing Digital pierden **horas semanales** analizando hojas de cálculo masivas con miles de keywords, dificultando la identificación rápida de oportunidades de crecimiento ("Quick Wins") que requieren poco esfuerzo técnico pero generan **alto impacto en tráfico orgánico**.

**Pregunta de negocio:** ¿Cómo podemos automatizar la identificación de keywords con mayor ROI potencial en menos de 5 minutos?

---

## 💡 La Solución (Data Product)

Desarrollé un **Data Product end-to-end** que combina:

- **Python ETL Pipeline** para extracción, validación y carga automatizada de datos (con checks de calidad)
- **Modelado Dimensional** (Star Schema) para consultas optimizadas
- **SQL Avanzado** (CTEs, Window Functions) para análisis complejo
- **Vistas Inteligentes** con lógica de negocio embebida (modelo de priorización **ICE**)
- **CI/CD** con GitHub Actions: cada push ejecuta el ETL y un smoke test de toda la cadena SQL

**Resultado:** Un sistema que procesa 1,000+ keywords en segundos y clasifica automáticamente las oportunidades por:

- 🎯 **Quick Wins** — keywords en posiciones 4–30 priorizadas por ICE (Impacto × Confianza × Facilidad)
- ✅ **Ya Posicionados** — keywords en Top 3 (visibles en el resumen ejecutivo)
- ⚠️ **Necesita Trabajo / Riesgo** — decays de contenido y páginas con noindex que siguen recibiendo tráfico

---

## 🛠️ Stack Tecnológico

| Categoría | Tecnologías |
|-----------|-------------|
| **Base de Datos** | SQLite / PostgreSQL (Modelo Estrella) |
| **ETL & Automatización** | Python (CLI con validación de datos) |
| **Análisis** | SQL Avanzado (CTEs, Window Functions) |
| **Visualización** | DBeaver + Vistas SQL (ready para Power BI/Tableau) |
| **CI/CD** | GitHub Actions |
| **Control de Versiones** | Git/GitHub |

---

## 🏗️ Arquitectura del Producto

```
 [CSV / GSC exports]      [Python ETL]           [Star Schema]        [Business Views]      [Dashboard / BI]
        │                      │                       │                     │                     │
   Extracción  ──────▶  Limpieza + Data  ──────▶  dim_keyword          vw_quick_wins_       Power BI /
   (keywords,           Quality + carga   (dim_page,            priority (ICE)       Tableau /
   páginas,             idempotente       dim_site,             vw_position_         DBeaver
   posiciones)          (SQLite / PG)     fact_keyword_         changes              (conceptual)
                                          position,             vw_executive_
                                          fact_technical_       summary
                                          issue)                       ▲
                                                │                      │
                                                └── Fallback 100% SQL: 04_etl_pipeline.sql (sin Python)
```

---

## 📈 KPIs del Producto

| Métrica | Valor | Impacto |
|---------|-------|---------|
| **Tiempo de Análisis** | De 4 horas → 5 minutos | **98% reducción** |
| **Keywords Procesadas** | 1,000+ en segundos | Escalabilidad total |
| **Quick Wins Identificadas** | Priorización automática (modelo ICE, niveles P1–P4) | ROI inmediato |
| **Calidad de Datos** | 5 checks automáticos + 16 aserciones SQL en CI | Decisiones confiables |

---

## 🚀 Cómo Usar Este Data Product

### Prerrequisitos

```bash
pip install -r python/requirements.txt
```

### Instalación y Ejecución

1. **Clonar el repositorio:**

```bash
git clone https://github.com/ned913msd/seo-quick-wins-data-product.git
cd seo-quick-wins-data-product
```

2. **Ejecutar el pipeline ETL** (crea el warehouse y ejecuta los checks de calidad):

```bash
python python/etl_seo_pipeline.py --full-refresh --verify
```

3. **Abrir la base de datos en DBeaver:**

   - Conectar a `seo_warehouse.db` (se genera al ejecutar el pipeline)
   - Explorar las vistas del esquema en `sql/03_create_views.sql`

4. **Consultar resultados:**

```sql
-- Top 10 quick wins priorizados por ICE
SELECT keyword, url, position, monthly_search_volume,
       ROUND(ice_score, 2) AS ice, priority_tier
FROM vw_quick_wins_priority
ORDER BY ice_score DESC
LIMIT 10;

-- Resumen ejecutivo: 1 fila por dominio con KPIs agregados
SELECT * FROM vw_executive_summary;

-- Solo las oportunidades P1 (críticas)
SELECT keyword, url, ice_score
FROM vw_quick_wins_priority
WHERE priority_tier = 'P1 - Critical'
ORDER BY ice_score DESC;
```

---

## 🎓 Aprendizajes Clave

### 1. Hacerlo (Engineering)

- Pipeline ETL automatizado en Python con validación de contratos de datos (nulos, rangos, huérfanos)
- Carga idempotente por clave natural (upserts anti-join) con staging y `load_id` para trazabilidad
- Modelo dimensional optimizado para consultas analíticas (SQLite y PostgreSQL con el mismo SQL)

### 2. Entenderlo (Analytics)

- Definición del modelo de priorización **ICE**: Impacto (volumen logarítmico) × Confianza (keyword difficulty) × Facilidad (posición actual)
- Detección automática de decays de contenido (≥ 5 posiciones perdidas) y noindex con tráfico en riesgo
- Segmentación por intención de búsqueda y categoría

### 3. Explicarlo (Product)

- Vistas SQL que traducen datos crudos en insights accionables (`vw_quick_wins_priority`, `vw_executive_summary`)
- Priorización automática (P1–P4) que elimina el análisis manual de spreadsheets
- Caso de negocio documentado con ROI y arquitectura lista para exponer a stakeholders

---

## 📁 Estructura del Proyecto

```
seo-quick-wins-data-product/
├── sql/
│   ├── 01_create_tables.sql           # Creación del esquema estrella + staging
│   ├── 02_insert_sample_data.sql      # Datos de prueba (demos y smoke tests)
│   ├── 03_create_views.sql            # Vistas de negocio (vw_quick_wins_priority, ...)
│   ├── 04_etl_pipeline.sql            # ETL 100% SQL (fallback sin Python)
│   └── 05_analysis_queries.sql        # Consultas analíticas ad-hoc
│
├── python/
│   ├── etl_seo_pipeline.py            # Pipeline ETL automatizado (CLI)
│   ├── seo_config.py                  # Configuración central de rutas
│   └── requirements.txt               # Dependencias
│
├── docs/
│   ├── business_case.md               # Caso de negocio completo
│   ├── data_dictionary.md             # Diccionario de datos
│   └── architecture.md                # Arquitectura y decisiones (ADRs)
│
├── images/
│   ├── schema_diagram.png             # Diagrama ER del modelo
│   ├── dashboard_preview.png          # Preview del dashboard
│   └── etl_flow.png                   # Flujo del pipeline
│
├── .github/
│   ├── workflows/ci.yml               # CI: ETL + verify + smoke test SQL
│   └── scripts/sql_smoke_test.py      # 16 aserciones sobre la cadena SQL 01→05
│
└── README.md                          # Este archivo
```

---

## 💪 Competencias Demostradas

Este proyecto demuestra habilidades de Analytics Engineer y Data Product Manager:

- ✅ **SQL Avanzado:** CTEs, Window Functions (`ROW_NUMBER`), JOINs complejos, upserts portables
- ✅ **Modelado de Datos:** Esquema Estrella (Star Schema), capas staging → core → vistas
- ✅ **Python ETL:** Extracción, transformación y carga automatizada con CLI (`--full-refresh`, `--verify`, `--csv-dir`)
- ✅ **Data Quality:** Contratos de datos, validación en Transform y 5 checks post-carga
- ✅ **CI/CD:** GitHub Actions ejecutando ETL + smoke test en cada push
- ✅ **Business Intelligence:** KPIs, métricas de ROI, priorización ICE
- ✅ **Product Thinking:** De problema de negocio → solución técnica → valor medible

---

## 👤 Sobre el Autor

**David NED Bustamante**

📧 ned913msd@gmail.com
🔗 LinkedIn — *(añade aquí tu URL)*
📍 Medellín, Colombia

**Data Product Manager | Analytics Engineer | Full Stack Developer**

Especializado en construir productos de datos que generan valor de negocio. Combino habilidades técnicas (SQL, Python, Full Stack) con visión de producto (UX-UI, Marketing Digital, SEO) para crear soluciones que los usuarios realmente adoptan.

---

## 📄 Licencia

Este proyecto es open-source y está disponible bajo la licencia MIT.

*Proyecto desarrollado como parte del portafolio profesional para roles de Data Product Manager y Analytics Engineer.*
