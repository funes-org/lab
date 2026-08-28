# Historical product prices — one stream, many database rows

This code example demonstrates a **custom persistent projection**: unlike the 
[debt example](../01_simple_persistent_projection/), where each stream materializes into a single upserted record, here one stream 
(a SKU's pricing history) materializes into **one row per price period**, persisted through a 
custom hook (`persist_materialization_model_with`) instead of the default single-record upsert. 
The resulting `product_prices` table is a flavor of [Type 2 Slowly Changing Dimension](https://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_2:_add_new_row), fed by 
the event log instead of change detection at load time.

> [!NOTE]
> A custom persistence hook is open-ended: this example's one-row-per-event cardinality is just the
> choice that fits a price history. A hook could equally materialize aggregated rows, several
> tables, or any other shape.

Each `PriceSet` event declares a price and the half-open period `[from, to)` it covers. The
projection folds them into an in-memory list of periods and syncs the whole list into the
`product_prices` table, keyed by `[sku, version]` — the event's stream version, which makes the
sync idempotent under re-materialization.

## The event log

| Version | Event                          | Price | From  | To    |
|:--------|:-------------------------------|:------|:------|:------|
| 1       | `SkuHistoricEvents::PriceSet`  | $1    | Jan 1 | Feb 1 |
| 2       | `SkuHistoricEvents::PriceSet`  | $3    | Feb 1 | Mar 1 |
| 3       | `SkuHistoricEvents::PriceSet`  | $2    | Apr 1 | May 1 |

No event covers March — the product simply has no listed price during that month.

## The price timeline

"What was the price of this SKU on a given date?" is answered by dropping a vertical line on the
chart: it crosses at most one period. The dashed verticals below are mid-month queries, and the
value at the top of each is what `ProductPriceTable.for(sku).at(date)` finds:

```text
              $1          $3          n/a         $2
      ▲        ┆           ┆           ┆           ┆
   $3 ┤        ┆     ██████┆█████      ┆           ┆
   $2 ┤        ┆           ┆           ┆     ██████┆█████
   $1 ┤  ██████┆█████      ┆           ┆           ┆
      ┼──┬───────────┬───────────┬───────────┬───────────┬──▶
       Jan 1       Feb 1       Mar 1       Apr 1       May 1
```

Two semantics the chart makes visible:

- **Periods are half-open, `[from, to)`**: the $1 and $3 bars touch at Feb 1 without overlapping —
  on the boundary date the new price already applies.
- **Gaps are legitimate**: the March query crosses no bar and the relation comes back empty; there
  is no price to find, and that is an answer, not an error.
