---
name: python-app-architecture
description: Layout and dependency rules for Python apps, adapted from Architecture Patterns with Python (Cosmic Python). Use when starting a Python app or service, adding a use case or an external dependency (database, parser, LLM, API), restructuring a Python backend, or deciding where Python code goes.
---

# Python App Architecture

Shape a Python app so business rules stay pure, every external thing sits behind a port, and each pattern arrives only when its trigger appears. Adapted from [Architecture Patterns with Python](https://www.cosmicpython.com/).

## Layout

```
src/<package>/
  domain/          pure rules and models (Pydantic or dataclasses); imports nothing from the other layers
  service_layer/   one module per use case: a service function that orchestrates domain + adapters and raises domain errors
  adapters/        each external thing as a typing.Protocol (port) plus real implementations that inherit it (store, parser, files, LLM client, HTTP)
  entrypoints/     thin: CLI (argparse + printing), API (FastAPI routes); translate input, call a service, shape output
  views.py         read models (response shapes), separate from write models
  bootstrap.py     the one composition root, from day one: picks adapters from settings via a registry, builds them once for every entrypoint (pure DI, no framework)
  settings.py      environment config; fail hard on a missing secret
tests/
  unit/            no Docker or network: domain rules, services with fakes
  integration/     real adapters against real infrastructure: one contract test per Protocol, parametrized over its implementations
  e2e/             the whole path through an entrypoint; one or a few per feature
  fakes.py         in-memory fakes for service unit tests; created with the second use case
```

## Where code goes

- A business rule or invariant -> `domain/`, as a pure function or a model method.
- A new use case -> a new module in `service_layer/` exposing one service function.
- A new external dependency -> a Protocol and its implementation in `adapters/`, a contract test in `tests/integration/`, a registry entry in `bootstrap.py`; a fake in `tests/fakes.py` once a second use case exists.
- A new implementation of an existing port -> a new adapter file, one registry line in `bootstrap.py`, one more param in that Protocol's contract test.
- A new CLI command or route -> `entrypoints/`, calling exactly one service function.
- A new response shape -> `views.py`.
- A new config value -> `settings.py`, read once and passed down.

## Rules

- **Dependency direction**: entrypoints -> service_layer -> domain. Adapters implement Protocols that the service layer depends on; the domain imports nothing from adapters, service_layer, or entrypoints.
- **Inject dependencies as parameters.** A service function receives its adapters as arguments; it never constructs them or reads settings.
- **App factories take all or nothing.** `create_app(...)` accepts every injected dependency, or none and calls `bootstrap.py`. Never a mix.
- **Business rules live in domain code** with fast unit tests. A rule hidden in SQL, Cypher, or a route handler is a bug waiting for its test.
- **Value objects are immutable**: Pydantic `frozen=True` or `@dataclass(frozen=True)`.
- **One use case, one transaction.** Each service function commits its writes atomically or not at all.
- **Each port is a `typing.Protocol`.** Real adapters inherit it explicitly (`class DoclingParser(Parser)`) so the type checker flags a missing or wrong method at the class; fakes may stay plain classes. Use an ABC only when the base carries shared behaviour every implementation must run (a template method, as the book's `AbstractRepository.add` tracking `seen`).
- **Entrypoints never name a concrete adapter.** `bootstrap.py` picks implementations from settings through a small registry dict:
  ```python
  PARSERS = {"docling": lambda s: DoclingParser(), "llm": lambda s: LLMParser(model=s.llm_model)}
  parser = PARSERS[settings.parser](settings)  # PARSER=docling in .env
  ```
  An unknown value fails at startup naming the valid choices. Switching an implementation is a settings change; adding one is a new adapter file plus one registry line; entrypoints stay untouched. Prefer the dict over a plugin or entry-points system unless outside packages must add implementations.
- **Every adapter has a contract test from the start.** Write one test per Protocol, against the Protocol, parametrized over every real implementation (both parsers on the same fixture), run against real infrastructure. When fakes arrive, add each to its Protocol's parametrization so it passes the same contract. Use fakes, not mocks.

## Adopt when triggered

Start with the layout and rules above. Add each pattern only when its trigger appears, and say which trigger fired in the plan.

| Pattern | Trigger |
| --- | --- |
| Fakes in `tests/fakes.py` + service unit tests | a second use case |
| Consistency boundaries (aggregates) + optimistic locking (version numbers) | concurrent writes to the same record |
| Message bus + domain events | steps that chain automatically: "when X finishes, run Y" |
| Unit of Work class | the driver or ORM gives no atomic block of its own. Skip it for Neo4j `execute_write` or a SQLAlchemy `Session` used directly |
| ORM classical mapping | a relational database |
| Separate read path (CQRS) | reads need shapes or speed the write models cannot give |

## Naming

When the project's domain terms already use "Aggregate" (or another pattern name) for a domain concept, call the pattern a **consistency boundary** in docs and code comments. Check the `## Domain terms` section of the nearest `AGENTS.md` first.

## Sources

Cosmic Python chapters, for the reasoning behind each rule:

- [Ch 2, Repository](https://www.cosmicpython.com/book/chapter_02_repository)
- [Ch 3, Abstractions](https://www.cosmicpython.com/book/chapter_03_abstractions)
- [Ch 4, Service layer](https://www.cosmicpython.com/book/chapter_04_service_layer)
- [Ch 5, High gear and low gear (testing)](https://www.cosmicpython.com/book/chapter_05_high_gear_low_gear)
- [Ch 6, Unit of Work](https://www.cosmicpython.com/book/chapter_06_uow)
- [Ch 7, Aggregates and consistency boundaries](https://www.cosmicpython.com/book/chapter_07_aggregate)
- [Ch 8-10, Events, message bus, commands](https://www.cosmicpython.com/book/chapter_08_events_and_message_bus)
- [Ch 12, CQRS](https://www.cosmicpython.com/book/chapter_12_cqrs)
- [Ch 13, Dependency injection and bootstrapping](https://www.cosmicpython.com/book/chapter_13_dependency_injection)
