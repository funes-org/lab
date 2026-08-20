# Bitemporal history — Sally's salary

This code example reproduces Sally's case from Martin Fowler's
[Bitemporal History](https://martinfowler.com/articles/bitemporal-history.html) article. Sally is paid
$6,000 a month; on Mar 15 HR reports she got a raise to $6,500 effective Feb 15; on Apr 5 HR corrects
that report — the raise was actually to $6,400, effective the same Feb 15.

A Funes event stream is bitemporal out of the box: every event entry carries a **record time** (when
the system learned about the event, its `created_at`) and an **actual time** (when the event took
effect in the real world, its `occurred_at`, fed here by `actual_time_attribute :at`). Fowler's
two-dimensional query `sally.salaryAt(actualDate, recordDate)` is answered by
`projected_with(SalaryStateProjection, as_of: record_date, at: actual_date)`.

Since the example exists only to show the two time dimensions, the whole domain is a single
`Employee::SalarySet` event and a **virtual** projection: its materialization model
(`SalaryState`) is a plain `ActiveModel` class, computed on demand from the event log — nothing but
the events themselves is ever persisted.

## The record

The event log is literally the article's event-sourcing table:

| Record date | Event                 | Actual (effective) date | Amount |
|:------------|:----------------------|:------------------------|:-------|
| Jan 1       | `Employee::SalarySet` | Jan 1                   | $6,000 |
| Mar 15      | `Employee::SalarySet` | Feb 15                  | $6,500 |
| Apr 5       | `Employee::SalarySet` | Feb 15                  | $6,400 |

## Sally's salary along both timelines

The same actual date answers differently depending on when we ask — Fowler's table:

| Actual date | Record date | Salary | |
|:------------|:------------|:-------|:--|
| Feb 25      | Feb 25      | $6,000 | payroll ran with the information available at the time |
| Feb 25      | Mar 25      | $6,500 | the raise had been reported, with the wrong amount |
| Feb 25      | Apr 25      | $6,400 | after the Apr 5 correction |

Each test in the stream suite fixes a record date and walks the actual history as it was believed on
that date — one horizontal slice of the article's two-dimensional chart per test:

```text
as of Feb 25:                  as of Mar 25:                  as of Apr 25:
      ▲                              ▲                              ▲
 6500 ┤                         6500 ┤       ┌────────────     6500 ┤
 6400 ┤                         6400 ┤       │                 6400 ┤       ┌────────────
 6000 ┼────────────────────     6000 ┼───────┘                 6000 ┼───────┘
      └───────┬───────┬───▶          └───────┬───────┬───▶          └───────┬───────┬───▶
      Jan 1   Feb 15  Feb 25         Jan 1   Feb 15  Feb 25         Jan 1   Feb 15  Feb 25
```

Record history itself is append-only: the Apr 5 correction adds a third entry to the log, it never
rewrites the mistaken Mar 15 one — which is why "what did we believe on Mar 25?" stays answerable
after the correction, as the Mar 25 test shows by running against the full, already-corrected log.
