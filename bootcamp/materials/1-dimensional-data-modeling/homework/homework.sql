SELECT *
FROM public.actor_films
WHERE 1 = 1
AND actor = 'Steven Seagal'
--AND actorid = 'nm0000003'
ORDER BY year;

SELECT 
MAX(year)
FROM public.actor_films;

create type films_stats as (
    year INTEGER,
	film TEXT,
	votes INTEGER,
	rating REAL,
	filmid TEXT
);


CREATE TYPE quality_class AS
    ENUM ('bad', 'average', 'good', 'star');

CREATE TABLE actors (
    actorid TEXT,
    actor TEXT,
    films_stats films_stats[],
    quality_class quality_class,
    is_active BOOLEAN,
    current_year INTEGER,
    PRIMARY KEY (actorid, current_year)
);

DROP TABLE actors;

INSERT INTO actors
WITH last_year AS (
        SELECT * FROM actors
        WHERE current_year = 1969
),
this_year AS (
        SELECT 
            actorid,
            actor,
            ARRAY_AGG(
                ROW(
                    year,
                    film,
                    votes,
                    rating,
                    filmid
                )::films_stats
            ) AS films_stats,
            CASE
                WHEN AVG(rating) > 8 
                    THEN 'star'
                WHEN AVG(rating) > 7 AND AVG(rating) <= 8
                    THEN 'good'
                WHEN AVG(rating) > 6 AND AVG(rating) <= 7
                    THEN 'average'
                ELSE 'bad'
            END::quality_class AS quality_class,
            AVG(rating) AS avg_rating,
            year AS current_year

        FROM actor_films
        WHERE year = 1970
        GROUP BY 
            actor,
            actorid,
            year
)
, final AS (
    SELECT
        COALESCE(ty.actorid, ly.actorid) AS actorid,
        COALESCE(ty.actor, ly.actor) AS actor,
        -- Merge films from last year and this year
        CASE 
            WHEN ly.films_stats IS NULL 
                THEN ty.films_stats
            WHEN ty.films_stats IS NOT NULL
                THEN ly.films_stats || ty.films_stats
            ELSE ly.films_stats
        END AS films_stats,
        -- Use quality class from this year or last year
        COALESCE(ty.quality_class, ly.quality_class) AS quality_class,
        -- Determine if the actor is active this year
        CASE
            WHEN ty.films_stats IS NOT NULL AND ARRAY_LENGTH(ty.films_stats, 1) > 0
                THEN TRUE
            ELSE FALSE
        END AS is_active,
        CASE 
            WHEN ty.current_year IS NULL
                THEN ly.current_year + 1
            ELSE ty.current_year
        END AS current_year
    FROM this_year AS ty 
        FULL OUTER JOIN last_year AS ly
        ON ty.actorid = ly.actorid
)
SELECT *
FROM final;


-- 3. DDL actors_history_scd
CREATE TABLE actors_history_scd (
    actorid TEXT,
    actor TEXT,
    quality_class quality_class,
    is_active BOOLEAN,
    start_date INTEGER,
    end_date INTEGER,
    current_year INTEGER,
    PRIMARY KEY (actorid, start_date)
);


-- 4. Backfill query for actors_history_scd
INSERT INTO actors_history_scd
WITH with_previous AS (
    SELECT
        actorid,
        actor,
        current_year,
        quality_class,
        is_active,
        LAG(quality_class, 1) OVER (PARTITION BY actorid ORDER BY current_year) AS previous_quality_class,
        LAG(is_active, 1) OVER (PARTITION BY actorid ORDER BY current_year) AS previous_is_active
    FROM actors
    WHERE current_year <= 2020
)
, with_indicators AS (
    SELECT 
        *,
        CASE
            WHEN quality_class <> previous_quality_class
                THEN 1
            WHEN is_active <> previous_is_active
                THEN 1
            ELSE 0
        END AS change_indicator
    FROM with_previous
)
, with_streaks AS (
    SELECT
        *,
        SUM(change_indicator) OVER (PARTITION BY actorid ORDER BY current_year) AS streak_identifier
    FROM with_indicators
)
    SELECT
        actorid,
        actor,
        quality_class,
        is_active,
        MIN(current_year) AS start_date,
        MAX(current_year) AS end_date,
        2020 AS current_year
    FROM with_streaks
    GROUP BY
        actorid,
        actor,
        streak_identifier,
        is_active,
        quality_class
    ORDER BY
        actor;

-- 5. Incremental query for actors_history_scd
CREATE TYPE actors_scd_type AS (
    quality_class quality_class,
    is_active BOOLEAN,
    start_date INTEGER,
    end_date INTEGER
);

WITH last_year_scd AS (
    SELECT *
    FROM actors_history_scd
    WHERE current_year = 2020
    AND end_date = 2020
)
, historical_scd AS (
    SELECT
        actorid,
        actor,
        quality_class,
        is_active,
        start_date,
        end_date
    FROM actors_history_scd
    WHERE current_year = 2020
    AND end_date < 2020
)
, this_year_data AS (
    SELECT *
    FROM actors
    WHERE current_year = 2021
)
, unchanged_records AS (
    SELECT
        ty.actorid,
        ty.actor,
        ty.quality_class,
        ty.is_active,
        ly.start_date,
        ty.current_year AS end_date
    FROM this_year_data AS ty
        INNER JOIN last_year_scd AS ly
        ON ty.actorid = ly.actorid
    WHERE
        ty.quality_class = ly.quality_class
        AND ty.is_active = ly.is_active
)
, changed_records AS (
    SELECT
        ty.actorid,
        ty.actor,
        ty.quality_class,
        ty.is_active,
        ly.start_date,
        ty.current_year AS end_date,
        UNNEST(ARRAY[
            ROW(
                ly.quality_class,
                ly.is_active,
                ly.start_date,
                ly.end_date
            )::actors_scd_type,
            ROW(
                ty.quality_class,
                ty.is_active,
                ty.current_year,
                ty.current_year
            )::actors_scd_type
        ]) as records
    FROM this_year_data AS ty
        LEFT JOIN last_year_scd AS ly
        ON ty.actorid = ly.actorid
    WHERE
        (ty.quality_class <> ly.quality_class
        OR ty.is_active <> ly.is_active)
)
, unnested_changed_records AS (
    SELECT
        actorid,
        actor,
        (records::actors_scd_type).quality_class,
        (records::actors_scd_type).is_active,
        (records::actors_scd_type).start_date,
        (records::actors_scd_type).end_date
    FROM changed_records
)
, new_records AS (
    SELECT 
        ty.actorid,
        ty.actor,
        ty.quality_class,
        ty.is_active,
        ty.current_year AS start_date,
        ty.current_year AS end_date
    FROM this_year_data AS ty
        LEFT JOIN last_year_scd AS ly
        ON ty.actorid = ly.actorid
    WHERE ly.actorid IS NULL
)
, final AS (
    SELECT
        *
    FROM historical_scd

    UNION ALL

    SELECT 
        *
    FROM unchanged_records

    UNION ALL

    SELECT
        *
    FROM unnested_changed_records

    UNION ALL

    SELECT
        *
    FROM new_records
)
SELECT *
FROM final;