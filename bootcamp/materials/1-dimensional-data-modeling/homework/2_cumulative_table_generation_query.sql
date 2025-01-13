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