LOAD CSV WITH HEADERS FROM 'file:///home/arcadedb/import/link.csv' AS row 
CREATE (l:Link {id:row.LINKSEQUENCE_OID}) 
SET l.fromNode = row.START_NODE_OID, l.toNode = row.END_NODE_OID
return 'created ' + count(l) + ' links' as result;

MATCH (l1:Link) 
MATCH (l2:Link {fromNode:l1.toNode}) 
CREATE (l1)-[r:NEXT_LINK]->(l2)
return 'created ' + count(r) + ' relationships' as result;

LOAD CSV WITH HEADERS FROM 'file:///home/arcadedb/import/lank.csv' AS row 
MATCH (l:Link {id: row.ELEMENT_ID}) 
SET l.length = tofloat(row.Sparlangd)
return 'updated ' + count(l) + ' links' as result;

LOAD CSV WITH HEADERS FROM 'file:///home/arcadedb/import/platsmitt.csv' AS row
CREATE (p:PlaceCenter {id:row.ELEMENT_ID})
SET p.signature = row.Signatur, p.name = row.Platsnamn,
p.plc = toInteger(row.Plc_kod)
CREATE (l)-[r:HAS_PLACECENTER]->(p)
return 'Created ' + count(p) + ' PlaceCenter and ' + count(r) + ' relationships with Link' as result