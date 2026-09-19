#!/usr/bin/env python3
# ============================================================================
# migrate_sqlite_to_duckdb.py
# SEO Quick Wins | Migración one-off: SQLite (legado) -> DuckDB (para dbt)
#
# Uso (con el venv del proyecto activo):
#   python migrate_sqlite_to_duckdb.py
#
# Notas:
#   * La BD SQLite legado completa vive en BASES DE DATOS DE PRUEBAS
#     (el archivo 'seo_data_product.db' suelto solo contiene raw_keywords).
#   * Override con la variable de entorno SEO_SQLITE_DB si cambia la ruta.
#   * El DuckDB resultante (seo_data_product.duckdb) queda en la raíz del
#     proyecto y NO se versiona (ver .gitignore).
# ============================================================================

import os
import sqlite3
import sys
from pathlib import Path

import duckdb
import pandas as pd  # <- faltaba en la versión original del tutorial

# Consolas Windows (cp1252): permitir imprimir emojis sin UnicodeEncodeError
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO_ROOT = Path(__file__).resolve().parent
SQLITE_DB = Path(
    os.environ.get(
        "SEO_SQLITE_DB",
        r"C:\Users\LENOVO\Desktop\BASES DE DATOS DE PRUEBAS\seo_data_product",
    )
)
DUCKDB_DB = REPO_ROOT / "seo_data_product.duckdb"

# Conectar a ambas bases de datos
sqlite_conn = sqlite3.connect(SQLITE_DB)
duckdb_conn = duckdb.connect(str(DUCKDB_DB))

# Migrar cada tabla
tables = ["dim_keyword", "dim_date", "fact_keyword_performance", "raw_keywords"]

for table in tables:
    print(f" Migrando {table}...")

    # Leer de SQLite
    df = pd.read_sql(f"SELECT * FROM {table}", sqlite_conn)

    # Escribir en DuckDB
    duckdb_conn.execute(f"DROP TABLE IF EXISTS {table}")
    duckdb_conn.execute(f"CREATE TABLE {table} AS SELECT * FROM df")

    print(f"✅ {table} migrada: {len(df)} registros")

# Verificar
print("\n🎯 Verificación en DuckDB:")
result = duckdb_conn.execute("SHOW TABLES").fetchall()
for table in result:
    count = duckdb_conn.execute(f"SELECT COUNT(*) FROM {table[0]}").fetchone()[0]
    print(f"  - {table[0]}: {count} registros")

sqlite_conn.close()
duckdb_conn.close()
print("\n✨ ¡Migración completada!")
