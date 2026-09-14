-- Development reset: remove every record and reset all generated IDs.
-- Run only against the intended Beleka development database.
DO $$
DECLARE
    table_record RECORD;
BEGIN
    FOR table_record IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
    LOOP
        EXECUTE format(
            'TRUNCATE TABLE %I.%I RESTART IDENTITY CASCADE',
            'public',
            table_record.tablename
        );
    END LOOP;
END
$$;

-- Clear cached VPS data as well, if Redis is used by the deployment.
-- Run separately in the Redis container:
-- redis-cli FLUSHALL
