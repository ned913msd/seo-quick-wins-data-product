# Business Case — SEO Quick Wins Data Product

## 1. Problema

Los equipos de SEO y contenido reciben cientos de hallazgos técnicos y de contenido en cada auditoría (meta descriptions faltantes, keywords en posición 11, contenido en decay, páginas con `noindex` accidental...). Sin un mecanismo de priorización:

- Se ejecuta lo fácil en vez de lo importante.
- Se pierden oportunidades con ROI inmediato (quick wins).
- La dirección no ve el impacto del trabajo de SEO en tráfico ni en ingresos.

**Coste de la inacción**: una keyword de 10.000 búsquedas/mes que cae de la posición 8 a la 15 puede perder ~70% de su CTR, lo que equivale a cientos de visitas/mes y, en e-commerce, a miles de euros de ingresos atribuidos.

## 2. Solución

Un **producto de datos** con 3 capas:

| Capa | Qué hace | Entregable |
|------|----------|------------|
| Ingesta | Centraliza exports de GSC, crawlers (Screaming Frog) y herramientas de keywords | `python/etl_seo_pipeline.py` |
| Modelado | Modelo estrella (dimensiones + hechos) con histórico de posiciones | `sql/01_create_tables.sql` |
| Consumo | Vistas priorizadas por el modelo **ICE** listas para Looker Studio / Metabase | `sql/03_create_views.sql` |

### Modelo de priorización ICE

```
ICE = Impacto × Confianza × Facilidad / 100
```

- **Impacto (1-10)**: volumen de búsqueda de la keyword (escala logarítmica).
- **Confianza (1-10)**: inversa de la keyword difficulty (menos competencia = más confianza).
- **Facilidad (1-10)**: inversa de la posición actual (posición 11 es más fácil de subir que la 40).

Resultado: una lista corta, ordenada y defendible de "esto es lo siguiente que hacemos y por qué".

## 3. Beneficios esperados

| Beneficio | Mecanismo | Estimación |
|-----------|-----------|------------|
| Recuperación de tráfico por decay | Detección automática de caídas ≥ 5 posiciones | +5-15% tráfico orgánico en 2 trimestres |
| Captura de "casi ganadas" | Keywords en posiciones 4-10 con volumen alto | +10-30% clicks en keywords objetivo |
| Recuperación por errores técnicos | `noindex` y Canonical conflicts detectados con tráfico en riesgo cuantificado | Recuperación inmediata (días) |
| Eficiencia del equipo | De auditoría de 40h a lista priorizada automática | -60% horas de análisis |
| Visibilidad ejecutiva | `vw_executive_summary` para reporting mensual | Reuniones con datos, no con opiniones |

## 4. ROI estimado (escenario e-commerce medio)

Supuestos: 50.000 visitas orgánicas/mes, tasa de conversión 1,5%, ticket medio 60 €, valor visita = 0,90 €.

- Quick wins capturados (10 keywords pos. 4-11 mejoradas a top 3): **+1.200 visitas/mes** ≈ **1.080 €/mes**.
- Decay detenido (3 páginas recuperadas): **+900 visitas/mes** ≈ **810 €/mes**.
- Coste de construcción (1 data engineer, 3 semanas) + mantenimiento (4 h/mes): ~8.000 € año 1.

**Payback estimado: 4-5 meses.** ROI año 1: ~1,7x (crece con el histórico de posiciones).

## 5. Stakeholders y responsabilidades

| Rol | Responsabilidad |
|-----|-----------------|
| SEO Lead | Owner del backlog priorizado; valida ICE semanalmente |
| Data Engineer | Mantiene el ETL, calidad de datos y SLA de actualización |
| Contenido / Dev | Ejecutan las acciones (contenidos, fixes técnicos) |
| Dirección | Consume `vw_executive_summary` y decide inversión |

## 6. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|--------|---------|------------|
| Datos de GSC incompletos (muestreo) | Prioridades sesgadas | Cruzar con datos del crawler y de la herramienta de keywords |
| "ICE inflation" (todos P1) | Pérdida de credibilidad | Recalibrar umbrales trimestralmente; tope de 10 P1 activas |
| Quick wins sin ejecución | Producto sin impacto | Revisión semanal con owner asignado por acción |
| Cambios de algoritmo | Anomalías en posiciones | Vista `vw_position_changes` + alertas de caídas ≥ 5 posiciones |

## 7. Roadmap

- **Fase 1 (mes 1)**: ETL manual semanal + vistas core + primer dashboard.
- **Fase 2 (mes 2-3)**: Ingesta automática (API GSC), alertas de decay, histórico completo.
- **Fase 3 (mes 4+)**: Atribución de ingresos por keyword, estimación de tráfico potencial con curvas de CTR propias, recomendaciones automáticas.
