# SQL-контест: оркестрация признаков blacklist

Вам дан пайплайн обработки данных из трёх последовательных SQL-кубиков:

```text
logs.sql ─────→ logs_features ─────┐
                                   ├──→ customer_features.sql
orders.sql ───→ orders_features ───┘
                                      ↑
                                 customer_ids
```

Каждый SQL-файл содержит синтаксические ошибки и незавершённые расчёты.

Ваша задача:

1. Исправить SQL-код каждого кубика так, чтобы весь пайплайн успешно выполнялся
   в SQLite.
2. Сохранить заданную гранулярность промежуточных результатов.
3. Рассчитать восемь признаков для всех пользователей из `customer_ids`.
   
## Оценивание
Если пайплайн запустился без ошибок - за задачу ставится 50 баллов.
Если пайплайн запустился и правильно посчитал признаки - за задачу ставится 100 баллов.

## Исходные таблицы

### `logs`

Одна строка соответствует одному обращению к ручке `bonuses` или `promo`.

Поле `triggered_rule_codes` содержит JSON-массив сработавших правил. Ограничение
по правилу `blacklist` считается сработавшим, если одновременно выполнены
условия:

- `triggered_rules > 0`;
- `request_status = 'rejected'`;
- JSON-массив `triggered_rule_codes` содержит значение `blacklist`.

Обращения к одной ручке внутри сессии могут повторяться. Вместе с `blacklist`
могут срабатывать другие правила.

| Поле | Тип | Описание |
|---|---|---|
| `log_id` | INTEGER | Уникальный идентификатор события |
| `event_dttm` | TEXT | Время события в формате `YYYY-MM-DD HH:MM:SS` |
| `customer_id` | INTEGER | Идентификатор пользователя |
| `session_id` | TEXT | Идентификатор сессии |
| `endpoint` | TEXT | Ручка: `bonuses` или `promo` |
| `promo_id` | TEXT, NULL | Промокод для обращений к `promo` |
| `triggered_rules` | INTEGER | Количество сработавших правил |
| `triggered_rule_codes` | TEXT | JSON-массив кодов сработавших правил |
| `request_status` | TEXT | `allowed`, `rejected` или `error` |

Для разбора JSON-массива можно использовать встроенную табличную функцию
SQLite `json_each`.

### `orders`

Одна строка соответствует заказу. Оплаченным считается заказ со статусом
`paid` или `completed`. Заказ считается оформленным без промокода, если
`promo_id IS NULL`.

| Поле | Тип | Описание |
|---|---|---|
| `order_id` | INTEGER | Уникальный идентификатор заказа |
| `created_dttm` | TEXT | Время заказа в формате `YYYY-MM-DD HH:MM:SS` |
| `customer_id` | INTEGER | Идентификатор пользователя |
| `session_id` | TEXT | Идентификатор сессии |
| `promo_id` | TEXT, NULL | Применённый промокод; `NULL` — заказ без промокода |
| `order_amount` | NUMERIC | Сумма заказа |
| `order_status` | TEXT | `created`, `paid`, `cancelled` или `completed` |

### `customer_ids`

Список целевых пользователей. В итоговую таблицу должны попасть все
пользователи из этого списка, включая пользователей без логов и заказов.

| Поле | Тип | Описание |
|---|---|---|
| `customer_id` | INTEGER | Пользователь из целевой аудитории |

## Кубик 1: `logs.sql`

Кубик обрабатывает таблицу `logs`.

Гранулярность результата:

```text
customer_id × session_id
```

Для каждой сессии необходимо подготовить:

| Поле | Описание |
|---|---|
| `customer_id` | Идентификатор пользователя |
| `session_id` | Идентификатор сессии |
| `bonus_blacklist_requests_cnt` | Число blacklist-срабатываний в ручке `bonuses` |
| `promo_blacklist_requests_cnt` | Число blacklist-срабатываний в ручке `promo` |
| `first_bonus_blacklist_dttm` | Время первого blacklist-срабатывания в `bonuses` |
| `first_promo_blacklist_after_bonus_dttm` | Время первого blacklist-срабатывания в `promo`, произошедшего после бонусного |
| `blacklist_funnel_flg` | `1`, если в сессии сначала сработал `blacklist` в `bonuses`, а позже — в `promo`; иначе `0` |

## Кубик 2: `orders.sql`

Кубик обрабатывает таблицу `orders`.

Гранулярность результата:

```text
customer_id × session_id
```

Для каждой сессии необходимо подготовить:

| Поле | Описание |
|---|---|
| `customer_id` | Идентификатор пользователя |
| `session_id` | Идентификатор сессии |
| `paid_orders_cnt` | Число заказов со статусом `paid` или `completed` |
| `paid_orders_without_promo_cnt` | Число оплаченных или завершённых заказов без промокода |
| `paid_orders_without_promo_gmv` | Сумма оплаченных или завершённых заказов без промокода |
| `first_paid_order_without_promo_dttm` | Время первого оплаченного или завершённого заказа без промокода |

## Кубик 3: `customer_features.sql`

Кубик объединяет результаты первых двух кубиков с таблицей `customer_ids`.

Гранулярность результата:

```text
customer_id
```

В итоговой таблице нужно рассчитать восемь признаков:

| Поле | Описание |
|---|---|
| `bonus_blacklist_requests_cnt` | Общее число blacklist-срабатываний в `bonuses` |
| `promo_blacklist_requests_cnt` | Общее число blacklist-срабатываний в `promo` |
| `blacklist_funnel_sessions_cnt` | Число сессий, прошедших оба blacklist-этапа в правильном порядке |
| `paid_orders_cnt` | Общее число оплаченных или завершённых заказов |
| `paid_orders_without_promo_cnt` | Число оплаченных или завершённых заказов без промокода |
| `paid_orders_without_promo_gmv` | Сумма таких заказов |
| `converted_blacklist_sessions_cnt` | Число blacklist-сессий, где после отклонённой попытки применить промокод появился оплаченный или завершённый заказ без промокода |
| `blacklist_to_order_conversion_rate` | Доля конвертированных blacklist-сессий |

Сессия считается конвертированной, если:

```text
blacklist_funnel_flg = 1
AND first_paid_order_without_promo_dttm
    > first_promo_blacklist_after_bonus_dttm
```

Формула доли:

```text
converted_blacklist_sessions_cnt
/
blacklist_funnel_sessions_cnt
```

## Требования к результату

- Итог содержит ровно одну строку на каждого пользователя из `customer_ids`.
- Пользователи без событий не должны исчезнуть из результата.
- Для отсутствующих счётчиков и GMV возвращается `0`.
- При отсутствии blacklist-сессий `blacklist_to_order_conversion_rate` равен
  `0.0`.
- Одна сессия учитывается в сессионных метриках не более одного раза.
- Результат отсортирован по `customer_id` по возрастанию.
