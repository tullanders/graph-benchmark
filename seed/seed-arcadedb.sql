-- ArcadeDB seed — Link / PlaceCenter / Station graph
-- Loads data/link.csv, data/lank.csv, data/platsmitt.csv and
-- data/trainstations.json, which docker-compose mounts read-only at
-- /home/arcadedb/import.

-- The whole file is ONE sqlscript. Create the database once:
--   curl -u root:benchmark -X POST http://localhost:2480/api/v1/server \
--        -H 'Content-Type: application/json' \
--        -d '{"command":"create database benchmark"}'
-- then run this file:
--   curl -u root:benchmark -X POST http://localhost:2480/api/v1/command/benchmark \
--        -H 'Content-Type: application/json' \
--        --data-binary @<(jq -Rs '{language:"sqlscript", command:.}' seed/seed-arcadedb.sql)
-- Studio works too: paste the file in and set the language to "sqlscript".

-- Re-running is safe: the script drops and recreates every type it owns.

-- Ingest strategy:
--   1. CSVs and JSON are bulk-loaded with IMPORT DATABASE into throwaway staging
--      types, reading only the columns we actually need.
--   2. Vertices are projected out of staging with FOREACH, which renames the
--      source columns into the schema shared with the Neo4j/Memgraph seeds
--      (id / fromNode / toNode / length / signature / name / plc).
--      INSERT ... FROM SELECT cannot be used here: it resolves its source type
--      while the script is parsed, i.e. before IMPORT DATABASE has created it.
--   3. Indexes are created AFTER the bulk load, so no index has to be maintained
--      row by row during ingest.
--   4. Edges are built last, driven by the indexes from step 3.

-- ---------------------------------------------------------------- schema ----

DROP TYPE NEXT_LINK IF EXISTS UNSAFE;
DROP TYPE HAS_PLACECENTER IF EXISTS UNSAFE;
DROP TYPE Link IF EXISTS UNSAFE;
DROP TYPE PlaceCenter IF EXISTS UNSAFE;
DROP TYPE Station IF EXISTS UNSAFE;
DROP TYPE LinkCsv IF EXISTS;
DROP TYPE LankCsv IF EXISTS;
DROP TYPE PlaceCsv IF EXISTS;
DROP TYPE StationImport IF EXISTS UNSAFE;

CREATE VERTEX TYPE Link;
CREATE PROPERTY Link.id STRING;
CREATE PROPERTY Link.fromNode STRING;
CREATE PROPERTY Link.toNode STRING;
CREATE PROPERTY Link.length FLOAT;

CREATE VERTEX TYPE PlaceCenter;
CREATE PROPERTY PlaceCenter.id STRING;
CREATE PROPERTY PlaceCenter.signature STRING;
CREATE PROPERTY PlaceCenter.name STRING;
CREATE PROPERTY PlaceCenter.plc INTEGER;

CREATE VERTEX TYPE Station;
CREATE PROPERTY Station.signature STRING;
CREATE PROPERTY Station.plc STRING;
CREATE PROPERTY Station.name STRING;

CREATE EDGE TYPE NEXT_LINK;
CREATE EDGE TYPE HAS_PLACECENTER;

-- --------------------------------------------------------- Link vertices ----

IMPORT DATABASE file:///home/arcadedb/import/link.csv WITH
  documentType = LinkCsv,
  documentPropertiesInclude = 'LINKSEQUENCE_OID,START_NODE_OID,END_NODE_OID',
  maxPropertySize = 1000000,
  commitEvery = 50000;

LET $linkRows = SELECT FROM LinkCsv;
FOREACH ($r IN $linkRows) {
  INSERT INTO Link SET id = $r.LINKSEQUENCE_OID, fromNode = $r.START_NODE_OID, toNode = $r.END_NODE_OID;
}

DROP TYPE LinkCsv;

CREATE INDEX ON Link (id) UNIQUE;
CREATE INDEX ON Link (fromNode) NOTUNIQUE;
CREATE INDEX ON Link (toNode) NOTUNIQUE;

-- ------------------------------------------------------ NEXT_LINK edges  ----
-- A link is followed by every link that starts where it ends.
-- The Link(fromNode) index makes each lookup an index probe instead of a scan.

LET $links = SELECT FROM Link;
FOREACH ($l IN $links) {
  CREATE EDGE NEXT_LINK FROM $l TO (SELECT FROM Link WHERE fromNode = $l.toNode);
}

-- ------------------------------------------------------ Link.length      ----
-- lank.csv carries a WKT geometry column far above the CSV parser's default
-- 4096 chars per column, hence maxPropertySize.

IMPORT DATABASE file:///home/arcadedb/import/lank.csv WITH
  documentType = LankCsv,
  documentPropertiesInclude = 'ELEMENT_ID,Sparlangd',
  maxPropertySize = 1000000,
  commitEvery = 50000;

LET $lengths = SELECT ELEMENT_ID, Sparlangd FROM LankCsv;
FOREACH ($r IN $lengths) {
  UPDATE Link SET length = $r.Sparlangd WHERE id = $r.ELEMENT_ID;
}

DROP TYPE LankCsv;

-- --------------------------------------------------- PlaceCenter + edges ----
-- platsmitt.csv is keyed by the id of the Link the place centre sits on.

IMPORT DATABASE file:///home/arcadedb/import/platsmitt.csv WITH
  documentType = PlaceCsv,
  documentPropertiesInclude = 'ELEMENT_ID,Signatur,Platsnamn,Plc_kod',
  maxPropertySize = 1000000,
  commitEvery = 50000;

LET $placeRows = SELECT FROM PlaceCsv;
FOREACH ($r IN $placeRows) {
  INSERT INTO PlaceCenter SET id = $r.ELEMENT_ID, signature = $r.Signatur, name = $r.Platsnamn, plc = $r.Plc_kod;
}

DROP TYPE PlaceCsv;

CREATE INDEX ON PlaceCenter (signature) NOTUNIQUE;

LET $places = SELECT FROM PlaceCenter;
FOREACH ($p IN $places) {
  CREATE EDGE HAS_PLACECENTER FROM (SELECT FROM Link WHERE id = $p.id) TO $p;
}

-- ------------------------------------------------------------- Station   ----
-- trainstations.json is one object wrapping a "TrainStation" array. The importer
-- chokes on leading whitespace before the opening brace, so the file must not be
-- indented as a whole.

-- Identity is LocationSignature, not PrimaryLocationCode: 255 of the 1750 records
-- carry no PrimaryLocationCode, and 14 codes are shared between a Swedish and a
-- Danish station, so keying on it silently drops stations on import and inserts
-- the code-less ones afresh on every run. LocationSignature is unique across all
-- 1750 records and is the same identifier PlaceCenter.signature uses.

IMPORT DATABASE file:///home/arcadedb/import/trainstations.json WITH
  mapping = {
    "TrainStation": [{
      "@cat": "d",
      "@type": "StationImport",
      "@id": "LocationSignature",
      "@idType": "string",
      "@strategy": "merge"
    }]
  },
  commitEvery = 5000;

CREATE INDEX ON Station (signature) UNIQUE;

-- UPSERT needs that index to exist; it also keeps this section safe to run on
-- its own against a Station type that is already populated.

LET importedStations = SELECT FROM StationImport;
FOREACH ($source IN $importedStations) {
  LET geom = geo.geomFromText($source.Geometry.WGS84);
  UPDATE Station
    SET signature   = $source.LocationSignature,
        name        = $source.AdvertisedLocationName,
        plc         = $source.PrimaryLocationCode,
        coords      = [geo.x($geom), geo.y($geom)],
        geometryWkt = $source.Geometry.WGS84
    UPSERT
    WHERE signature = $source.LocationSignature;
}
DROP TYPE StationImport;

-- Create relationships from Station to PlaceCenter
LET $stations = SELECT FROM Station;
FOREACH ($s IN $stations) {
  CREATE EDGE HAS_PLACECENTER FROM $s TO (SELECT FROM PlaceCenter WHERE signature = $s.signature);
}



-- ---------------------------------------------------------------- report ----