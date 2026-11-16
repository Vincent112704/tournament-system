\set ON_ERROR_STOP on
BEGIN;

-- Run as the migration owner against a disposable database, never production.
CREATE FUNCTION pg_temp.expect_failure(statement text, message_fragment text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE rejected boolean := false;
BEGIN
    BEGIN
        EXECUTE statement;
    EXCEPTION WHEN OTHERS THEN
        IF position(message_fragment IN SQLERRM) = 0 THEN
            RAISE EXCEPTION 'Unexpected error for %: %', statement, SQLERRM;
        END IF;
        rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'Expected rejection: %', statement; END IF;
END;
$$;

-- Exercise the guard before inserts queue deferred constraint trigger events.
SELECT pg_temp.expect_failure('TRUNCATE public.match','instead of TRUNCATE');

DO $$
DECLARE
    t uuid; d uuid; d2 uuid; b uuid; b2 uuid;
    p1 uuid; p2 uuid; p3 uuid; r1 uuid; r2 uuid; r3 uuid; other_r uuid;
    semi uuid; semi2 uuid; final uuid; other_match uuid;
BEGIN
    INSERT INTO public.tournament(tournament_name, date, venue, time, organizer)
        VALUES ('Schema test', '2026-11-16', 'Dumaguete', '09:00', 'DUMAA') RETURNING tournament_id INTO t;
    INSERT INTO public.weight_division VALUES ('test-light', 60, 70), ('test-heavy', 70, 80);
    INSERT INTO public.division_tournament(tournament_id, division_name)
        VALUES (t, 'test-light') RETURNING division_tournament INTO d;
    INSERT INTO public.division_tournament(tournament_id, division_name)
        VALUES (t, 'test-heavy') RETURNING division_tournament INTO d2;
    INSERT INTO public.player(name, age, coach, team) VALUES ('A', 20, 'Coach', 'Team') RETURNING player_id INTO p1;
    INSERT INTO public.player(name, age, coach, team) VALUES ('B', 21, 'Coach', 'Team') RETURNING player_id INTO p2;
    INSERT INTO public.player(name, age, coach, team) VALUES ('C', 22, 'Coach', 'Team') RETURNING player_id INTO p3;
    -- Both inclusive endpoints are accepted, and multi-division entry is allowed.
    INSERT INTO public.tournament_player(player_id, division_tournament, registered_weight_kg)
        VALUES (p1, d, 60) RETURNING tournament_player_id INTO r1;
    INSERT INTO public.tournament_player(player_id, division_tournament, registered_weight_kg)
        VALUES (p2, d, 70) RETURNING tournament_player_id INTO r2;
    INSERT INTO public.tournament_player(player_id, division_tournament, registered_weight_kg)
        VALUES (p3, d, 65) RETURNING tournament_player_id INTO r3;
    INSERT INTO public.tournament_player(player_id, division_tournament, registered_weight_kg)
        VALUES (p2, d2, 70) RETURNING tournament_player_id INTO other_r;
    PERFORM pg_temp.expect_failure(format('INSERT INTO public.division_tournament(tournament_id,division_name) VALUES (%L,%L)',t,'test-light'), 'unique');
    PERFORM pg_temp.expect_failure(format('INSERT INTO public.tournament_player(player_id,division_tournament,registered_weight_kg) VALUES (%L,%L,65)',p1,d), 'unique');
    PERFORM pg_temp.expect_failure(format('UPDATE public.tournament_player SET registered_weight_kg=59 WHERE tournament_player_id=%L',r1), 'boundaries');
    PERFORM pg_temp.expect_failure(format('UPDATE public.tournament_player SET registered_weight_kg=''NaN'' WHERE tournament_player_id=%L',r1), 'check constraint');
    PERFORM pg_temp.expect_failure('UPDATE public.weight_division SET min_weight=61 WHERE division_name=''test-light''', 'boundaries');
    PERFORM pg_temp.expect_failure('INSERT INTO public.player(name,age,coach,team) VALUES ('' '',20,''C'',''T'')','check constraint');
    PERFORM pg_temp.expect_failure('INSERT INTO public.player(name,age,coach,team) VALUES (''X'',-1,''C'',''T'')','check constraint');
    INSERT INTO public.bracket(division_tournament,bracket_name) VALUES (d,'Main') RETURNING bracket_id INTO b;
    INSERT INTO public.bracket(division_tournament,bracket_name) VALUES (d,'Additional') RETURNING bracket_id INTO b2;
    INSERT INTO public.match(bracket_id,round_number) VALUES (b,2) RETURNING match_id INTO final;
    INSERT INTO public.match(bracket_id,round_number) VALUES (b2,3) RETURNING match_id INTO other_match;
    INSERT INTO public.match(bracket_id,round_number,player_1,player_2,next_match_id,next_match_slot)
        VALUES (b,1,r1,r2,final,1) RETURNING match_id INTO semi;
    INSERT INTO public.match(bracket_id,round_number,player_1,next_match_id,next_match_slot)
        VALUES (b,1,r3,final,2) RETURNING match_id INTO semi2;
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET player_2=%L WHERE match_id=%L',r1,semi),'check constraint');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET player_2=%L WHERE match_id=%L',other_r,semi),'bracket division');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET next_match_id=%L WHERE match_id=%L',semi,semi),'check constraint');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET next_match_id=%L WHERE match_id=%L',other_match,semi),'later round');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET next_match_slot=1 WHERE match_id=%L',semi2),'unique');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET next_match_slot=NULL WHERE match_id=%L',semi),'check constraint');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET winner_id=%L WHERE match_id=%L',r3,semi),'check constraint');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET next_match_id=%L,next_match_slot=1 WHERE match_id=%L',semi,final),'later round');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET player_1=%L WHERE match_id=%L',r1,final),'feeder winner');
    PERFORM pg_temp.expect_failure(format('SELECT public.finalize_match(%L,%L)',semi,r3),'participant');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET winner_id=%L WHERE match_id=%L; SET CONSTRAINTS ALL IMMEDIATE',r1,semi),'advancement slot');
    IF (SELECT winner_id IS NOT NULL FROM public.match WHERE match_id=semi) THEN
        RAISE EXCEPTION 'Deferred rejection left an unadvanced winner';
    END IF;
    PERFORM pg_temp.expect_failure(format('DELETE FROM public.player WHERE player_id=%L',p1),'foreign key');
    PERFORM pg_temp.expect_failure(format('DELETE FROM public.tournament WHERE tournament_id=%L',t),'foreign key');
    PERFORM pg_temp.expect_failure(format('UPDATE public.tournament_player SET player_id=%L WHERE tournament_player_id=%L',p3,r1),'registration used');

    -- An incomplete final is rejected. A duplicate destination participant also
    -- rejects advancement and rolls back the source winner in the same call.
    UPDATE public.match SET player_1=r1 WHERE match_id=semi2;
    PERFORM public.finalize_match(semi2,r1);
    PERFORM pg_temp.expect_failure(format('SELECT public.finalize_match(%L,%L)',final,r1),'Feeder matches');
    PERFORM pg_temp.expect_failure(format('SELECT public.finalize_match(%L,%L)',semi,r1),'check constraint');
    IF (SELECT winner_id IS NOT NULL FROM public.match WHERE match_id=semi) THEN
        RAISE EXCEPTION 'Failed advancement left a recorded winner';
    END IF;

    -- Separate bracket for the successful two-semifinal progression workflow.
    INSERT INTO public.match(bracket_id,round_number) VALUES (b2,2) RETURNING match_id INTO final;
    INSERT INTO public.match(bracket_id,round_number,player_1,player_2,next_match_id,next_match_slot)
        VALUES (b2,1,r1,r2,final,1) RETURNING match_id INTO semi;
    INSERT INTO public.match(bracket_id,round_number,player_1,next_match_id,next_match_slot)
        VALUES (b2,1,r3,final,2) RETURNING match_id INTO semi2;
    PERFORM public.finalize_match(semi,r1);
    PERFORM public.finalize_match(semi,r1);
    PERFORM public.finalize_match(semi2,r3);
    IF NOT EXISTS (SELECT 1 FROM public.match WHERE match_id=final AND player_1=r1 AND player_2=r3) THEN
        RAISE EXCEPTION 'Winners did not advance to their assigned slots';
    END IF;
    PERFORM pg_temp.expect_failure(format('SELECT public.finalize_match(%L,%L)',semi,r2),'different winner');
    PERFORM pg_temp.expect_failure(format('UPDATE public.match SET winner_id=NULL WHERE match_id=%L',semi),'Finalized matches');
    PERFORM pg_temp.expect_failure(format('DELETE FROM public.match WHERE match_id=%L',semi),'Finalized matches');
    PERFORM pg_temp.expect_failure(format('DELETE FROM public.match WHERE match_id=%L',final),'foreign key');
    PERFORM public.finalize_match(final,r1);
    IF (SELECT winner_id IS DISTINCT FROM r1 FROM public.match WHERE match_id=final) THEN
        RAISE EXCEPTION 'Final winner was not persisted';
    END IF;
    -- RLS is enabled with no public policies; functions are invoker rights only.
    IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relname IN ('tournament','player','weight_division',
        'division_tournament','tournament_player','bracket','match') AND NOT c.relrowsecurity) THEN
        RAISE EXCEPTION 'Missing RLS';
    END IF;
END;
$$;

-- Force deferred checks before rolling back all fixtures.
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo 'Database schema integration tests passed (fixtures rolled back).'
