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