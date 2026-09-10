CREATE CONSTRAINT ON (n:Link) ASSERT EXISTS (n.id);
CREATE INDEX ON :Link(id);
CREATE INDEX ON :Link(fromNode);
CREATE INDEX ON :Link(toNode);
CREATE INDEX ON :PlaceCenter(id);
CREATE INDEX ON :PlaceCenter(signature);
CREATE INDEX ON :Location(signature);
CREATE INDEX ON :Location(rinfSignature);
CREATE INDEX ON :Location(rinfUri);

// Create Link nodes from CSV
LOAD CSV FROM "/usr/lib/memgraph/import-data/link.csv" WITH HEADER AS row
CREATE (l:Link {id:row.LINKSEQUENCE_OID})
SET l.fromNode = row.START_NODE_OID, l.toNode = row.END_NODE_OID;

MATCH (l1:Link)
MATCH (l2:Link {fromNode:l1.toNode})
CREATE (l1)-[:NEXT_LINK]->(l2);

// Update Link nodes with length from CSV
LOAD CSV FROM "/usr/lib/memgraph/import-data/lank.csv" WITH HEADER AS row
MATCH (l:Link {id: row.ELEMENT_ID})
SET l.length = toFloat(row.Sparlangd);

// Create PlaceCenter nodes from CSV
LOAD CSV FROM "/usr/lib/memgraph/import-data/platsmitt.csv" WITH HEADER AS row
MERGE (p:PlaceCenter {id:row.ELEMENT_ID})
SET p.signature = toUpper(row.Signatur), p.name = row.Platsnamn,
p.plc = toInteger(row.Plc_kod)
WITH p, row
MATCH (l:Link {id: row.ELEMENT_ID})
CREATE (p)-[r:HAS_LINK]->(l);

// Create Location nodes from rinf-op.csv
LOAD CSV FROM "/usr/lib/memgraph/import-data/rinf-op.csv" WITH HEADER DELIMITER ';' AS row
WITH row, 
    toUpper(replace(row.era_OperationalPoint_era_uopid,'SE','')) as signature,
    split(trim(replace(replace(replace(row.era_OperationalPoint_era_netReference_geosparql_hasGeometry_geosparql_asWKT, "POINT", ""), "(", ""), ")", "")), " ") AS coords
MERGE (l:Location {signature: signature})
SET l.name = row.era_OperationalPoint_era_opName,
    l.rinfUri = row.era_OperationalPoint,
    l.rinfSignature = row.era_OperationalPoint_era_uopid,
    l.type = row.era_OperationalPoint_era_opType__label,
    l.wkt = row.era_OperationalPoint_era_netReference_geosparql_hasGeometry_geosparql_asWKT,
    l.coords = point(
        {
            longitude: toFloat(coords[0]),
            latitude: toFloat(coords[1]),
            crs: 'wgs-84'
        });

// Create NEXT_LOCATION relationships between Location nodes based on rinf-sections.csv
LOAD CSV FROM "/usr/lib/memgraph/import-data/rinf-sections.csv" WITH HEADER DELIMITER ';' AS row
WITH row
MATCH (from:Location {rinfUri: row.era_SectionOfLine_era_opStart})
MATCH (to:Location {rinfUri: row.era_SectionOfLine_era_opEnd})
MERGE (from)-[:NEXT_LOCATION {meters:toFloat(row.era_SectionOfLine_era_lengthOfSectionOfLine)*1000}]->(to);        

// Create Station nodes from JSON
CALL json_util.load_from_path("/usr/lib/memgraph/import-data/trainstations.json")
YIELD objects
UNWIND objects[0].TrainStation AS row
WITH row, split(trim(replace(replace(replace(row.Geometry.WGS84, "POINT", ""), "(", ""), ")", "")), " ") AS coords
MERGE (l:Location {signature: toUpper(row.LocationSignature)})
SET l.name = row.AdvertisedLocationName,
    l.plc = toInteger(row.PrimaryLocationCode),
    l.wkt = row.Geometry.WGS84,
    l.coords = point(
        {
            longitude: toFloat(coords[0]),
            latitude: toFloat(coords[1]),
            crs: 'wgs-84'
        })
WITH l
MATCH (pc:PlaceCenter {signature:toUpper(l.signature)})--()
MERGE (l)-[:HAS_PLACECENTER]->(pc);