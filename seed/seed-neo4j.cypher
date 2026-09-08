CREATE CONSTRAINT link_id IF NOT EXISTS FOR (n:Link) REQUIRE n.id IS UNIQUE;
CREATE INDEX link_id IF NOT EXISTS FOR (n:Link) ON (n.id);
CREATE INDEX link_from IF NOT EXISTS FOR (n:Link) ON (n.from);
CREATE INDEX link_to IF NOT EXISTS FOR (n:Link) ON (n.to);
CREATE INDEX placecenter_signature IF NOT EXISTS FOR (n:PlaceCenter) ON (n.signature);
CREATE INDEX station_signature IF NOT EXISTS FOR (n:Station) ON (n.signature);

LOAD CSV WITH HEADERS FROM 'file:///link.csv' AS row

CREATE (l:Link {id:row.LINKSEQUENCE_OID})
SET l.from = row.START_NODE_OID, l.to = row.END_NODE_OID;

MATCH (l1:Link)
MATCH (l2:Link {from:l1.to})
CREATE (l1)-[:NEXT_LINK]->(l2);

LOAD CSV WITH HEADERS FROM 'file:///lank.csv' AS row
MATCH (l:Link {id: row.ELEMENT_ID})
SET l.length = toFloat(row.Sparlangd);

LOAD CSV WITH HEADERS FROM 'file:///platsmitt.csv' AS row
CREATE (p:PlaceCenter {id:row.ELEMENT_ID})
SET p.signature = row.Signatur, p.name = row.Platsnamn,
p.plc = toInteger(row.Plc_kod)
with p, row
match (l:Link {id: row.ELEMENT_ID})
CREATE (l)-[r:HAS_PLACECENTER]->(p);

CALL apoc.load.json("file:///trainstations.json") YIELD value
UNWIND value.TrainStation AS row
CREATE (s:Station {signature: row.LocationSignature})
SET s.name = row.AdvertisedLocationName,
    s.plc = toInteger(row.PrimaryLocationCode),
    s.geometryWkt = row.Geometry.WGS84
with s, row
match (pc:PlaceCenter {signature:s.signature})
create (s)-[:HAS_PLACECENTER]->(pc);

