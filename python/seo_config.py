#!/usr/bin/env python3
# ============================================================================
# seo_config.py
# SEO Quick Wins — Data Product | Configuración central de rutas
#
# Rutas canónicas del proyecto (unificadas):
#   * Scripts Python  → C:\Users\LENOVO\Desktop\SCRIPTS PYTHON
#   * Bases de datos  → C:\Users\LENOVO\Desktop\BASES DE DATOS DE PRUEBAS
#
# Resolución del warehouse (prioridad):
#   1. Parámetro explícito (CLI: --db)
#   2. Variable de entorno SEO_DB_PATH
#   3. Ruta canónica: BASES DE DATOS DE PRUEBAS\seo_warehouse.db
#   4. Fallback local (seo_warehouse.db junto al script)
#
# Overrides opcionales por variable de entorno:
#   SEO_SCRIPTS_DIR, SEO_DATABASES_DIR, SEO_SQL_DIR
# ============================================================================

from __future__ import annotations

import os
from pathlib import Path

# --- Rutas canónicas del usuario (overrides permitidos) ---------------------
SCRIPTS_DIR = Path(
    os.environ.get("SEO_SCRIPTS_DIR", r"C:\Users\LENOVO\Desktop\SCRIPTS PYTHON")
)
DATABASES_DIR = Path(
    os.environ.get("SEO_DATABASES_DIR", r"C:\Users\LENOVO\Desktop\BASES DE DATOS DE PRUEBAS")
)

WAREHOUSE_DB = DATABASES_DIR / "seo_warehouse.db"


def _find_sql_dir() -> Path:
    """Localiza el directorio de scripts SQL (soporta ambos despliegues)."""
    env_dir = os.environ.get("SEO_SQL_DIR")
    candidates = [
        Path(env_dir) if env_dir else None,
        Path(__file__).resolve().parent / "sql",         # despliegue: SCRIPTS PYTHON/sql
        Path(__file__).resolve().parent.parent / "sql",  # checkout: <proyecto>/sql
    ]
    for cand in candidates:
        if cand and (cand / "01_create_tables.sql").exists():
            return cand
    return candidates[-1]


SQL_DIR = _find_sql_dir()


def resolve_db(explicit: str | Path | None = None) -> Path:
    """Resuelve la ruta del warehouse SQLite según la prioridad documentada."""
    if explicit:
        path = Path(explicit)
    else:
        env = os.environ.get("SEO_DB_PATH")
        if env:
            path = Path(env)
        else:
            try:
                DATABASES_DIR.mkdir(parents=True, exist_ok=True)
                return WAREHOUSE_DB
            except OSError:
                # Sin acceso a la carpeta canónica: fallback junto al script
                return Path(__file__).resolve().parent / "seo_warehouse.db"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path
