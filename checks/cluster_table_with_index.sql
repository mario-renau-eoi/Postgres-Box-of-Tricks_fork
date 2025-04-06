-- Crear un índice para clustering si no existe
CREATE INDEX IF NOT EXISTS idx_pizza_reviews_clustering
    ON pizza_reviews (id, product);
-- Cluster la tabla utilizando el índice creado
CLUSTER pizza_reviews USING idx_pizza_reviews_clustering;
-- Analizar la tabla para actualizar estadísticas después del clustering
ANALYZE pizza_reviews;
VACUUM FULL pizza_reviews;


-- Configura la generación de los datos
DO
$$
    DECLARE
        batch_size      INT    := 100000; -- Define el tamaño del lote
        total_records   INT    := 60000000; -- Total de registros a insertar
        i               INT;
        product_names   TEXT[] := ARRAY ['Pepperoni', 'Margherita', 'BBQ Chicken', 'Hawaiian', 'Veggie', 'Meat Lovers','pizza'];
        message_samples TEXT[] := ARRAY [
            'Delicious!',
            'A bit too salty for my taste.',
            'Amazing crust texture.',
            'The delivery was fast and the pizza was hot.',
            'Not my favorite, but still good.',
            'Perfect balance of flavors.',
            NULL -- Incluye mensajes nulos ocasionalmente
            ];
        current_count   BIGINT := 0;
        start_time      TIMESTAMP;
        end_time        TIMESTAMP;
    BEGIN
        -- Nota inicial del tiempo
        start_time := clock_timestamp();

        FOR i IN 1..(total_records / batch_size)
            LOOP
                INSERT INTO pizza_reviews (product, customer_message)
                SELECT product_names[ceil(random() * array_length(product_names, 1))],    -- Selecciona un producto aleatorio
                       message_samples[ceil(random() * array_length(message_samples, 1))] -- Selecciona un mensaje aleatorio
                FROM generate_series(1, batch_size);

                current_count := current_count + batch_size;

                -- Muestra el progreso
                RAISE NOTICE 'Inserted % records so far.', current_count;
            END LOOP;

        -- Nota final del tiempo
        end_time := clock_timestamp();
        RAISE NOTICE 'Data insertion completed. Started at %, ended at %.', start_time, end_time;
    END
$$;


-- Script to Insert Massive Data into fact_measurements Table
DO
$$
    DECLARE
        sensor_count     INTEGER   := 1000; -- Number of unique sensors
        location_count   INTEGER   := 100; -- Number of unique locations
        start_time       TIMESTAMP := '2023-01-01 00:00:00';
        end_time         TIMESTAMP := '2023-12-31 23:59:59';
        interval_minutes INTEGER   := 10; -- Time interval between measurements
    BEGIN
        -- Insert data into fact_measurements
        INSERT INTO fact_measurements (measurement_id, sensor_id, location_id, timestamp, value)
        SELECT row_number() OVER (),               -- Unique measurement ID
               s.sensor_id,                        -- Sensor ID
               l.location_id,                      -- Location ID
               t.measurement_time,                 -- Timestamp
               round((random() * 100)::numeric, 2) -- Random measurement value (0 to 100, rounded to 2 decimal places)
        FROM generate_series(1, sensor_count) AS s(sensor_id),     -- Generate sensor_ids
             generate_series(1, location_count) AS l(location_id), -- Generate location_ids
             generate_series(start_time, end_time, interval '1 minute' * interval_minutes) AS t(measurement_time)
        ORDER BY random(); -- Randomize insert order
    END
$$;


-- 1. Query to check the page statistics
-- If the ratio of reads to hits exceeds 0.5 (i.e., less locality), clustering is recommended

select *
from pg_stat_user_tables;


-- Simulación: Consulta registros utilizando un patrón aleatorio
SELECT *
FROM pizza_reviews
WHERE id IN (SELECT id
             FROM pizza_reviews
             ORDER BY RANDOM() -- Forzamos un acceso no secuencial
             LIMIT 10000 -- Consulta aleatoria de 10,000 registros
);

-- Consulta con filtros irregulares para dispersar el acceso
SELECT *
FROM pizza_reviews
WHERE MOD(id, 3) = 0     -- Accesos irregulares no consecutivos
   OR product = 'Veggie' -- Combina diferentes filtros
   OR LENGTH(customer_message) > 50;

-- Operación intensiva para simular alta carga y analizar "localidad"
DO
$$
    BEGIN
        FOR i IN 1..2
            LOOP
                PERFORM *
                FROM pizza_reviews
                WHERE MOD(id, 3) = 0     -- Accesos irregulares no consecutivos
                   OR product IN ('Veggie','pizza') -- Combina diferentes filtros
                   OR LENGTH(customer_message) > 50
                ORDER BY RANDOM()
                LIMIT 20000; -- Simulación de acceso aleatorio a 20,000 registros
            END LOOP;
    END
$$;


-- Query to Check Clustering Need
SELECT relname                                            AS table_name,
       heap_blks_read,
       heap_blks_hit,
       heap_blks_read::numeric / NULLIF(heap_blks_hit, 0) AS read_hit_ratio
FROM pg_statio_user_tables
WHERE relname = 'pizza_reviews';


-- #### 3. Automate the Re-Clustering Check
DO
$$
    BEGIN
        -- Check if re-clustering is needed
        IF EXISTS (SELECT 1
                   FROM pg_statio_user_tables
                   WHERE relname = 'fact_measurements'
                     AND heap_blks_read::numeric / NULLIF(heap_blks_hit, 0) > 0.5) THEN
            -- Re-cluster the table
            PERFORM format('CLUSTER %I.%I', 'public_star', 'fact_measurements');
            RAISE NOTICE 'Table re-clustered: fact_measurements';
        ELSE
            RAISE NOTICE 'Clustering not needed for fact_measurements';
        END IF;
    END
$$;