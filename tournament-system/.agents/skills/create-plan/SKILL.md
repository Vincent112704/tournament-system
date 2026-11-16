---
name: create-plan
description: Force a review-first implementation plan before making code changes. Use when a user requests a feature, bug fix, refactor, migration, configuration change, or other coding task where implementation should be planned before execution.
---

# Create Plan

## Purpose

Prevent wrong-direction implementation by separating repository discovery and planning from execution.

For every task that triggers this skill, **do not modify, create, delete, rename, or overwrite any project file before the user explicitly approves the plan**.

## Mandatory workflow

### Phase 1 — Read-only discovery

Operate in read-only mode.

1. Inspect the repository structure and relevant documentation.
2. Read the files most likely to be affected.
3. Identify the existing architecture, conventions, dependencies, and constraints relevant to the request.
4. Identify the likely files/modules that would change.
5. Identify the existing test and validation commands.
6. Identify important edge cases, compatibility concerns, and risks.

Do not:
- edit files;
- create files;
- delete or rename files;
- run commands that intentionally mutate project state;
- install dependencies;
- make commits;
- generate migrations;
- format or auto-fix files.

Read-only commands such as listing files, searching, reading files, inspecting git status/diffs/logs, and running non-mutating analysis are allowed.

### Phase 2 — Present the plan

Present the plan using this structure:

# Plan

<1–3 sentences describing the intent and high-level approach.>

## Scope
- In: <what will change>
- Out: <what will deliberately not change>

## Files to change
- `<path>` — <what will change and why>
- `<path>` — <what will change and why>

If no existing file needs to change, say so explicitly.

## Action items
[ ] <ordered, concrete implementation step>
[ ] <ordered, concrete implementation step>
[ ] <ordered, concrete implementation step>
[ ] <ordered, concrete implementation step>
[ ] <test/validation step>
[ ] <edge-case/risk verification step>

## Edge cases and risks
- <risk or edge case and how the implementation will handle it>

## Tests / validation
- <specific tests or commands to run after approval>

## Open questions
- <only genuinely blocking question(s), maximum 3>

Keep the plan concrete and implementation-oriented. Mention actual files/modules and commands when known. Avoid vague steps and unnecessary abstractions.

### Phase 3 — STOP

After presenting the plan, **STOP**.

Do not continue into implementation in the same turn.

Wait for an explicit user approval such as:
- "approve"
- "approved"
- "go ahead"
- "implement it"
- "execute the plan"
- "yes, proceed"

If the user requests changes to the plan, revise the plan and stop again.

If the user asks a question about the plan, answer it without modifying files, then stop again unless the user explicitly approves execution.

## Phase 4 — Execute only after approval

Only after explicit approval:

1. Re-read the approved plan.
2. Implement only the approved scope.
3. Avoid introducing abstractions or touching unrelated files.
4. Run the planned tests/validation.
5. Report what changed, what was tested, and any deviations from the approved plan.

If implementation reveals that the approved plan is materially wrong or incomplete, stop before expanding scope and ask for approval of the revised approach.

## Important distinction

A user asking to "build X" is **not** approval to immediately modify files when this skill is active. Planning and execution are separate phases.

The approval must occur after the plan is presented.
