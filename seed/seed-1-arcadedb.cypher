LOAD CSV WITH HEADERS FROM 'file:///home/arcadedb/import/link.csv' AS row 
CREATE (l:Link {id:row.LINKSEQUENCE_OID}) 
SET l.fromNode = row.START_NODE_OID, l.toNode = row.END_NODE_OID
return 'created ' + count(l) + ' links';

MATCH (l1:Link) 
MATCH (l2:Link {fromNode:l1.toNode}) 
CREATE (l1)-[r:NEXT_LINK]->(l2)
return 'created ' + count(r) + ' relationships';

LOAD CSV WITH HEADERS FROM 'file:///home/arcadedb/import/lank.csv' AS row 
MATCH (l:Link {id: row.ELEMENT_ID}) 
SET l.length = tofloat(row.Sparlangd)
return 'updated ' + count(l) + ' links';