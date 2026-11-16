BEGIN;

CREATE TABLE public.tournament (
    tournament_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_name text NOT NULL CHECK (btrim(tournament_name) <> ''),
    date date NOT NULL,
    venue text NOT NULL CHECK (btrim(venue) <> ''),
    time time without time zone NOT NULL,
    organizer text NOT NULL CHECK (btrim(organizer) <> '')
);

CREATE TABLE public.player (
    player_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (btrim(name) <> ''),
    age integer NOT NULL CHECK (age >= 0),
    coach text NOT NULL CHECK (btrim(coach) <> ''),
    team text NOT NULL CHECK (btrim(team) <> '')
);

CREATE TABLE public.weight_division (
    division_name text PRIMARY KEY CHECK (btrim(division_name) <> ''),
    min_weight numeric(5,2) NOT NULL,
    max_weight numeric(5,2) NOT NULL,
    CHECK (min_weight >= 0 AND max_weight >= min_weight AND max_weight < 'Infinity'::numeric)
);

CREATE TABLE public.division_tournament (
    division_tournament uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tournament_id uuid NOT NULL REFERENCES public.tournament ON DELETE RESTRICT,
    division_name text NOT NULL REFERENCES public.weight_division ON DELETE RESTRICT,
    UNIQUE (tournament_id, division_name)
);

CREATE TABLE public.tournament_player (
    tournament_player_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id uuid NOT NULL REFERENCES public.player ON DELETE RESTRICT,
    division_tournament uuid NOT NULL REFERENCES public.division_tournament ON DELETE RESTRICT,
    registered_weight_kg numeric(5,2) NOT NULL
        CHECK (registered_weight_kg > 0 AND registered_weight_kg < 'Infinity'::numeric),
    UNIQUE (player_id, division_tournament)
);

CREATE TABLE public.bracket (
    bracket_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    division_tournament uuid NOT NULL REFERENCES public.division_tournament ON DELETE RESTRICT,
    bracket_name text NOT NULL CHECK (btrim(bracket_name) <> '')
);

CREATE TABLE public.match (
    match_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    bracket_id uuid NOT NULL REFERENCES public.bracket ON DELETE RESTRICT,
    round_number integer NOT NULL CHECK (round_number > 0),
    player_1 uuid REFERENCES public.tournament_player ON DELETE RESTRICT,
    player_2 uuid REFERENCES public.tournament_player ON DELETE RESTRICT,
    winner_id uuid REFERENCES public.tournament_player ON DELETE RESTRICT,
    next_match_id uuid REFERENCES public.match ON DELETE RESTRICT,
    next_match_slot smallint,
    CHECK (player_1 IS NULL OR player_2 IS NULL OR player_1 <> player_2),
    CHECK (winner_id IS NULL OR
        winner_id IS NOT DISTINCT FROM player_1 OR winner_id IS NOT DISTINCT FROM player_2),
    CHECK ((next_match_id IS NULL AND next_match_slot IS NULL) OR
        (next_match_id IS NOT NULL AND next_match_slot IS NOT NULL AND next_match_slot IN (1, 2))),
    CHECK (next_match_id IS NULL OR next_match_id <> match_id),
    UNIQUE (next_match_id, next_match_slot)
);

CREATE INDEX division_tournament_division_idx ON public.division_tournament (division_name);
CREATE INDEX tournament_player_division_idx ON public.tournament_player (division_tournament);
CREATE INDEX bracket_division_idx ON public.bracket (division_tournament);
CREATE INDEX match_bracket_idx ON public.match (bracket_id);
CREATE INDEX match_player_1_idx ON public.match (player_1);
CREATE INDEX match_player_2_idx ON public.match (player_2);
CREATE INDEX match_winner_idx ON public.match (winner_id);

-- Serialize integrity-sensitive writes before row locks are acquired. This modest
-- single-operator workload favors simple correctness over write concurrency.
-- Serializable/repeatable-read snapshots could hide a preceding transaction's
-- changes after waiting; require READ COMMITTED for these write workflows.
CREATE FUNCTION public.lock_tournament_write() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Tournament writes require READ COMMITTED isolation';
    END IF;
    PERFORM pg_advisory_xact_lock(173021, 1);
    RETURN NULL;
END;
$$;

-- Validate the resulting state after each statement, including parent updates.
CREATE FUNCTION public.validate_tournament_integrity() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.tournament_player p
        JOIN public.division_tournament d USING (division_tournament)
        JOIN public.weight_division w USING (division_name)
        WHERE p.registered_weight_kg NOT BETWEEN w.min_weight AND w.max_weight
    ) THEN
        RAISE EXCEPTION 'Registration weight is outside its division boundaries';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.match m
        JOIN public.bracket b USING (bracket_id)
        JOIN public.tournament_player p ON p.tournament_player_id IN (m.player_1, m.player_2)
        WHERE p.division_tournament <> b.division_tournament
    ) THEN
        RAISE EXCEPTION 'Match participants must belong to the bracket division';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.match m JOIN public.match n ON n.match_id = m.next_match_id
        WHERE n.bracket_id <> m.bracket_id OR n.round_number <= m.round_number
    ) THEN
        RAISE EXCEPTION 'Advancement must target a later round in the same bracket';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.match m JOIN public.match n ON n.match_id = m.next_match_id
        WHERE (CASE m.next_match_slot WHEN 1 THEN n.player_1 ELSE n.player_2 END) IS NOT NULL
          AND (CASE m.next_match_slot WHEN 1 THEN n.player_1 ELSE n.player_2 END)
              IS DISTINCT FROM m.winner_id
    ) THEN
        RAISE EXCEPTION 'Destination slot must contain only its feeder winner';
    END IF;

    RETURN NULL;
END;
$$;

CREATE FUNCTION public.protect_finalized_match() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    IF OLD.winner_id IS NOT NULL THEN
        IF TG_OP = 'DELETE' THEN
            RAISE EXCEPTION 'Finalized matches cannot be deleted';
        ELSIF NEW IS DISTINCT FROM OLD THEN
            RAISE EXCEPTION 'Finalized matches cannot be changed';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

-- Deferred validation permits the function to record a winner and advance it
-- in two statements, while still checking direct SQL writes at commit.
CREATE FUNCTION public.check_match_commit() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.match m JOIN public.match feeder ON feeder.next_match_id = m.match_id
        WHERE m.winner_id IS NOT NULL AND feeder.winner_id IS NULL
    ) THEN
        RAISE EXCEPTION 'Feeder matches must be finalized first';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.match m JOIN public.match n ON n.match_id = m.next_match_id
        WHERE m.winner_id IS NOT NULL AND
          (CASE m.next_match_slot WHEN 1 THEN n.player_1 ELSE n.player_2 END)
              IS DISTINCT FROM m.winner_id
    ) THEN
        RAISE EXCEPTION 'Finalized winner must occupy the advancement slot';
    END IF;
    RETURN NULL;
END;
$$;

CREATE FUNCTION public.protect_registration() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    IF (NEW.player_id, NEW.division_tournament, NEW.tournament_player_id)
       IS DISTINCT FROM (OLD.player_id, OLD.division_tournament, OLD.tournament_player_id)
       AND EXISTS (SELECT 1 FROM public.match WHERE
           player_1 = OLD.tournament_player_id OR player_2 = OLD.tournament_player_id) THEN
        RAISE EXCEPTION 'Cannot reassign a registration used in a match';
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION public.prevent_tournament_truncate() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    RAISE EXCEPTION 'Use DELETE with integrity checks instead of TRUNCATE';
END;
$$;

-- Install statement locks on all related tables, including TRUNCATE protection.
DO $$
DECLARE table_name text;
BEGIN
    FOREACH table_name IN ARRAY ARRAY['tournament', 'player', 'weight_division',
        'division_tournament', 'tournament_player', 'bracket', 'match'] LOOP
        EXECUTE format('CREATE TRIGGER lock_write BEFORE INSERT OR UPDATE OR DELETE ON public.%I
            FOR EACH STATEMENT EXECUTE FUNCTION public.lock_tournament_write()', table_name);
        EXECUTE format('CREATE TRIGGER validate_integrity AFTER INSERT OR UPDATE OR DELETE ON public.%I
            FOR EACH STATEMENT EXECUTE FUNCTION public.validate_tournament_integrity()', table_name);
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
        EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC', table_name);
        EXECUTE format('CREATE TRIGGER prevent_truncate BEFORE TRUNCATE ON public.%I
            FOR EACH STATEMENT EXECUTE FUNCTION public.prevent_tournament_truncate()', table_name);
    END LOOP;
END;
$$;

CREATE TRIGGER protect_finalized BEFORE UPDATE OR DELETE ON public.match
FOR EACH ROW EXECUTE FUNCTION public.protect_finalized_match();

CREATE TRIGGER protect_registration BEFORE UPDATE ON public.tournament_player
FOR EACH ROW EXECUTE FUNCTION public.protect_registration();

CREATE CONSTRAINT TRIGGER check_advancement AFTER INSERT OR UPDATE OR DELETE ON public.match
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.check_match_commit();

CREATE FUNCTION public.finalize_match(p_match_id uuid, p_winner_id uuid) RETURNS void
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
DECLARE current_match public.match%ROWTYPE;
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Tournament writes require READ COMMITTED isolation';
    END IF;
    PERFORM pg_advisory_xact_lock(173021, 1);
    SELECT * INTO STRICT current_match FROM public.match WHERE match_id = p_match_id FOR UPDATE;
    IF p_winner_id IS NULL OR
       (p_winner_id IS DISTINCT FROM current_match.player_1 AND
        p_winner_id IS DISTINCT FROM current_match.player_2) THEN
        RAISE EXCEPTION 'Winner must be a match participant';
    END IF;
    IF current_match.winner_id IS NOT NULL THEN
        IF current_match.winner_id = p_winner_id THEN RETURN; END IF;
        RAISE EXCEPTION 'Match already finalized with a different winner';
    END IF;
    IF EXISTS (SELECT 1 FROM public.match
        WHERE next_match_id = p_match_id AND winner_id IS NULL) THEN
        RAISE EXCEPTION 'Feeder matches must be finalized first';
    END IF;
    UPDATE public.match SET winner_id = p_winner_id WHERE match_id = p_match_id;
    IF current_match.next_match_id IS NOT NULL THEN
        UPDATE public.match SET
            player_1 = CASE WHEN current_match.next_match_slot = 1 THEN p_winner_id ELSE player_1 END,
            player_2 = CASE WHEN current_match.next_match_slot = 2 THEN p_winner_id ELSE player_2 END
        WHERE match_id = current_match.next_match_id;
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.lock_tournament_write() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validate_tournament_integrity() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.protect_finalized_match() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_match_commit() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.protect_registration() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prevent_tournament_truncate() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.finalize_match(uuid, uuid) FROM PUBLIC;

COMMIT;
