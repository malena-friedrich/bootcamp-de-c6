-- Databricks notebook source
-- MAGIC %md
-- MAGIC # EDA - Importaciones ARCA (corte 202610)
-- MAGIC Corre sobre la tabla Bronze. Cambiá el nombre de la tabla en la celda siguiente (único lugar).
-- MAGIC Objetivo: decidir las reglas de Silver. Después se replica con otros meses.

-- COMMAND ----------

-- AJUSTÁ: nombre de tu tabla Bronze
CREATE OR REPLACE TEMP VIEW bronze AS
SELECT * FROM bootcamp.TU_SCHEMA.bronze_arca_importaciones;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 0) Conteo total (debe dar 8.026.601 para 202610)

-- COMMAND ----------

SELECT count(*) AS filas FROM bronze;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1) Valores vacíos por columna

-- COMMAND ----------

SELECT
  sum(CASE WHEN trim(aduana) = '' THEN 1 ELSE 0 END)             AS aduana,
  sum(CASE WHEN trim(destinacion) = '' THEN 1 ELSE 0 END)        AS destinacion,
  sum(CASE WHEN trim(num_item) = '' THEN 1 ELSE 0 END)           AS num_item,
  sum(CASE WHEN trim(periodo) = '' THEN 1 ELSE 0 END)            AS periodo,
  sum(CASE WHEN trim(nombre_importador) = '' THEN 1 ELSE 0 END)  AS nombre_importador,
  sum(CASE WHEN trim(medio_transporte) = '' THEN 1 ELSE 0 END)   AS medio_transporte,
  sum(CASE WHEN trim(unidad_medida) = '' THEN 1 ELSE 0 END)      AS unidad_medida,
  sum(CASE WHEN trim(cantidad) = '' THEN 1 ELSE 0 END)           AS cantidad,
  sum(CASE WHEN trim(fob_dolar) = '' THEN 1 ELSE 0 END)          AS fob_dolar,
  sum(CASE WHEN trim(fob_total) = '' THEN 1 ELSE 0 END)          AS fob_total,
  sum(CASE WHEN trim(divisa) = '' THEN 1 ELSE 0 END)             AS divisa,
  sum(CASE WHEN trim(pais_origen) = '' THEN 1 ELSE 0 END)        AS pais_origen,
  sum(CASE WHEN trim(pais_procedencia) = '' THEN 1 ELSE 0 END)   AS pais_procedencia,
  sum(CASE WHEN trim(pos_ncm) = '' THEN 1 ELSE 0 END)            AS pos_ncm,
  sum(CASE WHEN trim(concepto_arancel) = '' THEN 1 ELSE 0 END)   AS concepto_arancel,
  sum(CASE WHEN trim(monto_arancel) = '' THEN 1 ELSE 0 END)      AS monto_arancel
FROM bronze;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2) Cardinalidad aproximada por columna

-- COMMAND ----------

SELECT
  approx_count_distinct(aduana)            AS aduana,
  approx_count_distinct(destinacion)       AS destinacion,
  approx_count_distinct(num_item)          AS num_item,
  approx_count_distinct(periodo)           AS periodo,
  approx_count_distinct(nombre_importador) AS nombre_importador,
  approx_count_distinct(medio_transporte)  AS medio_transporte,
  approx_count_distinct(unidad_medida)     AS unidad_medida,
  approx_count_distinct(divisa)            AS divisa,
  approx_count_distinct(pais_origen)       AS pais_origen,
  approx_count_distinct(pais_procedencia)  AS pais_procedencia,
  approx_count_distinct(pos_ncm)           AS pos_ncm,
  approx_count_distinct(concepto_arancel)  AS concepto_arancel
FROM bronze;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3) Grano: ¿hay duplicados por destinación + ítem + concepto?

-- COMMAND ----------

SELECT count(*) AS grupos_duplicados
FROM (
  SELECT destinacion, num_item, concepto_arancel, count(*) AS c
  FROM bronze
  GROUP BY destinacion, num_item, concepto_arancel
  HAVING count(*) > 1
);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4) Divisa: valores y peso de cada uno

-- COMMAND ----------

SELECT divisa, count(*) AS filas
FROM bronze
GROUP BY divisa
ORDER BY filas DESC;

-- COMMAND ----------

-- Muestra de filas que no están en DOL
SELECT * FROM bronze WHERE divisa <> 'DOL' LIMIT 20;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 5) Hipótesis: fob_total es el total de la destinación (no del ítem)
-- MAGIC - `con_fob_total_variable` = 0 indica que fob_total no cambia dentro de una destinación.
-- MAGIC - `no_cierran` = destinaciones donde la suma de fob_dolar por ítem difiere de fob_total en más de 1 USD.
-- MAGIC Solo filas en DOL, un valor por ítem (un ítem puede repetirse por concepto arancelario).

-- COMMAND ----------

WITH items AS (
  SELECT destinacion, num_item,
         max(try_cast(fob_dolar AS DOUBLE)) AS fob_item,
         max(try_cast(fob_total AS DOUBLE)) AS fob_tot
  FROM bronze
  WHERE divisa = 'DOL'
  GROUP BY destinacion, num_item
),
por_dest AS (
  SELECT destinacion,
         sum(fob_item)            AS suma_items,
         count(DISTINCT fob_tot)  AS n_fob_total,
         max(fob_tot)             AS fob_total
  FROM items
  GROUP BY destinacion
)
SELECT count(*) AS destinaciones,
       sum(CASE WHEN n_fob_total > 1 THEN 1 ELSE 0 END)                     AS con_fob_total_variable,
       sum(CASE WHEN abs(suma_items - fob_total) > 1 THEN 1 ELSE 0 END)     AS no_cierran
FROM por_dest;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 6) NCM: formato y capítulos

-- COMMAND ----------

SELECT count(*) AS ncm_formato_raro
FROM bronze
WHERE NOT pos_ncm RLIKE '^[0-9]{4}[.][0-9]{2}[.][0-9]{2}$';

-- COMMAND ----------

SELECT substring(pos_ncm, 1, 2) AS capitulo, count(*) AS filas
FROM bronze
GROUP BY 1
ORDER BY 1;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 7) Importador: cantidad, más frecuentes y nombres posiblemente cortados

-- COMMAND ----------

SELECT count(DISTINCT nombre_importador) AS importadores_distintos FROM bronze;

-- COMMAND ----------

SELECT nombre_importador, count(*) AS filas
FROM bronze
GROUP BY nombre_importador
ORDER BY filas DESC
LIMIT 20;

-- COMMAND ----------

-- Nombres de exactamente 30 caracteres: candidatos a estar truncados
SELECT count(DISTINCT nombre_importador) AS nombres_de_30_caracteres
FROM bronze
WHERE length(nombre_importador) = 30;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 8) Numéricas: no numéricos, ceros y negativos

-- COMMAND ----------

SELECT
  sum(CASE WHEN try_cast(cantidad AS DOUBLE)       IS NULL AND trim(cantidad)       <> '' THEN 1 ELSE 0 END) AS cantidad_no_num,
  sum(CASE WHEN try_cast(fob_dolar AS DOUBLE)      IS NULL AND trim(fob_dolar)      <> '' THEN 1 ELSE 0 END) AS fob_dolar_no_num,
  sum(CASE WHEN try_cast(fob_total AS DOUBLE)      IS NULL AND trim(fob_total)      <> '' THEN 1 ELSE 0 END) AS fob_total_no_num,
  sum(CASE WHEN try_cast(monto_arancel AS DOUBLE)  IS NULL AND trim(monto_arancel)  <> '' THEN 1 ELSE 0 END) AS monto_arancel_no_num,
  sum(CASE WHEN try_cast(cantidad AS DOUBLE)       <= 0 THEN 1 ELSE 0 END) AS cantidad_cero_neg,
  sum(CASE WHEN try_cast(fob_dolar AS DOUBLE)      <= 0 THEN 1 ELSE 0 END) AS fob_dolar_cero_neg,
  sum(CASE WHEN try_cast(fob_total AS DOUBLE)      <= 0 THEN 1 ELSE 0 END) AS fob_total_cero_neg,
  sum(CASE WHEN try_cast(monto_arancel AS DOUBLE)  <  0 THEN 1 ELSE 0 END) AS monto_arancel_neg
FROM bronze;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 9) Categóricas chicas

-- COMMAND ----------

SELECT aduana, count(*) AS filas FROM bronze GROUP BY aduana ORDER BY filas DESC LIMIT 15;

-- COMMAND ----------

SELECT medio_transporte, count(*) AS filas FROM bronze GROUP BY medio_transporte ORDER BY filas DESC;

-- COMMAND ----------

SELECT unidad_medida, count(*) AS filas FROM bronze GROUP BY unidad_medida ORDER BY filas DESC LIMIT 15;

-- COMMAND ----------

SELECT concepto_arancel, count(*) AS filas FROM bronze GROUP BY concepto_arancel ORDER BY filas DESC LIMIT 15;

-- COMMAND ----------

SELECT pais_origen, count(*) AS filas FROM bronze GROUP BY pais_origen ORDER BY filas DESC LIMIT 15;
