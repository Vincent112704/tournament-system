## 1. Data model

- [Entity relationship diagram](#appendix-a-entity-relationship-diagram): Mermaid transcription of the supplied **Untitled Diagram**, covering tournaments, divisions, registrations, brackets, players, and matches.


## Appendix A. Entity relationship diagram

The following conceptual ERD transcribes the supplied **Untitled Diagram**. The named shapes overlaid on unnamed rectangles are represented as the associative entities `TOURNAMENT_PLAYER` and `DIVISION_TOURNAMENT`. Attributes and primary keys follow the source; Entities without attributes in the source remain without attributes here.

```mermaid
erDiagram
    TOURNAMENT {
        uuid tournament_id PK
        string tournament_name
        date date
        string venue
        string time
        string organizer
    }

    PLAYER {
        uuid player_id PK
        string name
        int age
        string coach
        string team
    }

    WEIGHT_DIVISION {
        string division_name PK
        int min_weight
        int max_weight
    }

    MATCH {
        uuid match_id PK
        uuid player_1 FK "References TOURNAMENT_PLAYER(tournament_player_id)"
        uuid player_2 FK "References TOURNAMENT_PLAYER(tournament_player_id)"
        uuid winner_id FK "References TOURNAMENT_PLAYER(tournament_player_id)"
        uuid bracket_id FK 
    }

    DIVISION_TOURNAMENT {
        uuid division_tournament PK
        uuid tournament_id FK
        string division_name FK
    }
    
    TOURNAMENT_PLAYER {
        uuid tournament_player_id PK
        uuid player_id FK
        uuid division_tournament FK
        float registered_weight_kg 
    }

    BRACKET {
        uuid division_tournament FK
        uuid bracket_id PK
        string bracket_name

    }

    
    PLAYER ||--o{ TOURNAMENT_PLAYER : "has registrations"
    WEIGHT_DIVISION ||--|{ DIVISION_TOURNAMENT : "is in"
    TOURNAMENT ||--|{ DIVISION_TOURNAMENT : "has divisions"
    DIVISION_TOURNAMENT ||--o{ TOURNAMENT_PLAYER : "has registrations"
    DIVISION_TOURNAMENT ||--|{ BRACKET : "has brackets"
    BRACKET ||--o{ MATCH : "has matches"
    TOURNAMENT_PLAYER ||--|{ MATCH : "occupies player 1 slot"
    TOURNAMENT_PLAYER ||--|{ MATCH : "occupies player 2 slot"
    TOURNAMENT_PLAYER ||--|{ MATCH : "occupies winner ID slot"
    MATCH |o--o| MATCH : "next-match"
```

### Interpretation and open questions

- Each registration connects one tournament and one player; a tournament or player may have no registrations or many. Each registration also belongs to one tournament division, which may have no registrations or many.
- `DIVISION_TOURNAMENT` associates a weight division with a tournament. The diagram places `(1,1)` beside each parent and `(1,N)` beside the association; the Mermaid relationships interpret these as one parent per association and one or more associations per parent. Confirm these minimum counts before implementing constraints.
- Each bracket belongs to one tournament division, and each match belongs to one bracket. The source shows one or more brackets per tournament division and zero or more matches per bracket.
- The registration–match relationship carries `(0,2)` near `TOURNAMENT_PLAYER` and `(0,N)` near `MATCH`. Mermaid cannot encode an upper bound of two, so the line preserves the association and its label records the source limit. Confirm whether the two refers to registered participants per match; do not implement it as a two-match limit per player without clarification.
- The match self-relationship is labeled `contains`, with a single `(0,1)` annotation and an endpoint drawn back to the match without a target ID. The optional one-to-one line is a provisional transcription; the inverse cardinality and whether this means the next match remain undefined. It does not specify how two feeder matches advance into a later round.
- The source does not define keys for `WEIGHT_DIVISION`, `DIVISION_TOURNAMENT`, `TOURNAMENT_PLAYER`, or `BRACKET`, nor foreign-key columns, score fields, or match states. `player_1`, `player_2`, and `winner` are retained as drawn; their references and nullability must be defined when creating the database schema.
