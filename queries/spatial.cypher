/*
Fetch all locations near 'HRBG' within 1000 meters
*/

// Memgraph and Neo4j
MATCH (l1:Location {signature: 'HRBG'})
MATCH (l2:Location) WHERE point.distance(l1.coords, l2.coords) < 1000
RETURN l2;


// ArcadeDB
MATCH (l1:Location {signature: 'HRBG'})
MATCH (l2:Location) WHERE geo.distance(l1.wkt, l2.wkt) < 1000
RETURN l2;


/*
    Fetch all locations in Stockholm bounding box
*/

// Neo4j and Memgraph
WITH point({latitude: 59.220, longitude: 17.729}) AS sw, 
    point({latitude: 59.44, longitude: 18.287}) AS ne
MATCH (l:Location)
WHERE point.withinBBox(l.coords, sw, ne)
RETURN l;

// ArcadeDB
WITH geo.geomFromText('POINT (17.729 59.220)') as sw,  geo.geomFromText('POINT (18.287 59.44)') as ne 
WITH geo.envelope(geo.lineString([sw, ne])) AS bbox
MATCH (l:Location)
WHERE geo.within(l.wkt, bbox)
RETURN l;
