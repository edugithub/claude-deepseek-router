---
name: coding-workflow
description: Use for coding tasks. Provides a reliable implementation workflow, including task classification, multi-file change coordination, verification, and completion checks. Use this for normal implementation work and whenever a coding task may affect multiple files.
---

# Coding Workflow

Follow this workflow for coding tasks. The goal is a complete, consistent, verified implementation — not just editing the first file that seems relevant.

## 1. Classify the task

Pick the category that best fits:

- **Simple**: clearly isolated and local (small function change, obvious local bug, adding a field, a focused test, a small config change).
- **Multi-file**: more than one file must change, or a shared contract (interface, signature, API, event, config key) changes, or the feature naturally crosses components.
- **Refactoring**: structure, responsibilities, interfaces, dependencies, architecture, or component boundaries change → also use the `refactoring` skill.
- **Debugging**: bugs, failing tests, runtime errors, unexpected behaviour, regressions, integration failures → also use the `debugging` skill.

If several apply, apply all relevant protocols. Before editing, read the relevant implementation and search for usages/callers — do not assume the file the user named is the only one affected. Do not infer project behaviour when it can be verified from the codebase, tests, configuration, or tooling. Prefer evidence over assumptions.

## 2. Make the smallest complete change

Implement the requested behaviour while minimizing unrelated changes. Prefer existing project patterns and small, focused edits. Avoid unrequested refactoring, new abstractions without a concrete need, and changing behaviour that was not requested.

"Minimal change" does not mean "change only the file the user mentioned" — it means the smallest set of changes required for a complete implementation.

## 3. Multi-file consistency

When a change crosses files: update all affected implementations, callers, tests, and config; update imports/dependencies; search for stale references; check that contracts remain consistent. Never knowingly leave the project inconsistent if the task can be completed.

## 4. Verify

After editing: inspect the final diff; search for stale references to renamed or changed symbols; check for obvious type, compile, import, or syntax errors; run the most relevant available tests or validation; fix failures caused by the change; re-run verification after fixes. Use the project's existing build, test, or lint mechanisms rather than inventing new ones.

## 5. Completion check

Before declaring the task complete, verify: every explicit requirement was implemented; every affected file and caller was considered; no stale references remain; no obvious errors remain; relevant tests were run when practical; the final diff contains no accidental changes; no temporary debugging code remains; no requested work was silently skipped.

Do not claim a test passed unless it was actually run. If verification cannot be performed, state explicitly what could not be verified.

Do not stop merely because the code was written — the task is complete only after it has been checked for consistency and, when practical, verified. If the task becomes significantly broader than expected, reassess the affected scope before continuing. If the user asks for a plan rather than implementation, provide the plan without editing code.
