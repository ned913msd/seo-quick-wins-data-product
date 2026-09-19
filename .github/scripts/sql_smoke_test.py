#!/usr/bin/env python3
# ============================================================================
# sql_smoke_test.py
# SEO Quick Wins — Data Product | Smoke test de los scripts SQL (usado en CI)
#
# Ejecuta la cadena completa 01→05 sobre SQLite en memoria y verifica:
#   * que todos los scripts corren sin errores
#   * que el DDL crea las tablas y vistas esperadas
#   * que los datos semilla cargan en las cantidades correctas
#   * que el ETL SQL-only (04) produce efectos verificables
#   * que las queries de análisis (05) devuelven resultados coherentes
#
# Uso local:  python .github/scripts/sql_smoke_test.py
# Uso en CI:  lo invoca .github/workflows/ci.yml
# ============================================================================

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SQL_DIR = REPO_ROOT / "sql"

SCRIPTS = [
    "01_create_tables.sql",
    "02_insert_sample_data.sql",
    "03_create_views.sql",
    "04_etl_pipeline.sql",
    "05_analysis_queries.sql",
]

EXPECTED_TABLES = {
    "dim_site", "dim_keyword", "dim_page",
    "fact_keyword_position", "fact_technical_issue", "fact_backlink",
    "stg_keywords_raw", "stg_pages_raw",
    "etl_run_log",
}

EXPECTED_VIEWS = {
    "vw_quick_wins_priority", "vw_category_summary", "vw_executive_summary",
    "vw_indexation_health", "vw_position_changes", "vw_backlink_gaps",
}


def check(name: str, condition: bool, detail: str) -> bool:
    status = "PASS" if condition else "FAIL"
    print(f"  [{status}] {name} ({detail})")
    return condition


def main() -> int:
    if not SQL_DIR.is_dir():
        print(f"ERROR: no existe el directorio SQL: {SQL_DIR}")
        return 1

    con = sqlite3.connect(":memory:")
    ok = True

    # --- 1. Ejecutar la cadena completa 01→05 -------------------------------
    print("== Ejecución de scripts SQL (SQLite en memoria) ==")
    for script in SCRIPTS:
        path = SQL_DIR / script
        try:
            con.executescript(path.read_text(encoding="utf-8"))
            con.commit()
            print(f"  [OK]   {script}")
        except sqlite3.Error as exc:
            print(f"  [FAIL] {script}: {exc}")
            con.close()
            return 1

    # --- 2. DDL: tablas y vistas esperadas ----------------------------------
    print("== DDL: tablas y vistas ==")
    tables = {r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table'")}
    views = {r[0] for r in con.execute(
        "SELECT name FROM sqlite_master WHERE type = 'view'")}
    ok &= check("tablas core presentes",
                EXPECTED_TABLES <= tables,
                f"faltan: {sorted(EXPECTED_TABLES - tables) or 'ninguna'}")
    ok &= check("vistas analíticas presentes",
                EXPECTED_VIEWS <= views,
                f"faltan: {sorted(EXPECTED_VIEWS - views) or 'ninguna'}")

    # --- 3. Datos semilla en cantidades esperadas ---------------------------
    print("== Datos semilla (02) ==")
    expected_counts = {
        "dim_site": 2,
        "dim_keyword": 10,
        "dim_page": 10,
        "fact_keyword_position": 12,
        "fact_backlink": 7,
    }
    for table, n in expected_counts.items():
        actual = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        ok &= check(f"{table} = {n}", actual == n, f"{actual} filas")

    # --- 4. ETL SQL-only (04): efectos verificables -------------------------
    print("== ETL SQL-only (04) ==")
    status, msg = con.execute(
        "SELECT status, message FROM etl_run_log "
        "ORDER BY run_id DESC LIMIT 1").fetchone()
    ok &= check("run del ETL en 'success'", status == "success", f"status={status!r}")
    ok &= check("mensaje de cierre", msg == "ETL SQL-only completado", f"msg={msg!r}")

    # El semillero deja staging (2+2 filas) y el ETL debe haber respetado las
    # claves naturales: las 2 keywords del staging ya existen en dim_keyword,
    # así que no se duplican; dim_page recibe updates, no inserts nuevos.
    n_kw = con.execute("SELECT COUNT(*) FROM dim_keyword").fetchone()[0]
    ok &= check("sin duplicados de keywords", n_kw == 10, f"{n_kw} filas")
    n_pg = con.execute("SELECT COUNT(*) FROM dim_page").fetchone()[0]
    ok &= check("sin duplicados de páginas", n_pg == 10, f"{n_pg} filas")

    # Update de página existente desde staging: post-viejo sigue en 800 palabras
    wc = con.execute(
        "SELECT word_count FROM dim_page WHERE url = "
        "'https://blog-demo.com/post-viejo'").fetchone()[0]
    ok &= check("update staging aplicado (word_count=800)", wc == 800, f"wc={wc}")

    # Los 'detected_at' de issues nuevos deben ser fechas reales, no 'now'
    bad_dates = con.execute(
        "SELECT COUNT(*) FROM fact_technical_issue "
        "WHERE detected_at = 'now'").fetchone()[0]
    ok &= check("detected_at con fecha real", bad_dates == 0, f"{bad_dates} inválidos")

    # --- 5. Queries de análisis (05) coherentes ------------------------------
    print("== Queries de análisis (05) ==")
    # Q1: la query estrella debe devolver quick wins con ICE > 0
    rows = con.execute(
        "SELECT COUNT(*), MAX(ice_score) FROM vw_quick_wins_priority").fetchone()
    ok &= check("Q1 vw_quick_wins_priority con resultados",
                rows[0] > 0 and (rows[1] or 0) > 0,
                f"{rows[0]} filas, ICE máx={rows[1]}")

    # Q2: casi-ganando (pos 4-10, vol>=2000) en el último snapshot
    n = con.execute(
        "SELECT COUNT(*) FROM fact_keyword_position f "
        "JOIN dim_keyword k ON k.keyword_id = f.keyword_id "
        "WHERE f.snapshot_date = (SELECT MAX(snapshot_date) FROM fact_keyword_position) "
        "AND f.position BETWEEN 4 AND 10 AND k.monthly_search_volume >= 2000"
    ).fetchone()[0]
    ok &= check("Q2 casi-ganando detectados", n >= 1, f"{n} keywords")

    # Q3: decay (position sube respecto a previous) presente en el semillero
    n = con.execute(
        "SELECT COUNT(*) FROM fact_keyword_position "
        "WHERE position - previous_position >= 3 "
        "AND snapshot_date = (SELECT MAX(snapshot_date) FROM fact_keyword_position)"
    ).fetchone()[0]
    ok &= check("Q3 decay detectado", n >= 1, f"{n} keywords en decay")

    # Q10: resumen ejecutivo accesible
    cols = [r[1] for r in con.execute("PRAGMA table_info(vw_executive_summary)")]
    ok &= check("Q10 vw_executive_summary usable", len(cols) > 0,
                f"{len(cols)} columnas")

    con.close()

    print()
    if ok:
        print("SMOKE TEST OK — todos los checks en PASS")
        return 0
    print("SMOKE TEST FALLIDO — hay checks en FAIL")
    return 1


if __name__ == "__main__":
    sys.exit(main())
