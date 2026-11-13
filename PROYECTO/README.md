# 📊 Proyecto 1: Demografía de Empresas de Chile (SII)
📖 Descripción General
Este proyecto tiene como objetivo construir un pipeline de datos end-to-end en Databricks (Arquitectura Medallion) para analizar la demografía, supervivencia y cierre de empresas en Chile, utilizando los datos públicos de la Nómina de Personas Jurídicas del Servicio de Impuestos Internos (SII).

El proyecto procesa archivos históricos en formato .TXT correspondientes a diferentes cortes comerciales (ej. 2005-2009, 2010-2014, etc.), simulando una ingesta incremental por lotes (batches).

# 🏗️ Arquitectura y Tecnologías
- Plataforma: Databricks Free (Unity Catalog).
- Almacenamiento: Volumes (para archivos crudos .TXT).
- Procesamiento: PySpark / Spark SQL.
- Arquitectura: Medallion (Bronze -> Silver -> Gold).
- Orquestación: Databricks Jobs (parametrizado por fecha_corte o año).

### 🔍 Hallazgos del Análisis Exploratorio (EDA) y Reglas de Negocio
Durante la exploración inicial del archivo PUB_EMPRESAS_PJ_2005.TXT, se detectaron los siguientes puntos críticos que definen las reglas de transformación:

### 1. Formato del Archivo
Separador: El delimitador oficial no es una coma, sino un Tabulador (\t).

- Codificación: Se debe verificar en la ingesta (usualmente UTF-8 o ISO-8859-1 para manejar tildes y Ñ).
- Volumen: El corte 2005 posee más de 200.000 filas. Los archivos rondan entre 79 MB y 96 MB.

### 2. Tratamiento de Valores Atípicos (*)
Se detectó que el SII utiliza el carácter asterisco (*) para denotar "Dato no informado" o "Sin Información".

En el corte 2005, 8.474 filas tienen '*' en la columna Tramo según ventas.

De estas, 6.680 también tienen '*' en las columnas de capital propio.

Regla de limpieza: En la capa Silver, el * se convertirá a nulo (NULL). **Para el análisis de tamaño empresarial, se excluirán las filas que no tengan un tramo de ventas numérico válido.**

### 3. Entendimiento de las Columnas de Tramos (Medidas en UF)

La UF (Unidad de Fomento) es una medida chilena ajustada por inflación (similar al UVA/CER en Argentina). El SII categoriza a las empresas en rangos del 1 al 12, sin exponer montos exactos:

Tramo según ventas: Clasifica el tamaño de la empresa (Micro, Pequeña, Mediana, Gran Empresa) según facturación anual.

Tramo capital propio positivo: Patrimonio neto positivo de la empresa (escala del 1 al 10).

Tramo capital propio negativo: Indicador de insolvencia (patrimonio neto negativo o deudas mayores a los activos).

### 4. Cierres Administrativos vs. Reales
- Fecha término de giro: Si tiene fecha, la empresa está cerrada. Si está vacía, está activa.
- Tipo término de giro: Indica el motivo (Voluntario, Fusión, Judicial).

⚠️ Advertencia Metodológica: El SII ha realizado cierres masivos de tipo administrativo (empresas inactivas que no quebraron realmente). En la capa Gold, se debe crear la columna tipo_cierre_normalizado para no sesgar los análisis de supervivencia.

# 🗄️ Diseño de las Capas (Medallion)

### 🥉 Bronze (bronze.sii_empresas_raw)
Propósito: Ingesta cruda, append-only.

Reglas: Todas las columnas como tipo String. Sin limpieza.

Columnas de control agregadas: archivo_origen, fecha_corte, fecha_ingesta, hash_fila.

Tabla de rechazos: bronze.sii_empresas_rechazos para filas malformadas.

### 🥈 Silver (silver.empresas)
Propósito: Datos limpios, tipados y normalizados.

Transformaciones:

Reemplazo de * por NULL.

Casteo de fechas (fecha_inicio_actividades, fecha_termino_giro) y enteros (trabajadores, tramos).

Filtro de calidad: Se conservan solo las filas que tengan Razón social válida y Tramo según ventas numérico.

Cálculo de indicadores: esta_activa (booleano), anios_vida (entero), cohorte (año de inicio).

Normalización de tipo_cierre_normalizado (Voluntario, Administrativo, Judicial, Otro).

### 🥇 Gold (Modelo Dimensional)
Dimensiones: dim_region, dim_rubro, dim_tamano, dim_fecha, dim_tipo_cierre.

### Tablas de Hechos:

fact_empresa_cohorte: Cantidad de empresas por cohorte, región y rubro. Indicadores de supervivencia a 1, 3 y 5 años.

fact_cierres_mensuales: Cierres agrupados por mes, región, rubro y tipo de cierre.

# 🎯 Hipótesis a Validar (Preguntas de Negocio)
Supervivencia por Tamaño: ¿Las empresas que inician como "Microempresa" tienen una tasa de supervivencia a 5 años significativamente menor que las que inician como "Pequeña" o "Mediana"?

El factor del Capital Negativo: ¿Cuál es la probabilidad de quiebra (cierre real) de una empresa que registra un "Tramo capital propio negativo" en sus primeros años?

Sesgo Geográfico: ¿La Región Metropolitana concentra la mayor cantidad de cierres administrativos debido a que allí se registran las casas matrices de las empresas? (Nota metodológica 8: Los trabajadores se asocian a la casa matriz).