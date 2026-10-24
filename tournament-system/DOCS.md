# Arnis Tournament Management System

> **Status:** Initial architecture and requirements draft  
> **Purpose:** A reference document for planning, implementation, and verification.  
> **Important:** This document captures current decisions and open questions. It is not a claim that every rule has been finalized.

## 1. Project overview

Build a web-based arnis tournament management system for Dumaguete Arnis Association (DUMAA). Tournament managers use the private management interface to register players, configure events and divisions, generate brackets, record results, and control match progression. The public can view a live scoreboard without receiving access to management capabilities.

The system is initially intended for a small number of operators and a modest database, so the architecture should prioritize correctness, maintainability, and simplicity over infrastructure complexity.

### Primary requirements

- Automated **single-elimination bracketing** for combat-sport tournaments.
- Manager-only authentication for the administrative interface.
- A scoreboard that the public can view and that updates as match data changes.
- Support for approximately **3–5 concurrent tournament managers**.
- Support for at least **1,000 player records**; design database constraints and queries properly rather than treating this as a scaling challenge.
- One organization managing multiple events over time.
- A modular monolith with TypeScript across the application and Supabase for database and selected backend services.

## 2. Product boundaries

### In scope for the initial version

- Manager sign-in and authorization.
- Player records.
- Events and divisions/categories.
- Player registrations in divisions.
- Bracket generation and display.
- Match status and result management.
- Winner advancement through a bracket.
- Public, read-only bracket and scoreboard views.
- Live scoreboard updates.
- Basic audit history for important management actions.
- Validation and tests for bracket generation and match-result workflows.

### Not decided yet

These are requirements questions, not implementation details to guess:

- Bracketing logic (rules for bracketing players and constraints)
- How divisions are defined: age, weight class, gender category, or other criteria.
- Seeding rules and how byes are assigned.
- How is scoreboard displayed from client ( do admins select from bracket? auto progression? etc. )


## 3. Architecture decisions

### Chosen direction

Use a **modular monolith**:

- **Web application:** Next.js + TypeScript, hosted on Vercel.
- **Database:** Supabase PostgreSQL.
- **Authentication:** Supabase Auth, with manager access controlled by server-side authorization.
- **Realtime updates:** Supabase Realtime for public scoreboard updates.
- **Runtime validation:** Zod schemas at application boundaries.
- **Types:** Supabase-generated database types plus separately defined domain and API types.
- **Testing:** Unit tests for pure domain logic; integration tests for database workflows; end-to-end tests for critical manager and public journeys.

This is a proposed baseline, not a requirement to use every library from day one. Confirm versions and platform limits during implementation.

### Why a modular monolith?

The system has a small number of concurrent managers and a straightforward initial workflow. Separate microservices would add deployment, networking, observability, and consistency costs without a demonstrated need.

Keep the code divided by domain responsibilities so individual modules can be changed and tested independently. A modular monolith does **not** mean putting all logic into one file or allowing every module to access every other module's internals.

### Why Supabase?

Supabase provides managed PostgreSQL, authentication, and realtime capabilities in one platform. PostgreSQL is the durable source of truth for players, registrations, brackets, matches, and results.

Supabase simplifies infrastructure, but it does not remove the need to design constraints, authorization, transactions, or business rules correctly.

### Why TypeScript for both frontend and backend?

Using TypeScript across the web application makes it easier to reuse types and validation definitions. It also lets the domain logic be tested independently of UI components and HTTP handlers.

Sharing a type is not the same as validating input. Browser data is untrusted: validate incoming requests at runtime and apply domain rules on the server.

### Why Next.js Route Handlers initially?

Next.js Route Handlers can provide the server-side API and domain orchestration needed for this initial scope. A separate Hono, Express, or Fastify service is not required unless concrete needs emerge, such as independent deployment, a separate worker process, or a different runtime.

Vercel hosts the web application; Supabase remains the managed database/auth/realtime provider. This is one application codebase, not literally one service or one database.

## 4. High-level architecture

```text
                    ┌───────────────────────────┐
                    │        Web clients        │
                    │                           │
                    │ Manager dashboard         │
                    │ Public scoreboard         │
                    └─────────────┬─────────────┘
                                  │ HTTPS
                                  ▼
                    ┌───────────────────────────┐
                    │ Next.js application       │
                    │                           │
                    │ UI / Route Handlers       │
                    │ Authentication checks     │
                    │ Authorization checks      │
                    │ Domain/use-case logic     │
                    │ Request validation        │
                    └───────┬───────────┬───────┘
                            │           │
                 queries / writes       │ realtime subscription
                            │           │
                            ▼           ▼
                 ┌────────────────┐  ┌────────────────┐
                 │ Supabase       │  │ Supabase       │
                 │ PostgreSQL     │  │ Realtime       │
                 │ source of truth│  │ change delivery│
                 └────────────────┘  └────────────────┘
```

**Important distinction:** The diagram is conceptual. Realtime notifications tell clients that data changed; they are not the authoritative match result. Clients should fetch the persisted state on initial load and after reconnecting.

### Request flow: recording a result

1. A manager submits a result through the authenticated interface.
2. The server verifies the manager's identity and permission to perform the action.
3. The request is validated for shape and business meaning.
4. A database transaction validates the match state, records the result, marks the match complete, advances the winner if appropriate, and records an audit entry.
5. The committed database changes become available to the public scoreboard.
6. The scoreboard updates from realtime notifications and can refetch persisted state to recover from missed notifications.

The critical steps in item 4 must be atomic: they should all succeed or all roll back.

## 5. Suggested code organization

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
- **Domain logic:** Bracket generation, valid match transitions, winner advancement rules, and other rules that can be tested without a database.
- **Database layer:** Queries, constraints, and transaction/RPC calls.
- **Validation:** Runtime schemas for incoming requests and other untrusted data.

Do not create abstractions just to match this tree. For a small codebase, directories can begin flatter and be split when responsibilities become substantial.

## 6. Initial domain model

The entities below are a starting point. Exact columns and constraints must be refined with the organization’s tournament rules.

### `managers`

Represents authorized tournament operators or an application-level manager profile.

Possible fields:

- `id`
- `auth_subject` — links to the authenticated Supabase Auth identity
- `display_name`
- `role` — keep simple if all managers have the same permissions
- `is_active`
- `created_at`


### `players`

Represents a person independently of a particular event or division.

Possible fields:

- `id`
- `full_name`
- `date_of_birth` — only if required for eligibility
- other necessary player profile fields
- `created_at`
- `updated_at`

Avoid storing unnecessary sensitive personal information.

### `tournament`

Represents a tournament event. The organization may create many events over time.

Possible fields:

- `id`
- `name`
- `venue`
- `starts_at`
- `ends_at`
- `status` — for example, draft, published, in progress, completed, or cancelled
- `created_at`

The exact status values and transition rules still need to be defined.

### `divisions`

Represents a competition category within an event.

Possible fields:

- `id`
- `event_id`
- `name`
- sport/discipline and applicable category attributes
- `status`
- `created_at`

A division belongs to one event. The category attributes depend on the actual sport and rules.

### `registrations`

Represents a player's entry into a particular division. This is deliberately separate from `players`: the same player may enter different divisions or events, subject to the organization's rules.

Possible fields:

- `id`
- `player_id`
- `division_id`
- `registration_status`
- `seed` — nullable until seeding is assigned, if seeding is used
- eligibility/verification fields only if needed
- `created_at`

Add a database uniqueness constraint for the intended rule, commonly one registration per player per division. Confirm whether re-entry or duplicate registrations are ever legitimate.

### `brackets`

Represents a generated bracket version for a division.

Possible fields:

- `id`
- `division_id`
- `version`
- `format` — initially single elimination
- `status` — for example, draft, published, in progress, or completed
- `generated_at`
- `published_at`

A version is useful because regenerating a bracket after results exist can invalidate match assignments and recorded outcomes. The system should not silently overwrite an active bracket.

### `matches`

Represents a match slot in a bracket.

Possible fields:

- `id`
- `bracket_id`
- `round_number`
- `match_number`
- `red_registration_id` / `blue_registration_id` — use the sport's actual competitor terminology where appropriate
- `winner_registration_id`
- `status` — for example, pending, ready, in progress, completed, or cancelled
- `winner_to_match_id`
- `winner_to_slot`
- timestamps such as `started_at` and `completed_at`

Use explicit advancement relationships instead of relying only on arithmetic such as “the next match is match number plus one.” This makes the bracket structure easier to reason about and validate.

A bye should be represented deliberately in the bracket-generation and match-state rules. Do not treat a bye as an ordinary scored match without deciding what that means for the domain.

### `match_results`

Represents the result details and how they were confirmed.

Possible fields:

- `id`
- `match_id`
- `outcome_type`
- score or round details appropriate to the sport
- `confirmed_by`
- `confirmed_at`
- optional correction/supersession fields if results can be amended

Decide whether a match can have only one current result row or whether result history must be retained. Do not silently overwrite a result if an audit trail is required.

### `audit_logs`

Records important actions for accountability and troubleshooting.

Possible fields:

- `id`
- `manager_id`
- `entity_type`
- `entity_id`
- `action`
- `occurred_at`
- structured details describing the change, without unnecessarily copying sensitive data

At minimum, consider logging bracket generation/publication, result confirmation/correction, and important event or registration changes.

### Relationship overview

```text
Event 1 ─── many Divisions
Division 1 ─── many Registrations
Player 1 ─── many Registrations
Division 1 ─── many Bracket versions
Bracket 1 ─── many Matches
Match 1 ─── result record(s), according to the chosen history model
Match ─── may advance its winner to another Match
Manager 1 ─── many audit log entries
```

## 7. Bracket generation and advancement

### Initial format

The initial format is **single elimination**: a competitor is eliminated from the division after a loss, subject to any special rules the organization defines.

For `N` valid entrants, if the bracket is a conventional single-elimination tournament with one overall winner and no third-place match:

- `P` = the smallest power of two greater than or equal to `N`.
- Number of byes in the opening round = `P - N`.
- Number of matches required to produce one winner = `N - 1`.

These formulas are useful checks, not a complete seeding or bracket-placement algorithm. They do not determine which competitors receive byes or who faces whom.

### Design rules

1. Implement bracket generation as deterministic TypeScript domain logic, separate from UI, HTTP handlers, and database access.
2. Input should explicitly include the eligible registrations, any seeds, and the applicable format/rules.
3. Output should describe the bracket structure and advancement links. Persist that result only after it passes validation.
4. Use stable identifiers for registrations and matches; do not rely on display names as identity.
5. Define how byes, walkovers, withdrawals, disqualifications, and corrections affect advancement.
6. Make generation reproducible for the same inputs and rules, where practical.
7. Validate invariants before publishing a bracket.
8. Once matches have started, do not silently regenerate the bracket. Use a deliberate correction/revision workflow that accounts for downstream matches and audit history.

### Useful invariants to test

- Every scheduled competitor belongs to the relevant division.
- A registration cannot occupy two slots in the same bracket unless the rules explicitly allow it.
- Every match has a unique position within its bracket.
- Advancement links point to valid matches and valid slots.
- A winner is one of the match's eligible competitors, except where a separately defined outcome rule applies.
- A completed match cannot be advanced twice by duplicate requests.
- A bracket with `N` entrants produces the expected number of matches for the chosen format.
- Byes are assigned according to the selected rules and cannot create contradictory match states.

### Result confirmation should be atomic

Do not implement result confirmation as unrelated client-side writes. The operation should validate and commit together:

1. Confirm the match is in a state that permits a result.
2. Confirm the submitted winner/outcome is valid for the match and the sport's rules.
3. Store the result and mark the match completed.
4. Advance the winner or resolve the next match according to the bracket rules.
5. Record an audit event.
6. Commit all changes as one transaction.

A carefully designed PostgreSQL function/RPC can perform this operation transactionally. Another server-side PostgreSQL transaction approach is also valid. Multiple independent Supabase API requests should **not** be assumed to form one transaction.

Use row locking or an appropriate optimistic-concurrency strategy so two managers cannot accidentally confirm conflicting results. Make retry behavior safe, for example by detecting that a result was already processed.

## 8. Authentication, authorization, and data security

Authentication answers “Who is signed in?” Authorization answers “What is this person allowed to do?” The application needs both.

### Manager interface

- Only authenticated, active managers may access management actions.
- Verify authorization on the server for every protected operation; hiding a UI button is not security.
- Disable public self-service manager signup unless the organization explicitly needs it.
- Use a controlled process to invite/create managers and revoke access.
- Record who confirms or corrects results.

### Public scoreboard

- Public access should be read-only.
- Expose only the fields needed to display published events, divisions, brackets, matches, and results.
- Do not expose manager details, private registration data, or unnecessary personal information.
- Subscribe only to the public data that the scoreboard is permitted to see.

### Supabase safeguards

- Never put a Supabase service-role/secret key in browser code or public environment variables.
- Keep server-only secrets on the server.
- Enable and correctly configure Row Level Security (RLS) for tables exposed through Supabase's Data API.
- Apply least-privilege access policies. Do not assume that enabling RLS alone means the policies are correct.
- Validate all incoming requests on the server.
- Use database foreign keys, unique constraints, check constraints, and appropriate indexes as a second line of defense.
- Do not rely on frontend validation for integrity or authorization.

The final RLS policy design depends on whether clients read data directly from Supabase or all access is mediated by the Next.js server. Choose one intentional access model and document its policies rather than mixing approaches casually.

## 9. Realtime scoreboard

The scoreboard should display committed database state, with Supabase Realtime notifying connected clients when relevant records change.

Expected behavior:

- Initial page load fetches the current published state.
- A committed result or match-state change triggers the scoreboard to refresh/update.
- Reconnection or missed notifications causes a refetch so the display can recover.
- Realtime events do not independently determine the winner or advance a bracket.
- Public subscriptions must not leak private data.

Start with Supabase Realtime rather than implementing a custom WebSocket service. Revisit this only if real usage reveals a limitation.

## 10. Type safety and validation

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

## 11. Testing strategy

Prioritize correctness around brackets, results, and permissions.

### Unit tests

- Bracket generation for zero, one, two, odd, and power-of-two entrant counts, plus larger examples.
- Bye assignment and advancement.
- Seed placement once the policy is defined.
- Valid and invalid match-state transitions.
- Special outcomes once supported.
- Deterministic output for identical inputs.

### Integration tests

- Database constraints for duplicate registrations and invalid references.
- Result confirmation, winner advancement, and audit entry in one transaction.
- Duplicate/retried result requests.
- Conflicting concurrent attempts to confirm a match.
- Authorization for manager and public requests.
- RLS behavior for the selected Supabase access model.

### End-to-end tests

- Manager signs in and creates an event/division.
- Manager registers competitors and generates/publishes a bracket.
- Manager confirms a result.
- Public scoreboard reflects the committed result and advancement.
- Unauthorized users cannot perform management actions.

## 12. Deployment and operational approach

Initial deployment can remain simple:

- Deploy the Next.js application to Vercel.
- Use a Supabase project for PostgreSQL, Auth, and Realtime.
- Keep schema changes in version-controlled Supabase migrations.
- Configure environment variables separately for local development, preview, and production.
- Use separate development/test data from real tournament data.
- Add backups and verify the recovery procedure before relying on the system for a live event.
- Add basic error logging and an operational procedure for correcting mistaken results.

Do not add Redis, Kafka, microservices, or a separate backend deployment without a concrete requirement. The current scale does not justify that complexity by itself.

## 13. Implementation sequence

A sensible sequence is to settle domain rules before building a large UI.

1. **Confirm requirements:** Match rules, division definitions, seeding, byes, special outcomes, permissions, and bracket-correction policy.
2. **Define domain states:** Write down valid event, division, bracket, registration, and match states and transitions.
3. **Design the database:** Create the ER model, constraints, indexes, and migration plan.
4. **Build and test bracket logic:** Keep the generator pure and test its invariants before connecting it to the UI.
5. **Implement authentication and authorization:** Establish manager-only write access and public read-only access.
6. **Implement core management flows:** Players, events, divisions, registrations, bracket generation, and publication.
7. **Implement transactional result confirmation:** Include advancement, concurrency safety, and audit history.
8. **Build the public scoreboard:** Fetch initial state and subscribe to allowed realtime changes.
9. **Test end-to-end workflows:** Especially result correction, retries, and access control.
10. **Pilot with sample data:** Have tournament managers verify that the software matches their actual workflow before using it in a live event.

## 14. Verification checklist

Use this list during implementation and review.

### Requirements and domain

- [ ] Confirm the exact sports and competition rules.
- [ ] Confirm division attributes and eligibility requirements.
- [ ] Confirm seeding and bye policies.
- [ ] Confirm special outcomes and score representation.
- [ ] Confirm bracket editing/correction policy after publication and after matches begin.
- [ ] Confirm whether all managers have equal permissions.
- [ ] Confirm which player fields are actually necessary.

### Architecture

- [ ] Next.js + TypeScript is the initial application baseline.
- [ ] Supabase PostgreSQL is the source of truth.
- [ ] Supabase Auth handles manager identity.
- [ ] Supabase Realtime is used for scoreboard change notifications.
- [ ] Domain logic is separate from UI and HTTP handlers.
- [ ] No unnecessary microservices, queue, or cache are introduced without a demonstrated need.

### Data and integrity

- [ ] Database relationships use foreign keys.
- [ ] Duplicate registration rules are enforced by the database.
- [ ] Bracket versions and publication state are represented explicitly.
- [ ] Advancement links are explicit and validated.
- [ ] Result confirmation and advancement are atomic.
- [ ] Concurrent or retried result submissions cannot corrupt the bracket.
- [ ] Important changes are auditable.

### Security

- [ ] Public users cannot perform manager actions.
- [ ] Server-side authorization checks every protected operation.
- [ ] Secret/service-role credentials are server-only.
- [ ] RLS policies are tested for the chosen data-access model.
- [ ] Public data excludes private or unnecessary personal information.
- [ ] Request payloads are validated at runtime.

### User experience and reliability

- [ ] Managers can recover from accidental or invalid submissions through an explicit workflow.
- [ ] The scoreboard refetches state on load/reconnect.
- [ ] Realtime notifications do not replace persisted-state reads.
- [ ] Loading, error, empty, and stale-data states are handled.
- [ ] Backups and recovery have been considered before live deployment.

## 15. Reference documentation

Consult current official documentation during implementation; APIs, defaults, and platform limits can change.

- [Next.js documentation](https://nextjs.org/docs)
- [Next.js Route Handlers](https://nextjs.org/docs/app/building-your-application/routing/route-handlers)
- [Supabase documentation](https://supabase.com/docs)
- [Supabase database type generation](https://supabase.com/docs/guides/api/rest/generating-types)
- [Supabase database security and RLS](https://supabase.com/docs/guides/database/secure-data)
- [Supabase Realtime: Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes)
- [Zod documentation](https://zod.dev/)
- [Vercel documentation](https://vercel.com/docs)

---

## Change log

- **Initial draft:** Captures the agreed direction of a modular monolith using TypeScript, Next.js, Supabase PostgreSQL/Auth/Realtime, single-elimination brackets, manager-only administration, and a public live scoreboard.
- Update this document when a requirement or architecture decision changes. Record the reason for material changes so it remains a reliable reference rather than a stale plan.
