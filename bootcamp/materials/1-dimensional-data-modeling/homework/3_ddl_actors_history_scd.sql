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