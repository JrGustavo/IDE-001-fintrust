# Evidencia de Validaciones de Calidad de Datos

**Fecha de ejecución:** 2026-04-16 10:18:12

## Resumen

| Total checks | Pasaron | Con observaciones |
|---|---|---|
| 30 | 30 | 0 |

## Detalle por Tabla

| Tabla | Validación | Estado | Registros afectados | Detalle |
|---|---|---|---|---|
| customers | pk_no_nula | ✅ PASS | 0 | 0 registros con problema |
| customers | pk_unica | ✅ PASS | 0 | 0 registros con problema |
| customers | segmento_valido | ✅ PASS | 0 | 0 registros con problema |
| customers | ingreso_positivo | ✅ PASS | 0 | 0 registros con problema |
| customers | ciudad_no_nula | ✅ PASS | 0 | 0 registros con problema |
| loans | pk_no_nula | ✅ PASS | 0 | 0 registros con problema |
| loans | pk_unica | ✅ PASS | 0 | 0 registros con problema |
| loans | fk_customer_existe | ✅ PASS | 0 | 0 registros con problema |
| loans | monto_positivo | ✅ PASS | 0 | 0 registros con problema |
| loans | tasa_en_rango | ✅ PASS | 0 | 0 registros con problema |
| loans | status_valido | ✅ PASS | 0 | 0 registros con problema |
| loans | plazo_positivo | ✅ PASS | 0 | 0 registros con problema |
| installments | pk_no_nula | ✅ PASS | 0 | 0 registros con problema |
| installments | pk_unica | ✅ PASS | 0 | 0 registros con problema |
| installments | fk_loan_existe | ✅ PASS | 0 | 0 registros con problema |
| installments | status_valido | ✅ PASS | 0 | 0 registros con problema |
| installments | cuota_numero_outlier | ✅ PASS | 1 | 1 registros con problema |
| installments | montos_no_negativos | ✅ PASS | 0 | 0 registros con problema |
| loans | creditos_sin_cuotas | ✅ PASS | 0 | 0 registros con problema |
| payments | pk_no_nula | ✅ PASS | 0 | 0 registros con problema |
| payments | pk_unica | ✅ PASS | 0 | 0 registros con problema |
| payments | fk_loan_existe | ✅ PASS | 0 | 0 registros con problema |
| payments | installment_huerfano | ✅ PASS | 1 | 1 registros con problema |
| payments | monto_invalido | ✅ PASS | 1 | 1 registros con problema |
| payments | canal_nulo | ✅ PASS | 1 | 1 registros con problema |
| payments | status_valido | ✅ PASS | 0 | 0 registros con problema |
| payments | pagos_no_confirmados | ✅ PASS | 2 | 2 registros con problema |
| payments | posible_duplicado | ✅ PASS | 0 | 0 registros con problema |
| cross | recaudo_no_supera_capital | ✅ PASS | 0 | 0 registros con problema |
| cross | cuotas_closed_no_pagadas | ✅ PASS | 0 | 0 registros con problema |

## Casos de Calidad Documentados


| ID | Tabla | Tipo | Descripción | Acción en Staging |
|---|---|---|---|---|
| P101 | payments | FK huérfana | Referencia I999 que no existe en installments | Excluido del análisis de cuotas, cuenta para recaudo total |
| P102 | payments | Canal NULL | payment_channel = NULL | Reemplazado por 'UNKNOWN' |
| P103 | payments | REVERSED | Pago revertido | Excluido del recaudo efectivo |
| P104 | payments | Posible duplicado | Mismo loan+installment+fecha que P042 | Mantenido con flag; investigar |
| P105 | payments | PENDING | Pago no confirmado | Excluido del recaudo efectivo |
| P106 | payments | Monto = 0 | payment_amount = 0 | Excluido como inválido |
| I135 | installments | Outlier | installment_number = 99 en L003 | Excluido de cálculos de mora |
| P107 | payments | FK a cuota fantasma | Pago aplicado a I135 (cuota #99) | Excluido del análisis de cuotas |
