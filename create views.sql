
-- osm_water_areas
CREATE OR REPLACE VIEW public.osm_water_areas AS
  SELECT
    osm_id,
    COALESCE(planet_osm_polygon.tags -> 'name:br'::text) as name,
    COALESCE(planet_osm_polygon.tags -> 'source:name:br'::text) as source_name,
    COALESCE(waterway, '') || COALESCE(landuse, '') || COALESCE("natural", '') as type,
    way_area as area,
    way as geometry
  FROM planet_osm_polygon
  WHERE waterway = 'riverbank'::text OR (landuse = ANY (ARRAY['reservoir'::text, 'water'::text, 'basin'::text, 'salt_pond'::text])) OR ("natural" = ANY (ARRAY['lake'::text, 'water'::text])) OR amenity = 'swimming_pool'::text OR leisure = 'swimming_pool'::text
  ORDER BY z_order, way_area DESC;


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
  WHERE ST_AREA(ST_SimplifyPreserveTopology(geometry, 50)) > 50000.000000