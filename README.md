# Funes Lab

A laboratory of small, self-contained example apps exploring [funes-rails](https://rubygems.org/gems/funes-rails),
an event sourcing library for Rails.

Each example lives in a single file under `apps/`, holding its schema, domain code, and tests —
annotated with comments showing where each piece would live in a real Rails app. The examples are
executable documentation: running one boots a minimal Rails app against an in-memory SQLite
database, installs the funes schema, and runs the example's test suite.

## Running the examples

Run a single example:

```sh
bundle install
bundle exec ruby apps/01_simple_persistent_projection/app.rb
```

Run every example at once, each in its own process (this is also the default rake task, and what CI runs):

```sh
bundle exec rake apps
```

CI runs the full suite on every push and pull request, alongside RuboCop and bundler-audit.

## Applications

Each entry highlights the specific concepts it applies, so if you are interested in a
particular subject it can be found at a glance.

### [Simple debt persistent projection modeling](apps/01_simple_persistent_projection/)

A simplified debt balance tracker: debts are issued and paid through events, and their current
state (outstanding balance, status, key dates) is materialized into a persistent projection.

Exercises: [persistent projections](https://docs.funes.org/recipes/materialization-models/persistent/) ·
[transactional projections](https://docs.funes.org/concepts/projection/#persistence-tiers-for-projections) ·
[actual time attribute](https://docs.funes.org/recipes/bi-temporal-event-streams/)

### [Fowler's bitemporal history — Sally's salary](apps/02_fowlers_bitemporal_history/)

Reproduces Sally's case from Martin Fowler's [Bitemporal History](https://martinfowler.com/articles/bitemporal-history.html)
article: a retroactive raise and its later correction, queried along both record time and actual time.

Exercises: [bi-temporal event streams](https://docs.funes.org/recipes/bi-temporal-event-streams/) ·
[virtual projections](https://docs.funes.org/recipes/materialization-models/virtual/)
