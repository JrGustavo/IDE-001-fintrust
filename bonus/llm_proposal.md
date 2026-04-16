# Bonus: Propuesta de Uso de LLMs en FinTrust Analytics

## Contexto

El bonus propone una capa de inteligencia sobre el data mart ya construido, usando LLMs para reducir la fricción entre los datos y los usuarios de negocio.

---

## Propuesta: Asistente de Consulta en Lenguaje Natural

### Problema que resuelve

El equipo financiero de FinTrust necesita responder preguntas ad-hoc sobre la cartera sin depender siempre de ingeniería de datos. Ejemplos reales:

- *"¿Cuánto desembolsamos en Bogotá el mes pasado en el segmento SME?"*
- *"¿Qué cohortes tienen más del 10% de mora?"*
- *"Dame el top 5 de créditos con mayor riesgo de impago"*

### Enfoque: Text-to-SQL con contexto del schema

El LLM actúa como un **traductor de lenguaje natural a SQL**, conociendo el schema del data mart. La respuesta viene de BigQuery/DuckDB, no del LLM (los datos son confiables).

```
Usuario → [Pregunta en español]
             ↓
        LLM (Claude/GPT)
        [System prompt: schema + reglas de negocio]
             ↓
        SQL generado
             ↓
        BigQuery/DuckDB ejecuta
             ↓
        Resultado tabular
             ↓
        LLM explica el resultado en lenguaje natural
             ↓
        Usuario recibe respuesta + tabla
```

### Implementación mínima funcional

```python
import anthropic
import duckdb

SCHEMA_CONTEXT = \"\"\"
Tienes acceso a las siguientes tablas en analytics_fintrust:

1. dm_cartera_diaria: una fila por crédito activo.
   - loan_id, customer_id, nombre_cliente, ciudad, segmento, tipo_producto
   - fecha_originacion, cohort_mes, monto_desembolsado, tasa_anual, plazo_meses
   - estado_credito (ACTIVE/DEFAULT), en_mora (bool), bucket_mora
   - saldo_pendiente, saldo_mora, saldo_vigente, max_dias_atraso
   - total_recaudado, ultimo_pago_fecha

2. vw_desembolso_diario: desembolso agrupado por fecha, ciudad, segmento
3. vw_recaudo_diario: recaudo agrupado por fecha
4. vw_cartera_por_cohorte: mora agrupada por cohorte de originación

Reglas:
- Mora significa en_mora = TRUE o loan_status = 'DEFAULT'
- Cohorte = cohort_mes (formato YYYY-MM)
- Solo responde con SQL válido para DuckDB/BigQuery, sin explicaciones
\"\"\"

def natural_language_to_sql(question: str) -> str:
    client = anthropic.Anthropic()
    
    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=500,
        system=SCHEMA_CONTEXT,
        messages=[{
            "role": "user",
            "content": f"Genera solo la query SQL para: {question}"
        }]
    )
    return response.content[0].text.strip()


def explain_result(question: str, sql: str, result_df) -> str:
    \"\"\"LLM explica el resultado en lenguaje de negocio.\"\"\"
    client = anthropic.Anthropic()
    
    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=300,
        messages=[{
            "role": "user",
            "content": f\"\"\"
            Pregunta del analista: {question}
            Query ejecutada: {sql}
            Resultado: {result_df.to_string()}
            
            Explica el resultado en 2-3 oraciones, en español, 
            como si fuera un analista financiero hablando con la dirección.
            \"\"\"
        }]
    )
    return response.content[0].text


def ask_fintrust(question: str):
    conn = duckdb.connect("fintrust.duckdb")
    
    # 1. Generar SQL
    sql = natural_language_to_sql(question)
    print(f"SQL generado:\\n{sql}\\n")
    
    # 2. Ejecutar contra los datos reales
    result = conn.execute(sql).df()
    print(result.to_string())
    
    # 3. Explicar en lenguaje natural
    explanation = explain_result(question, sql, result)
    print(f"\\nAnálisis:\\n{explanation}")
    
    return result


# Ejemplo de uso:
# ask_fintrust("¿Cuáles son las 3 ciudades con mayor cartera en mora?")
# ask_fintrust("¿Qué cohortes del 2025 muestran deterioro temprano?")
```

---

## Caso 2: Generación Asistida de Explicaciones de Métricas

Para el dashboard diario, el LLM puede generar automáticamente un comentario ejecutivo:

```python
def generate_daily_commentary(kpis: dict) -> str:
    \"\"\"Genera comentario ejecutivo diario a partir de KPIs del data mart.\"\"\"
    
    prompt = f\"\"\"
    Eres analista financiero de FinTrust. Con base en estos indicadores del día:
    
    - Cartera total: ${kpis['cartera_total']:,.0f}
    - Índice de mora: {kpis['indice_mora']}%
    - Recaudo del día: ${kpis['recaudo_dia']:,.0f}
    - Créditos en mora: {kpis['creditos_mora']}
    - Cohorte con mayor deterioro: {kpis['peor_cohorte']}
    
    Escribe un párrafo ejecutivo (máx 100 palabras) destacando lo más relevante.
    Sé directo y actionable.
    \"\"\"
    
    client = anthropic.Anthropic()
    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=200,
        messages=[{"role": "user", "content": prompt}]
    )
    return response.content[0].text
```

---

## Límites y Consideraciones

| Aspecto | Consideración |
|---------|--------------|
| **Precisión del SQL** | El LLM puede generar queries incorrectas. Validar siempre contra un conjunto de preguntas conocidas (golden set). |
| **Seguridad** | No exponer datos de clientes individuales al LLM en producción. Solo métricas agregadas. |
| **Costos** | Cada consulta implica llamada a API. Cachear preguntas frecuentes. |
| **Latencia** | El round-trip LLM agrega 1-3 segundos. Aceptable para consultas ad-hoc. |
| **Alucinaciones** | El LLM no responde sobre los datos, solo genera SQL. El riesgo es SQL inválido, no datos inventados. |

## Justificación del Enfoque

Esta propuesta es **pragmática y de bajo riesgo** porque:
1. Los datos siempre vienen de BigQuery/DuckDB, nunca del LLM
2. El LLM solo hace la traducción lenguaje→SQL
3. Es un prototipo que puede probarse con 10 preguntas típicas del equipo financiero
4. No requiere fine-tuning ni infraestructura adicional (solo API key)
5. Agrega valor real: reduce tiempo de respuesta a preguntas ad-hoc de días a segundos
