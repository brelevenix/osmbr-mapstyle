
-- osm_waterareas
CREATE OR REPLACE VIEW osm_waterareas AS
  SELECT
    osm_id,
    COALESCE(tags -> 'name:br'::text) as name,
    COALESCE(tags -> 'source:name:br'::text) as source_name,
    COALESCE(waterway, '') || COALESCE(landuse, '') || COALESCE("natural", '') as type,
    way_area as area,
    --way as geometry
    ST_MULTI(way)::geometry(MultiPolygon,3857) as geometry
  FROM planet_osm_polygon
  WHERE 
    waterway = 'riverbank'::text
    OR (landuse = ANY (ARRAY['reservoir'::text, 'water'::text, 'basin'::text, 'salt_pond'::text]))
    OR ("natural" = ANY (ARRAY['lake'::text, 'water'::text])) OR amenity = 'swimming_pool'::text
    OR leisure = 'swimming_pool'::text
  ORDER BY z_order, way_area DESC ;


-- osm_waterareas_gen1
CREATE OR REPLACE VIEW osm_waterareas_gen1 AS
 SELECT
    osm_id,
    name,
    source_name,
    type,
    area,
    geometry
   FROM osm_waterareas
  WHERE ST_AREA(ST_SimplifyPreserveTopology(geometry, 50)) > 50000.000000 ;


-- osm_waterareas_gen0
CREATE OR REPLACE VIEW osm_waterareas_gen0 AS
 SELECT 
    osm_id,
    name,
    source_name,
    type,
    area,
    geometry
   FROM osm_waterareas_gen1
  WHERE ST_AREA(ST_SimplifyPreserveTopology(geometry, 200)) > 50000.000000 ;



-- osm_waterways
CREATE OR REPLACE VIEW osm_waterways AS
  SELECT
    osm_id,
    COALESCE(tags -> 'name:br'::text) as name,
    COALESCE(tags -> 'source:name:br'::text) as source_name,
    COALESCE(waterway, '') as type,
    way as geometry
  FROM planet_osm_line
  WHERE 
    waterway in ('weir','river','canal','derelict_canal','stream','drain','ditch','wadi')
  ORDER BY z_order ;


-- osm_waterways_gen1
CREATE OR REPLACE VIEW osm_waterways_gen1 AS
 SELECT
    osm_id,
    name,
    source_name,
    type,
    (ST_SimplifyPreserveTopology(geometry, 50)) as geometry
   FROM osm_waterways ;


-- osm_waterways_gen0
CREATE OR REPLACE VIEW osm_waterways_gen0 AS
 SELECT
    osm_id,
    name,
    source_name,
    type,
    (ST_SimplifyPreserveTopology(geometry, 50)) as geometry
   FROM osm_waterways_gen1 ;


-- osm_admin
CREATE OR REPLACE VIEW osm_admin AS 
  SELECT
    b.way::geometry(LineString,3857) AS geometry,
    admin_level::integer as admin_level,
    coalesce(b.tags->'maritime','no') as maritime,
    count(r.*) as nb,
    string_agg(id::text,',') as rels
  FROM planet_osm_roads b
    LEFT JOIN planet_osm_rels r ON (r.parts @> ARRAY[osm_id] AND r.members @> ARRAY['w' || osm_id] AND regexp_replace(r.tags::text,'[{}]',',') ~ format('(,admin_level,%s.*,boundary,administrative|,boundary,administrative.*,admin_level,%s,)',admin_level,admin_level)) 
  WHERE boundary='administrative' AND admin_level IS NOT NULL GROUP BY 1,2,3 ORDER BY admin_level desc, 4;


-- osm_places
CREATE OR REPLACE VIEW osm_places AS
 SELECT
    osm_id,
    COALESCE(tags -> 'name:br'::text) as name,
    COALESCE(tags -> 'source:name:br'::text) as source_name,
    place as type,
    admin_level,
    COALESCE(tags->'is_capital'::text) as is_capital,
    z_order,
    population::integer as population,
    way as geometry
   FROM planet_osm_point
   WHERE
    place in ('country','state','region','county','city','town','village','hamlet','suburb','locality')
    AND COALESCE(tags -> 'name:br') is not null
    -- keep only integer values for population
    AND (population ~ '^\d+$' OR population IS NULL) ;


-- osm_admin_places
-- see http://dba.stackexchange.com/questions/104943/osm2pgsql-select-relation-member-by-role
-- because planet_osm_rels.rels is not a hstore attribute
CREATE OR REPLACE VIEW osm_admin_places AS
-- préfecture
(SELECT
  DISTINCT(osm_id),
  way as geometry,
  name as name_fr,
  COALESCE(tags -> 'name:br'::text) as name,
  '3' as admin_level,
  'prefecture' as admin_name,
  place as type,
  population::integer as population
FROM planet_osm_point
JOIN (
        WITH numbered AS(
            SELECT row_number() OVER() AS row, entry
            FROM(
                SELECT unnest(members) AS entry
                FROM planet_osm_rels
                WHERE ARRAY['boundary','administrative']<@tags AND ARRAY['admin_level','6']<@tags) AS mylist)
        SELECT ltrim(a.entry,'n')::bigint AS osm_id
        FROM numbered AS a JOIN numbered AS b
        ON a.row = b.row-1 AND b.entry = 'admin_centre'
) x
USING(osm_id))
UNION
-- chef-lieu de canton
(SELECT
  DISTINCT(osm_id),
  way as geometry,
  name as name_fr,
  COALESCE(tags -> 'name:br'::text) as name,
  '2' as admin_level,
  'chef-lieu de canton' as admin_name,
  place as type,
  population::integer as population
FROM planet_osm_point
JOIN (
        WITH numbered AS(
            SELECT row_number() OVER() AS row, entry
            FROM(
                SELECT unnest(members) AS entry
                FROM planet_osm_rels
                WHERE ARRAY['political_division','canton']<@tags) AS mylist)
        SELECT ltrim(a.entry,'n')::bigint AS osm_id
        FROM numbered AS a JOIN numbered AS b
        ON a.row = b.row-1 AND b.entry = 'admin_centre'
) x
USING(osm_id))
UNION
-- commune
(SELECT
  DISTINCT(osm_id),
  way as geometry,
  name as name_fr,
  COALESCE(tags -> 'name:br'::text) as name,
  '1' as admin_level,
  'commune' as admin_name,
  place as type,
  population::integer as population
FROM planet_osm_point
JOIN (
        WITH numbered AS(
            SELECT row_number() OVER() AS row, entry
            FROM(
                SELECT unnest(members) AS entry
                FROM planet_osm_rels
                WHERE ARRAY['boundary','administrative']<@tags AND ARRAY['admin_level','8']<@tags) AS mylist)
        SELECT ltrim(a.entry,'n')::bigint AS osm_id
        FROM numbered AS a JOIN numbered AS b
        ON a.row = b.row-1 AND b.entry = 'admin_centre'
) x
USING(osm_id));


-- osm_roads + railways
CREATE OR REPLACE VIEW osm_roads AS
 -- roads
 (SELECT
    osm_id,
    COALESCE(highway, '') as type,
    COALESCE(tags -> 'name:br'::text,'') as name,
    COALESCE(tags -> 'source:name:br'::text,'') as source_name,
    tunnel,
    bridge,
    oneway,
    layer,
    ref,
    z_order,
    access,
    service,
    'highway'::text as class,
    way as geometry
 FROM planet_osm_line
 WHERE
   highway IN ('motorway','motorway_link','trunk','trunk_link','primary','primary_link','secondary','secondary_link','tertiary','tertiary_link','road','path','track','service','footway','bridleway','cycleway','steps','pedestrian','living_street','unclassified','residential','raceway')
)
 UNION
 -- railways
(
 SELECT
    osm_id,
    COALESCE(railway, '') as type,
    COALESCE(tags -> 'name:br'::text,'') as name,
    COALESCE(tags -> 'source:name:br'::text,'') as source_name,
    tunnel,
    bridge,
    oneway,
    layer,
    ref,
    z_order,
    access,
    service,
    'highway'::text as class,
    way as geometry
 FROM planet_osm_line
 WHERE
   railway IN ('rail','light_rail','subway','tram','narrow_gauge','spur','siding','platform','abandoned','disused')
);


-- osm_aeroways
CREATE OR REPLACE VIEW osm_aeroways AS
 SELECT
    osm_id,
    name,
    COALESCE(aeroway, '') as type,
    way as geometry
 FROM planet_osm_line
 WHERE
   aeroway IN ('runway','taxiway','taxipath','parking_position') ;


-- osm_buildings
CREATE OR REPLACE VIEW osm_buildings AS
 SELECT
    osm_id,
    COALESCE(tags -> 'name:br'::text,'') as name,
    COALESCE(tags -> 'source:name:br'::text,'') as source_name,
    building as type,
    COALESCE(tags -> 'building:levels','') as building_levels,
    way as geometry
   FROM planet_osm_polygon
   WHERE
    building is not null ;
    --and (tags -> 'building:levels') ~ '^\d+$' ;


-- osm_landusages
CREATE OR REPLACE VIEW osm_landusages AS
  -- amenity
  (SELECT
    osm_id,
    COALESCE(tags -> 'name:br'::text) as name,
    COALESCE(tags -> 'source:name:br'::text) as source_name,
    (case when amenity in ('university','school','college','library','fuel','parking','cinema','theatre','place_of_workship','hospital') then amenity end) as type,
    way_area as area,
    z_order,
    way as geometry
  FROM planet_osm_polygon
  WHERE amenity in ('university','school','college','library','fuel','parking','cinema','theatre','place_of_workship','hospital') )
  UNION
  -- landuse
  (SELECT
    osm_id,
    COALESCE(tags -> 'name:br'::text) as name,
    COALESCE(tags -> 'source:name:br'::text) as source_name,
    (case when landuse in ('park','forest','residential','retail','commercial','industrial','railway','cemetary','grass','farmyard','farm','farmland','orchard','vineyard','wood','meadow','village_green','recreation_ground','allotments','quarry') then landuse end) as type,
    way_area as area,
    z_order,
    way as geometry
  FROM planet_osm_polygon
  WHERE landuse in ('park','forest','residential','retail','commercial','industrial','railway','cemetary','grass','farmyard','farm','farmland','orchard','vineyard','wood','meadow','village_green','recreation_ground','allotments','quarry') )
  UNION
  -- leisure
  (SELECT
    osm_id,
    COALESCE(tags -> 'name:br'::text) as name,
    COALESCE(tags -> 'source:name:br'::text) as source_name,
    (case when leisure in ('park','garden','playground','golf_course','sports_centre','pitch','stadium','common','nature_reserve') then leisure end) as type,
    way_area as area,
    z_order,
    way as geometry
  FROM planet_osm_polygon
  WHERE leisure in ('park','garden','playground','golf_course','sports_centre','pitch','stadium','common','nature_reserve') )
  UNION
  -- natural
  (SELECT
    osm_id,
    COALESCE(tags -> 'name:br'::text) as name,
    COALESCE(tags -> 'source:name:br'::text) as source_name,
    (case when "natural" in ('wood','land','scrub','wetland','health') then "natural" end) as type,
    way_area as area,
    z_order,
    way as geometry
  FROM planet_osm_polygon
  WHERE "natural" in ('wood','land','scrub','wetland','health') )
  UNION
  -- aeroway
  (SELECT
    osm_id,
    COALESCE(tags -> 'name:br'::text) as name,
    COALESCE(tags -> 'source:name:br'::text) as source_name,
    (case when aeroway in ('runway','taxiway','apron','aerodrome') then aeroway end) as type,
    way_area as area,
    z_order,
    way as geometry
  FROM planet_osm_polygon
  WHERE aeroway in ('runway','taxiway','apron','aerodrome') ) ;


-- osm_landusages_gen1
CREATE MATERIALIZED VIEW osm_landusages_gen1
  (
    osm_id,
    type,
    area,
    geometry
  )
AS
 SELECT
    osm_id,
    type,
    area,
    (ST_SimplifyPreserveTopology(geometry, 50)) as geometry
   FROM osm_landusages
   WHERE ST_AREA(geometry) > 10000 ;


-- osm_landusages_gen0
CREATE MATERIALIZED VIEW osm_landusages_gen0
  (
    osm_id,
    type,
    area,
    geometry
  )
AS
 SELECT
    osm_id,
    type,
    area,
    (ST_SimplifyPreserveTopology(geometry, 50)) as geometry
   FROM osm_landusages_gen1
   WHERE ST_AREA(geometry) > 100000 ;



