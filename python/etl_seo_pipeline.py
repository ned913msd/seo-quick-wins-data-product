#!/usr/bin/env python3
# ============================================================================
# etl_seo_pipeline.py
# SEO Quick Wins — Data Product | ETL principal
#
# Pipeline: EXTRACT (CSV/seed) -> TRANSFORM (validación + reglas de negocio)
#           -> LOAD (SQLite por defecto, PostgreSQL opcional)
#
# Uso:
#   python etl_seo_pipeline.py --full-refresh          # carga dataset semilla
#   python etl_seo_pipeline.py --csv-dir ./exports     # carga desde CSVs
#   python etl_seo_pipeline.py --verify                # ejecuta checks de calidad
#
# Variables de entorno:
#   SEO_DB_PATH → ruta del warehouse SQLite (opcional; ver seo_config.py)
#   PG_HOST, PG_PORT, PG_DB, PG_USER, PG_PASSWORD → PostgreSQL opcional
# ============================================================================

from __future__ import annotations

import argparse
import csv
import logging
import os
import random
import sqlite3
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable, Iterator, Sequence

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("etl_seo")

from seo_config import SQL_DIR, resolve_db

# Ruta canónica: BASES DE DATOS DE PRUEBAS\seo_warehouse.db
# (configuración central en seo_config.py; override con --db o SEO_DB_PATH)
DEFAULT_DB = resolve_db()

# ----------------------------------------------------------------------------
# Contratos de datos (validación en la capa Transform)
# ----------------------------------------------------------------------------

@dataclass
class KeywordRow:
    keyword: str
    category: str
    search_intent: str
    monthly_search_volume: int
    keyword_difficulty: int

    def validate(self) -> list[str]:
        errors: list[str] = []
        if not self.keyword or not self.keyword.strip():
            errors.append("keyword vacía")
        if self.monthly_search_volume < 0:
            errors.append(f"volumen negativo: {self.monthly_search_volume}")
        if not 0 <= self.keyword_difficulty <= 100:
            errors.append(f"difficulty fuera de rango: {self.keyword_difficulty}")
        if self.category not in {"transaccional", "comercial", "informativo"}:
            errors.append(f"categoría desconocida: {self.category}")
        return errors


@dataclass
class PageRow:
    url: str
    title: str | None
    h1: str | None
    word_count: int
    indexable: int
    page_speed_score: int | None

    def validate(self) -> list[str]:
        errors: list[str] = []
        if not self.url or not self.url.startswith(("http://", "https://")):
            errors.append(f"URL inválida: {self.url!r}")
        if self.word_count < 0:
            errors.append(f"word_count negativo: {self.word_count}")
        if self.page_speed_score is not None and not 0 <= self.page_speed_score <= 100:
            errors.append(f"page_speed_score fuera de rango: {self.page_speed_score}")
        return errors


@dataclass
class PositionRow:
    keyword: str
    url: str
    snapshot_date: str
    position: int
    previous_position: int | None
    clicks_30d: int = 0
    impressions_30d: int = 0

    def validate(self) -> list[str]:
        errors: list[str] = []
        if self.position < 0:
            errors.append(f"posición negativa: {self.position}")
        if not self.snapshot_date:
            errors.append("snapshot_date vacío")
        return errors


@dataclass
class ExtractResult:
    keywords: list[KeywordRow] = field(default_factory=list)
    pages: list[PageRow] = field(default_factory=list)
    positions: list[PositionRow] = field(default_factory=list)


# ----------------------------------------------------------------------------
# EXTRACT
# ----------------------------------------------------------------------------

def extract_from_csv(csv_dir: Path) -> ExtractResult:
    """Lee keywords.csv, pages.csv y positions.csv del directorio dado."""
    result = ExtractResult()

    kw_path = csv_dir / "keywords.csv"
    if kw_path.exists():
        with kw_path.open(encoding="utf-8") as f:
            for row in csv.DictReader(f):
                result.keywords.append(KeywordRow(
                    keyword=row["keyword"].strip(),
                    category=row.get("category", "informativo").strip(),
                    search_intent=row.get("search_intent", "informational").strip(),
                    monthly_search_volume=int(row.get("monthly_search_volume", 0) or 0),
                    keyword_difficulty=int(row.get("keyword_difficulty", 50) or 50),
                ))

    pg_path = csv_dir / "pages.csv"
    if pg_path.exists():
        with pg_path.open(encoding="utf-8") as f:
            for row in csv.DictReader(f):
                result.pages.append(PageRow(
                    url=row["url"].strip(),
                    title=row.get("title"),
                    h1=row.get("h1"),
                    word_count=int(row.get("word_count", 0) or 0),
                    indexable=int(row.get("indexable", 1) or 0),
                    page_speed_score=int(row["page_speed_score"]) if row.get("page_speed_score") else None,
                ))

    pos_path = csv_dir / "positions.csv"
    if pos_path.exists():
        with pos_path.open(encoding="utf-8") as f:
            for row in csv.DictReader(f):
                result.positions.append(PositionRow(
                    keyword=row["keyword"].strip(),
                    url=row["url"].strip(),
                    snapshot_date=row["snapshot_date"].strip(),
                    position=int(row.get("position", 0) or 0),
                    previous_position=int(row["previous_position"]) if row.get("previous_position") else None,
                    clicks_30d=int(row.get("clicks_30d", 0) or 0),
                    impressions_30d=int(row.get("impressions_30d", 0) or 0),
                ))

    log.info(
        "EXTRACT csv-dir=%s keywords=%d pages=%d positions=%d",
        csv_dir, len(result.keywords), len(result.pages), len(result.positions),
    )
    return result


def extract_seed() -> ExtractResult:
    """
    Dataset semilla determinista (modo demo / --full-refresh sin CSVs).
    Simula un export de GSC + crawler con 12 keywords y 10 páginas.
    """
    rng = random.Random(42)  # determinista: misma semilla, mismos datos

    keywords = [
        KeywordRow("zapatillas running",              "transaccional", "transactional", 14800, 45),
        KeywordRow("zapatillas running hombre",       "transaccional", "transactional",  8100, 40),
        KeywordRow("mejores zapatillas running 2026", "comercial",     "commercial",     6600, 52),
        KeywordRow("como elegir zapatillas running",  "informativo",   "informational",  5400, 30),
        KeywordRow("auriculares bluetooth",           "transaccional", "transactional", 22200, 60),
        KeywordRow("ofertas deportivas",              "transaccional", "transactional",  3600, 25),
        KeywordRow("black friday deportivo",          "transaccional", "transactional",  9900, 48),
        KeywordRow("auditoria seo",                   "informativo",   "informational",  4400, 38),
        KeywordRow("seo tecnico",                     "informativo",   "informational",  2900, 42),
        KeywordRow("herramientas seo gratis",         "comercial",     "commercial",    12000, 35),
        KeywordRow("zapatillas para correr",          "transaccional", "transactional",  6100, 44),
        KeywordRow("guia de running para principiantes", "informativo","informational",  3300, 22),
    ]

    pages = [
        PageRow("https://tienda-demo.com/", "Zapatillas y ropa deportiva | Tienda Demo", "Deporte para todos", 850, 1, 72),
        PageRow("https://tienda-demo.com/zapatillas-running", "Zapatillas running | Tienda Demo", "Zapatillas running", 1200, 1, 65),
        PageRow("https://tienda-demo.com/zapatillas-running-hombre", "Zapatillas running hombre | Tienda Demo", "Zapatillas running para hombre", 950, 1, 61),
        PageRow("https://tienda-demo.com/auriculares", "Auriculares | Tienda Demo", "Auriculares", 700, 1, 58),
        PageRow("https://tienda-demo.com/blog/como-elegir-zapatillas-running", "Cómo elegir zapatillas running: guía 2026", "Cómo elegir zapatillas de running", 2100, 1, 80),
        PageRow("https://tienda-demo.com/ofertas", "Ofertas | Tienda Demo", "Ofertas de la semana", 300, 0, 45),  # noindex accidental
        PageRow("https://tienda-demo.com/landing-black-friday-2024", "Black Friday 2024 | Tienda Demo", "Black Friday 2024", 450, 1, 55),
        PageRow("https://blog-demo.com/seo-tecnico", "Guía de SEO técnico para 2026", "SEO técnico: la guía definitiva", 1800, 1, 77),
        PageRow("https://blog-demo.com/audit-seo", "Cómo hacer una auditoría SEO paso a paso", "Auditoría SEO paso a paso", 2400, 1, 74),
        PageRow("https://blog-demo.com/post-viejo", "10 herramientas SEO de 2021", "10 herramientas SEO", 800, 1, 50),  # decay
    ]

    today = datetime.now(timezone.utc).date()
    d_prev = (today - timedelta(days=7)).isoformat()
    d_now = today.isoformat()

    # (keyword, url, pos_prev, pos_now, clicks, impressions)
    raw_positions = [
        ("zapatillas running",              "https://tienda-demo.com/zapatillas-running",  14, 11, 210, 6200),
        ("zapatillas running hombre",       "https://tienda-demo.com/zapatillas-running-hombre", 12,  9, 340, 5100),
        ("mejores zapatillas running 2026", "https://tienda-demo.com/blog/como-elegir-zapatillas-running", 9, 14, 95, 3100),
        ("como elegir zapatillas running",  "https://tienda-demo.com/blog/como-elegir-zapatillas-running", 4,  3, 480, 4100),
        ("auriculares bluetooth",           "https://tienda-demo.com/auriculares", 16, 18, 60, 4400),
        ("ofertas deportivas",              "https://tienda-demo.com/ofertas",      0,  0,   0,  300),
        ("black friday deportivo",          "https://tienda-demo.com/landing-black-friday-2024", 21, 27, 30, 900),
        ("auditoria seo",                   "https://blog-demo.com/audit-seo",      6,  6, 390, 5200),
        ("seo tecnico",                     "https://blog-demo.com/seo-tecnico",    5,  7, 260, 3900),
        ("herramientas seo gratis",         "https://blog-demo.com/post-viejo",     8, 16, 70, 3400),
        ("zapatillas para correr",          "https://tienda-demo.com/zapatillas-running", 19, 15, 110, 2800),
        ("guia de running para principiantes", "https://tienda-demo.com/blog/como-elegir-zapatillas-running", 24, 20, 45, 1600),
    ]

    positions = [
        PositionRow(kw, url, d_now, pos_now, pos_prev,
                    clicks + rng.randint(-10, 10), impressions + rng.randint(-100, 100))
        for kw, url, pos_prev, pos_now, clicks, impressions in raw_positions
    ]

    log.info("EXTRACT seed keywords=%d pages=%d positions=%d", len(keywords), len(pages), len(positions))
    return ExtractResult(keywords=keywords, pages=pages, positions=positions)


# ----------------------------------------------------------------------------
# TRANSFORM
# ----------------------------------------------------------------------------

def transform(data: ExtractResult) -> tuple[ExtractResult, list[str]]:
    """
    Valida contratos y aplica reglas de negocio:
      * deduplicación por clave natural
      * normalización (trim, lower en keywords)
      * descarte de filas inválidas con reporte
    Devuelve (datos_limpios, lista_de_errores_descartados).
    """
    errors: list[str] = []
    clean = ExtractResult()

    # Keywords: normalizar + deduplicar
    seen_kw: set[str] = set()
    for kw in data.keywords:
        kw.keyword = kw.keyword.strip().lower()
        errs = kw.validate()
        if errs:
            errors.append(f"keyword {kw.keyword!r}: {'; '.join(errs)}")
            continue
        if kw.keyword in seen_kw:
            continue
        seen_kw.add(kw.keyword)
        clean.keywords.append(kw)

    # Pages: deduplicar por URL
    seen_url: set[str] = set()
    for pg in data.pages:
        pg.url = pg.url.strip()
        errs = pg.validate()
        if errs:
            errors.append(f"page {pg.url!r}: {'; '.join(errs)}")
            continue
        if pg.url in seen_url:
            continue
        seen_url.add(pg.url)
        clean.pages.append(pg)

    # Positions: validar + descartar las que referencian entidades inexistentes
    url_set = {p.url for p in clean.pages}
    kw_set = {k.keyword for k in clean.keywords}
    seen_pos: set[tuple[str, str, str]] = set()
    for pos in data.positions:
        pos.keyword = pos.keyword.strip().lower()
        pos.url = pos.url.strip()
        errs = pos.validate()
        if errs:
            errors.append(f"position {pos.keyword!r}@{pos.url!r}: {'; '.join(errs)}")
            continue
        if pos.keyword not in kw_set:
            errors.append(f"position huérfana (keyword desconocida): {pos.keyword!r}")
            continue
        if pos.url not in url_set:
            errors.append(f"position huérfana (url desconocida): {pos.url!r}")
            continue
        key = (pos.keyword, pos.url, pos.snapshot_date)
        if key in seen_pos:
            continue
        seen_pos.add(key)
        if pos.clicks_30d < 0:
            pos.clicks_30d = 0
        if pos.impressions_30d < pos.clicks_30d:
            pos.impressions_30d = pos.clicks_30d  # coherencia: impresiones >= clicks
        if pos.impressions_30d > 0:
            pos_ctr = pos.clicks_30d / pos.impressions_30d
        else:
            pos_ctr = 0.0
        clean.positions.append(pos)
        pos.ctr = pos_ctr if hasattr(pos, "ctr") else None  # noop, se calcula en load

    log.info("TRANSFORM filas_validas kw=%d pg=%d pos=%d | descartadas=%d",
             len(clean.keywords), len(clean.pages), len(clean.positions), len(errors))
    for e in errors[:10]:
        log.warning("  descartada: %s", e)
    return clean, errors


# ----------------------------------------------------------------------------
# LOAD
# ----------------------------------------------------------------------------

class Warehouse:
    """Carga en SQLite (default) o PostgreSQL (si PG_HOST está definido)."""

    def __init__(self, db_path: Path | None = None) -> None:
        # Prioridad: db_path explícito > SEO_DB_PATH > ruta canónica (seo_config)
        if os.environ.get("PG_HOST"):
            try:
                import psycopg2  # type: ignore[import-untyped]
            except ImportError as exc:
                raise SystemExit(
                    "PG_HOST definido pero psycopg2 no está instalado. "
                    "Instala con: pip install psycopg2-binary"
                ) from exc
            self.conn = psycopg2.connect(
                host=os.environ["PG_HOST"],
                port=os.environ.get("PG_PORT", "5432"),
                dbname=os.environ.get("PG_DB", "seo_dw"),
                user=os.environ.get("PG_USER", "postgres"),
                password=os.environ.get("PG_PASSWORD", ""),
            )
            self.engine = "postgresql"
        else:
            self.conn = sqlite3.connect(str(resolve_db(db_path)))
            self.conn.execute("PRAGMA foreign_keys = ON")
            self.engine = "sqlite"
        log.info("LOAD engine=%s", self.engine)

    # -- schema -------------------------------------------------------------
    def ensure_schema(self) -> None:
        ddl_path = SQL_DIR / "01_create_tables.sql"
        self.conn.executescript(ddl_path.read_text(encoding="utf-8"))
        self.conn.commit()
        log.info("DDL aplicado desde %s", ddl_path.name)

    # -- helpers ------------------------------------------------------------
    @staticmethod
    def _next_id(cur: sqlite3.Cursor, table: str, pk: str) -> int:
        cur.execute(f"SELECT COALESCE(MAX({pk}), 0) FROM {table}")
        return int(cur.fetchone()[0]) + 1

    # -- load ---------------------------------------------------------------
    def load(self, data: ExtractResult, full_refresh: bool = False) -> dict[str, int]:
        cur = self.conn.cursor()
        counts = {"keywords": 0, "pages": 0, "positions": 0, "issues": 0}

        if full_refresh and self.engine == "sqlite":
            # Solo borrar tablas que ya existen (stg_positions_raw se crea en el ETL SQL)
            cur.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
            existing = {row[0] for row in cur.fetchall()}
            for table in ("fact_keyword_position", "fact_technical_issue", "fact_backlink",
                          "stg_pages_raw", "stg_keywords_raw", "stg_positions_raw",
                          "dim_page", "dim_keyword", "dim_site", "etl_run_log"):
                if table in existing:
                    cur.execute(f"DELETE FROM {table}")

        # dim_site
        cur.execute("SELECT COUNT(*) FROM dim_site")
        if cur.fetchone()[0] == 0:
            cur.execute(
                "INSERT INTO dim_site (site_id, domain, site_name, language, country) VALUES (1, 'tienda-demo.com', 'Tienda Demo', 'es', 'ES'), (2, 'blog-demo.com', 'Blog Demo', 'es', 'MX')"
                if self.engine == "sqlite"
                else "INSERT INTO dim_site (site_id, domain, site_name, language, country) SELECT 1, 'tienda-demo.com', 'Tienda Demo', 'es', 'ES'"
            )
            if self.engine != "sqlite":
                cur.execute("INSERT INTO dim_site (site_id, domain, site_name, language, country) VALUES (2, 'blog-demo.com', 'Blog Demo', 'es', 'MX')")

        # dim_keyword (upsert por keyword)
        for kw in data.keywords:
            cur.execute("SELECT keyword_id FROM dim_keyword WHERE LOWER(keyword) = ?", (kw.keyword,))
            row = cur.fetchone()
            if row:
                continue
            cur.execute(
                """INSERT INTO dim_keyword (keyword_id, keyword, category, search_intent,
                                            monthly_search_volume, keyword_difficulty)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (self._next_id(cur, "dim_keyword", "keyword_id"), kw.keyword, kw.category,
                 kw.search_intent, kw.monthly_search_volume, kw.keyword_difficulty),
            )
            counts["keywords"] += 1

        # dim_page (upsert por URL; site 1 = tienda, 2 = blog)
        for pg in data.pages:
            site_id = 2 if "blog-demo.com" in pg.url else 1
            cur.execute("SELECT page_id FROM dim_page WHERE url = ?", (pg.url,))
            row = cur.fetchone()
            if row:
                cur.execute(
                    """UPDATE dim_page SET title=?, h1=?, word_count=?, indexable=?,
                       page_speed_score=? WHERE page_id=?""",
                    (pg.title, pg.h1, pg.word_count, pg.indexable, pg.page_speed_score, row[0]),
                )
                continue
            cur.execute(
                """INSERT INTO dim_page (page_id, site_id, url, title, h1, word_count,
                                         indexable, page_speed_score, last_crawled_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, date('now'))""",
                (self._next_id(cur, "dim_page", "page_id"), site_id, pg.url, pg.title,
                 pg.h1, pg.word_count, pg.indexable, pg.page_speed_score),
            )
            counts["pages"] += 1

        # fact_keyword_position
        for pos in data.positions:
            cur.execute("SELECT keyword_id FROM dim_keyword WHERE LOWER(keyword) = ?", (pos.keyword,))
            kw_row = cur.fetchone()
            cur.execute("SELECT page_id FROM dim_page WHERE url = ?", (pos.url,))
            pg_row = cur.fetchone()
            if not kw_row or not pg_row:
                continue
            keyword_id, page_id = kw_row[0], pg_row[0]
            ctr = (pos.clicks_30d / pos.impressions_30d) if pos.impressions_30d else None
            cur.execute(
                """SELECT position_id FROM fact_keyword_position
                   WHERE keyword_id=? AND page_id=? AND snapshot_date=?""",
                (keyword_id, page_id, pos.snapshot_date),
            )
            if cur.fetchone():
                continue
            cur.execute(
                """INSERT INTO fact_keyword_position (position_id, keyword_id, page_id,
                        snapshot_date, position, previous_position, clicks_30d,
                        impressions_30d, ctr_30d)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (self._next_id(cur, "fact_keyword_position", "position_id"), keyword_id,
                 page_id, pos.snapshot_date, pos.position, pos.previous_position,
                 pos.clicks_30d, pos.impressions_30d, ctr),
            )
            counts["positions"] += 1

        # Reglas de negocio: noindex con keywords posicionando
        cur.execute(
            """INSERT INTO fact_technical_issue (issue_id, site_id, page_id, issue_type,
                    severity, traffic_at_risk, detected_at, status)
               SELECT (SELECT COALESCE(MAX(issue_id), 0) FROM fact_technical_issue)
                      + ROW_NUMBER() OVER (ORDER BY p.page_id),
                      p.site_id, p.page_id, 'noindex', 'critical', 0, date('now'), 'open'
               FROM dim_page p
               WHERE p.indexable = 0
                 AND EXISTS (SELECT 1 FROM fact_keyword_position f
                             WHERE f.page_id = p.page_id AND f.position > 0)
                 AND NOT EXISTS (SELECT 1 FROM fact_technical_issue i
                                 WHERE i.page_id = p.page_id AND i.issue_type = 'noindex'
                                   AND i.status IN ('open','in_progress'))"""
        )
        counts["issues"] += cur.rowcount if cur.rowcount > 0 else 0

        # Reglas de negocio: decay >= 5 posiciones (position empeora: sube el numero)
        cur.execute(
            """INSERT INTO fact_technical_issue (issue_id, site_id, page_id, issue_type,
                    severity, traffic_at_risk, detected_at, status)
               SELECT (SELECT COALESCE(MAX(issue_id), 0) FROM fact_technical_issue)
                      + ROW_NUMBER() OVER (ORDER BY f.page_id, f.keyword_id),
                      p.site_id, f.page_id, 'content_decay',
                      CASE WHEN f.position - f.previous_position >= 8 THEN 'high' ELSE 'medium' END,
                      0, date('now'), 'open'
               FROM fact_keyword_position f
               JOIN dim_page p ON p.page_id = f.page_id
               WHERE f.position > 0 AND f.previous_position IS NOT NULL
                 AND (f.position - f.previous_position) >= 5
                 AND NOT EXISTS (SELECT 1 FROM fact_technical_issue i
                                 WHERE i.page_id = f.page_id AND i.issue_type = 'content_decay'
                                   AND i.status IN ('open','in_progress'))"""
        )
        counts["issues"] += cur.rowcount if cur.rowcount > 0 else 0

        self.conn.commit()
        log.info("LOAD completado %s", counts)
        return counts

    # -- vistas + verificación ----------------------------------------------
    def apply_views(self) -> None:
        views_path = SQL_DIR / "03_create_views.sql"
        self.conn.executescript(views_path.read_text(encoding="utf-8"))
        self.conn.commit()
        log.info("Vistas aplicadas desde %s", views_path.name)

    def quick_wins_top(self, limit: int = 5) -> Sequence[tuple]:
        cur = self.conn.cursor()
        cur.execute(
            f"""SELECT keyword, position, monthly_search_volume, ice_score, priority_tier
                FROM vw_quick_wins_priority ORDER BY ice_score DESC LIMIT {int(limit)}"""
        )
        return cur.fetchall()

    def close(self) -> None:
        self.conn.close()


# ----------------------------------------------------------------------------
# Orquestación
# ----------------------------------------------------------------------------

def run_pipeline(csv_dir: Path | None, full_refresh: bool,
                 db_path: Path | None = None) -> int:
    started = datetime.now(timezone.utc)
    log.info("=== ETL SEO Quick Wins — inicio ===")

    data = extract_from_csv(csv_dir) if csv_dir and csv_dir.exists() else extract_seed()
    clean, errors = transform(data)

    wh = Warehouse(db_path)
    try:
        wh.ensure_schema()
        counts = wh.load(clean, full_refresh=full_refresh)
        wh.apply_views()

        log.info("=== Top quick wins detectados ===")
        for kw, pos, vol, ice, tier in wh.quick_wins_top():
            log.info("  [%s] ICE=%-5s vol=%-6s pos=%-3s %s", tier, ice, vol, pos, kw)

        finished = datetime.now(timezone.utc)
        duration = (finished - started).total_seconds()
        log.info("=== ETL OK en %.1fs | errores de calidad: %d ===", duration, len(errors))
        return 0
    except Exception:
        log.exception("ETL falló")
        return 1
    finally:
        wh.close()


def verify(db_path: Path | None = None) -> int:
    """Checks de calidad de datos sobre el warehouse existente."""
    wh = Warehouse(db_path)
    cur = wh.conn.cursor()
    checks: list[tuple[str, bool, str]] = []

    try:
        cur.execute("SELECT COUNT(*) FROM dim_keyword")
    except sqlite3.OperationalError:
        log.error("El warehouse no está inicializado. Ejecuta antes: "
                  "python etl_seo_pipeline.py --full-refresh")
        wh.close()
        return 1
    n_kw = cur.fetchone()[0]
    checks.append(("dim_keyword no vacía", n_kw > 0, f"{n_kw} filas"))

    cur.execute("SELECT COUNT(*) FROM dim_page")
    n_pg = cur.fetchone()[0]
    checks.append(("dim_page no vacía", n_pg > 0, f"{n_pg} filas"))

    cur.execute("SELECT COUNT(*) FROM fact_keyword_position WHERE ctr_30d > 1")
    bad_ctr = cur.fetchone()[0]
    checks.append(("CTR <= 1 en todos los snapshots", bad_ctr == 0, f"{bad_ctr} violaciones"))

    cur.execute("SELECT COUNT(*) FROM dim_page WHERE indexable NOT IN (0, 1)")
    bad_idx = cur.fetchone()[0]
    checks.append(("indexable binario", bad_idx == 0, f"{bad_idx} violaciones"))

    cur.execute(
        """SELECT COUNT(*) FROM fact_keyword_position f
           WHERE NOT EXISTS (SELECT 1 FROM dim_keyword k WHERE k.keyword_id = f.keyword_id)"""
    )
    orphan = cur.fetchone()[0]
    checks.append(("sin posiciones huérfanas", orphan == 0, f"{orphan} huérfanas"))

    failed = [c for c in checks if not c[1]]
    for name, ok, detail in checks:
        log.info("  %-40s %s (%s)", name, "PASS" if ok else "FAIL", detail)
    wh.close()
    return 1 if failed else 0


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="ETL del data product SEO Quick Wins")
    parser.add_argument("--csv-dir", type=Path, default=None,
                        help="Directorio con keywords.csv, pages.csv y positions.csv")
    parser.add_argument("--full-refresh", action="store_true",
                        help="Borra datos existentes y recarga desde cero")
    parser.add_argument("--verify", action="store_true",
                        help="Ejecuta checks de calidad (tras el pipeline si se "
                             "combina con --full-refresh o --csv-dir)")
    parser.add_argument("--db", type=Path, default=None,
                        help="Ruta del warehouse SQLite (default: "
                             "BASES DE DATOS DE PRUEBAS\\seo_warehouse.db)")
    args = parser.parse_args(list(argv) if argv is not None else None)

    ran_pipeline = False
    if args.full_refresh or args.csv_dir:
        code = run_pipeline(args.csv_dir, args.full_refresh, db_path=args.db)
        if code != 0:
            return code
        ran_pipeline = True

    if args.verify or not ran_pipeline:
        return verify(db_path=args.db)
    return 0


if __name__ == "__main__":
    sys.exit(main())
