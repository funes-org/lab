# Simple debt persistent projection modeling

This code example exists solely to demonstrate the use of persistent projections. It models a simplified debt balance tracker, much simpler than what a real system in this domain would require.

It also includes an example of a failure in a projection configured as transactional, showing how events get rejected in practice.

Some examples of the system's behavior are listed below. The outstanding balance and debt status shown in the tables are data that, in practice, live in the persistent projection — alongside other, less relevant information.

> [!NOTE]
> The tests cover Funes internals, asserting that new event entries are created while no new projection records are — because in this example each debt's projection is only ever upserted into a single record, which is not necessarily the case in general. This is due to the didactic nature of this code; the practice is not encouraged in production code.

## Open debt

| Time | Event                        | Amount | Outstanding balance | Status  |
|:-----|:-----------------------------|:-------|:--------------------|:--------|
| t1   | `DebtEvent::Issued`          | $100   | $100                | `:open` |
| t2   | `DebtEvent::PaymentReceived` | $50    | $50                 | `:open` |

```text
     ▲
     │
 100 ┤      ┌───────────────────────────┐
     │      │                           │
     │      │                           │
  50 ┤      │                           └──────────────────
     │      │
     │      │
   0 ┼──────┴───────────────────────────────────────────────▶
     t0     t1                          t2
```

This case shows the debt's behavior after its issuance and after a partial payment (one whose amount is not enough to settle the debt).

## Repaid debt

| Time | Event                        | Amount | Outstanding balance | Status    |
|:-----|:-----------------------------|:-------|:--------------------|:----------|
| t1   | `DebtEvent::Issued`          | $100   | $100                | `:open`   |
| t2   | `DebtEvent::PaymentReceived` | $50    | $50                 | `:open`   |
| t3   | `DebtEvent::PaymentReceived` | $50    | $0                  | `:repaid` |

```text
     ▲
     │
 100 ┤      ┌───────────────────────────┐
     │      │                           │
     │      │                           │
  50 ┤      │                           └───────────────────────────┐
     │      │                                                       │
     │      │                                                       │
   0 ┼──────┴───────────────────────────────────────────────────────┴────────▶
     t0     t1                          t2                          t3
```

This case shows the debt's behavior after it has been fully repaid.
