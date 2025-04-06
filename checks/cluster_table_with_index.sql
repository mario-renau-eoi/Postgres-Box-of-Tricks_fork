-- 1. Create an index for clustering if it doesn't exist
CREATE INDEX IF NOT EXISTS idx_fact_measurements_clustering
    ON fact_measurements (sensor_id, location_id, timestamp);

-- 2. Cluster the table using the index
CLUSTER fact_measurements USING idx_fact_measurements_clustering;

-- 3. Optionally, analyze the table after clustering for statistics update
ANALYZE fact_measurements;




-- Script to Insert Massive Data into fact_measurements Table
DO $$
    DECLARE
        sensor_count INTEGER := 1000; -- Number of unique sensors
        location_count INTEGER := 100; -- Number of unique locations
        start_time TIMESTAMP := '2023-01-01 00:00:00';
        end_time TIMESTAMP := '2023-12-31 23:59:59';
        interval_minutes INTEGER := 10; -- Time interval between measurements
    BEGIN
        -- Insert data into fact_measurements
        INSERT INTO fact_measurements (measurement_id, sensor_id, location_id, timestamp, value)
        SELECT
                    row_number() OVER (),    -- Unique measurement ID
                    s.sensor_id,            -- Sensor ID
                    l.location_id,          -- Location ID
                    t.measurement_time,     -- Timestamp
                    round((random() * 100)::numeric, 2) -- Random measurement value (0 to 100, rounded to 2 decimal places)
        FROM
            generate_series(1, sensor_count) AS s(sensor_id),                          -- Generate sensor_ids
            generate_series(1, location_count) AS l(location_id),                      -- Generate location_ids
            generate_series(start_time, end_time, interval '1 minute' * interval_minutes) AS t(measurement_time)
        ORDER BY random(); -- Randomize insert order
    END $$;


-- 1. Query to check the page statistics
-- If the ratio of reads to hits exceeds 0.5 (i.e., less locality), clustering is recommended

select * from pg_stat_user_tables;

-- Query to Check Clustering Need
SELECT relname AS table_name,
       heap_blks_read,
       heap_blks_hit,
       heap_blks_read::numeric / NULLIF(heap_blks_hit, 0) AS read_hit_ratio
FROM pg_statio_user_tables
WHERE relname = 'fact_measurements';


-- #### 3. Automate the Re-Clustering Check
DO $$
    BEGIN
        -- Check if re-clustering is needed
        IF EXISTS (
            SELECT 1
            FROM pg_statio_user_tables
            WHERE relname = 'fact_measurements'
              AND heap_blks_read::numeric / NULLIF(heap_blks_hit, 0) > 0.5
        ) THEN
            -- Re-cluster the table
            PERFORM format('CLUSTER %I.%I', 'public_star', 'fact_measurements');
            RAISE NOTICE 'Table re-clustered: fact_measurements';
        ELSE
            RAISE NOTICE 'Clustering not needed for fact_measurements';
        END IF;
    END $$;