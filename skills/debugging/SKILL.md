---
name: debugging
description: Use when investigating bugs, failing tests, runtime errors, unexpected behaviour, regressions, integration failures, or other problems where the root cause must be identified and fixed.
---

# Debugging Protocol

The objective is to identify and fix the root cause, not merely suppress the observed symptom.

## 1. Establish the failure

Determine:

- What is failing.
- How it fails.
- Under what conditions it fails.
- Whether it is reproducible.
- What evidence is available.

Use:

- Error messages.
- Stack traces.
- Logs.
- Tests.
- Reproduction steps.
- Existing monitoring information.
- Recent changes when available.

## 2. Trace the execution path

Inspect the relevant code and follow the actual execution path.

Search for:

- The failing symbol.
- Callers.
- Consumers.
- Related configuration.
- State transitions.
- Error handling.
- External dependencies.
- Relevant tests.

Do not change code merely because a file looks suspicious.

## 3. Identify the root cause

Distinguish between:

- Root cause.
- Trigger.
- Symptom.
- Secondary failure.

Base the diagnosis on evidence whenever possible.

Before changing code, have a concrete hypothesis about why the failure occurs.

## 4. Apply the smallest correct fix

Fix the root cause with the smallest appropriate change.

Avoid:

- Broad rewrites.
- Unrelated refactoring.
- Disabling validation.
- Ignoring exceptions.
- Increasing timeouts without understanding why.
- Adding retries merely to hide failures.
- Changing behaviour unrelated to the failure.

## 5. Verify the fix

After the change:

1. Reproduce the original scenario when possible.
2. Run the relevant test.
3. Check related behaviour.
4. Check for regressions.
5. Inspect the final diff.

If the fix fails:

- Treat the new failure as evidence.
- Reassess the hypothesis.
- Investigate further.
- Do not repeatedly make arbitrary changes.

## 6. Completion

A debugging task is complete only when:

- The original failure is understood.
- The root cause has been identified with reasonable confidence.
- The fix addresses the root cause.
- Relevant verification succeeds.
- No obvious regression has been introduced.

If the root cause cannot be established, do not claim certainty.

Clearly distinguish:

- What is known.
- What was tested.
- What remains uncertain.
