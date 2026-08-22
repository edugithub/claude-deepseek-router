---
name: refactoring
description: Use when restructuring code, changing responsibilities, moving components, extracting abstractions, changing interfaces, changing dependencies, or performing non-trivial refactoring or architectural changes.
---

# Refactoring Protocol

Use this protocol for structural or non-trivial refactoring.

## 1. Understand the current design

Before editing:

- Inspect the existing implementation.
- Identify the responsibility of the code being changed.
- Identify consumers and dependencies.
- Search for callers, implementations, subclasses, interfaces, tests, configuration, and integrations.
- Identify existing project patterns that should be preserved.

Do not redesign code before understanding the current implementation.

## 2. Define the target

Determine:

- What responsibility is changing.
- What responsibility is moving.
- Which interfaces change.
- Which dependencies are introduced or removed.
- Which components are affected.
- What behaviour must remain unchanged.
- Whether compatibility must be preserved.

Prefer the smallest structural change that achieves the requested outcome.

## 3. Preserve behaviour

Unless explicitly requested, preserve:

- External behaviour.
- Error handling.
- Validation.
- Logging.
- Configuration semantics.
- Concurrency behaviour.
- Persistence semantics.
- API contracts.
- Event contracts.
- Performance characteristics where practical.

Do not silently introduce behavioural changes as part of a refactor.

## 4. Execute the refactoring coherently

When changing shared structures:

- Update interfaces and implementations together.
- Update callers and consumers.
- Update dependency injection/configuration.
- Update tests and mocks.
- Update serialization/deserialization when relevant.
- Update API/event contracts when relevant.
- Remove obsolete code only after checking references.

Avoid leaving duplicate or partially migrated implementations unless explicitly required.

## 5. Avoid speculative improvements

Do not use the refactoring as an excuse to:

- Rewrite unrelated code.
- Introduce unnecessary abstractions.
- Rename unrelated symbols.
- Change formatting throughout the project.
- Upgrade dependencies without a requirement.
- Fix unrelated technical debt.

Keep the change focused.

## 6. Verify

After the refactoring:

- Search for references to old implementations.
- Search for obsolete names and signatures.
- Inspect the complete diff.
- Run the relevant build/compile checks.
- Run relevant tests.
- Run static analysis or linting when appropriate.
- Fix failures caused by the refactoring.
- Re-run verification.

## 7. Completion

Do not consider the refactoring complete until:

- The intended target structure exists.
- Old structures are removed or intentionally retained.
- All affected consumers are consistent.
- Behaviour remains correct.
- Relevant verification succeeds.

If something cannot be verified, state that explicitly.
