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