<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

<!-- START:Project Overview -->

Build a web-based arnis tournament management system for Dumaguete Arnis Association (DUMAA). Tournament managers use the private management interface to register players, configure events/tournaments, generate brackets, record results, and control match progression. The public can view a live scoreboard without receiving access to management capabilities.

<!-- END:Project Overview -->

<!-- START:Functional Requirements -->

## 1. Player Management

### FR-01: Register Players
**Actor:** Admin

The system must allow the admin to register players.

- Capture and persist the required player information.
- Validate required fields before saving.
- Prevent invalid registrations according to the defined validation rules.

### FR-02: Manage Registered Players
**Actor:** Admin

The system must allow the admin to manage registered players.

- View and search registered players.
- View individual player details.
- Edit player information.
- Remove or deactivate player registrations as permitted by the tournament's current state.
- Preserve data integrity when a player is associated with an existing tournament, bracket, or match.

## 2. Tournament/Event Management

### FR-03: Manage Tournaments and Events
**Actor:** Admin

The system must allow the admin to create, view, edit, and delete tournaments/events.

- Create a tournament/event with the required information.
- View tournament/event details.
- Update tournament/event information.
- Delete a tournament/event subject to data integrity constraints.
- Manage the tournament's lifecycle and associated data.

## 3. Bracket Generation and Progression

### FR-04: Generate Single-Elimination Brackets
**Actor:** System

The system must automatically generate a single-elimination bracket for each applicable weight division within a tournament.

- Include eligible players registered for the corresponding tournament and weight division.
- Ensure each match has the required participant slots.
- Support byes when the number of eligible players is not a power of two.
- Persist generated matches and their bracket relationships.
- Prevent duplicate bracket generation unless an explicit regeneration workflow is supported.
- Preserve the relationship between tournament, weight division, participants, and matches.

### FR-05: Automatically Progress Brackets
**Actor:** System

The system must automatically advance the winner of a completed match to the appropriate participant slot in the next round.

- Determine the winner from the match's recorded result.
- Identify the next match and the correct participant slot.
- Update the bracket progression when a valid match result is finalized.
- Handle byes according to the bracket rules.
- Prevent progression when a match result is incomplete or invalid.
- Ensure that a match winner is not advanced more than once for the same finalized result.

## 4. Public Scoreboard

### FR-06: Display Public Scoreboard
**Actor:** Public Viewer

The system must provide a publicly accessible scoreboard view.

- Display the relevant match information and current scores.
- Clearly identify the competitors and their respective scores.
- Display the match status where applicable.
- Reflect the latest scoreboard state without requiring a manual page refresh, subject to the chosen real-time update mechanism.

### FR-07: Manage Scoreboard in Real Time
**Actor:** Admin

The system must allow the admin to modify the score of an active match in real time.

- Add points to a competitor's score.
- Deduct points from a competitor's score.
- Validate score modifications against the defined scoring rules.
- Persist score changes.
- Propagate score updates to connected public scoreboard viewers.
- Ensure unauthorized users cannot modify scores.
- Maintain a reliable record of score changes where required for auditing and dispute resolution.

## 5. Business Rules and Constraints

- Each tournament may contain multiple weight divisions.
- Each bracket belongs to a specific tournament and weight division.
- Only eligible players may participate in a generated bracket.
- Each match must belong to the appropriate bracket and round.
- A finalized match result determines bracket progression.
- Score updates and bracket progression must preserve data consistency.
- Administrative operations must enforce appropriate authorization.
- Destructive operations must account for dependent records and existing match results.

## 6. Acceptance Criteria

The implementation is considered functionally complete when:

1. An admin can register, view, edit, and manage players.
2. An admin can create, view, edit, and delete tournaments/events.
3. The system generates a valid single-elimination bracket for each applicable weight division.
4. A public viewer can access the scoreboard without administrative permissions.
5. An admin can add or deduct points and see the updated scores reflected on the public scoreboard.
6. Finalizing a match result automatically advances the winner to the correct next-round match.
7. The system prevents invalid operations from corrupting player, match, score, or bracket data.

<!-- END:Functional Requirements -->

<!-- START:Architecture Decisions -->
Use a **modular monolith**:

- **Web application:** Next.js + TypeScript, hosted on Vercel.
- **Database:** Supabase PostgreSQL.
- **Authentication:** Supabase Auth, with manager access controlled by server-side authorization.
- **Realtime updates:** Supabase Realtime for public scoreboard updates.
- **Runtime validation:** Zod schemas at application boundaries.
- **Types:** Supabase-generated database types plus separately defined domain and API types.
- **Testing:** Unit tests for pure domain logic; integration tests for database workflows; end-to-end tests for critical manager and public journeys.

This is a proposed baseline, not a requirement to use every library from day one. Confirm versions and platform limits during implementation.
<!-- END:Architecture Decisions -->

<!-- START:Code Organization -->

Keep the first version simple. Add packages or extra layers only when they provide a real boundary.

```text
tournament-system/
├── app/
│   ├── (manager)/
│   │   ├── players/
│   │   ├── events/
│   │   ├── divisions/
│   │   └── matches/
│   ├── scoreboard/
│   └── api/
│       └── ...
├── components/
├── modules/
│   ├── players/
│   │   ├── repository/
│   │   └── service/
│   ├── tournament/
│   │   ├── repository/
│   │   └── service/
│   ├── brackets/
│   │   ├── repository/
│   │   └── service/
│   └── matches/
│       ├── repository/
│       └── service/
├── lib/
│   ├── supabase/
│   ├── auth/
│   └── validation/
├── database/
│   ├── migrations/
│   └── seed/
├── schema/
└── tests/
    ├── unit/
    ├── integration/
    └── e2e/
```

Possible responsibility boundaries:

- **UI/components:** Rendering and user interaction. They should not be the sole place where rules are enforced.
- **Route Handlers:** HTTP input/output, authentication/authorization, and orchestration of use cases.
- **Business logic (service):** Bracket generation, valid match transitions, winner advancement rules, and other rules that can be tested without a database.
- **Database layer(repository):** Queries, constraints, and transaction/RPC calls.
- **Validation:** Runtime schemas for incoming requests and other untrusted data.

Do not create abstractions just to match this tree. For a small codebase, directories can begin flatter and be split when responsibilities become substantial.

<!-- END:Code Organization -->

<!-- START:Type safety and validation -->

Use different types for different purposes instead of expecting one type to solve everything.

- **Generated Supabase database types:** Reflect database tables, views, and database operations.
- **Zod schemas:** Validate untrusted request payloads at runtime.
- **Domain types:** Express concepts and invariants used by bracket and match logic.
- **UI types:** Represent presentation needs where they differ from database or domain shapes.

Example request schema:

```ts
import { z } from "zod";

export const SubmitScoreSchema = z.object({
  matchId: z.string().uuid(),
  redScore: z.number().int().nonnegative(),
  blueScore: z.number().int().nonnegative(),
});

export type SubmitScoreInput = z.infer<typeof SubmitScoreSchema>;
```

This is only an illustration. The final schema must reflect the sport's actual scoring model. A payload passing Zod validation can still violate domain rules—for example, a score may be structurally valid while the match is already completed. Validate those rules on the server too.

Generate and refresh Supabase database types from the actual schema as part of the development workflow. Do not manually duplicate the database schema in several places.

<!-- END:Type safety and validation -->

<!-- START:Testing strategy -->

Prioritize correctness around player and tournament management, bracket generation, match results, real-time scoreboard updates, data integrity, and authorization.

### Unit tests

- Player registration and management validation, including required fields and invalid player data.
- Tournament/event creation, editing, and deletion validation.
- Weight division assignment and player eligibility rules.
- Bracket generation for zero, one, two, odd, power-of-two, and larger entrant counts.
- Correct bye assignment and automatic advancement where applicable.
- Correct participant placement and match relationships across bracket rounds.
- Winner advancement after a match result is finalized.
- Valid and invalid match-state transitions.
- Score additions, deductions, and score validation rules.
- Prevention of duplicate winner advancement for the same finalized result.
- Deterministic bracket generation for identical inputs and seeding policies, once defined.

### Integration tests

- Database constraints for duplicate registrations, invalid references, and inconsistent tournament, division, player, and match relationships.
- Player registration and management workflows, including edits and removal constraints.
- Tournament/event creation, updates, and deletion with dependent records.
- Bracket persistence, match relationships, bye handling, and progression.
- Match-result finalization, winner advancement, and audit entry within a consistent transaction boundary.
- Score modifications, persistence, and audit history.
- Duplicate or retried match-result and score-update requests.
- Conflicting concurrent attempts to finalize the same match or modify the same scoreboard.
- Authorization for administrative operations versus public read-only requests.
- Public scoreboard retrieval and propagation of committed score changes.
- Row-level security (RLS) behavior for the selected Supabase access model, if RLS is used.

### End-to-end tests

- Admin signs in and creates a tournament/event.
- Admin registers players and assigns them to the appropriate weight divisions.
- Admin generates and views a single-elimination bracket for each applicable division.
- Generated brackets correctly handle byes and valid participant counts.
- Admin updates player information and manages tournament/event records according to the permitted lifecycle.
- Admin adds points to and deducts points from a competitor's score.
- Public viewers see scoreboard updates without manually refreshing the page.
- Admin finalizes a match result, and the winner advances to the correct next-round match.
- Public viewers see the updated bracket and relevant match status after result finalization.
- Invalid match results, unauthorized score changes, and unauthorized management actions are rejected.
- Important administrative actions are recorded in the audit history.

### Testing principles

- Test business rules independently of framework and database implementation details where practical.
- Verify persisted state, not only successful API responses.
- Test failure scenarios and transaction rollback to ensure partial operations do not corrupt data.
- Test real-time behavior alongside the underlying persisted state to distinguish delivery failures from data consistency failures.
- Avoid testing undefined policies, such as seeding algorithms or special match outcomes, until those policies are explicitly specified.

<!-- END:Testing strategy -->