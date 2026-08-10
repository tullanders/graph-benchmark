CREATE CONSTRAINT ON (n:Link) ASSERT EXISTS (n.id);
CREATE INDEX ON :Link(id);
CREATE INDEX ON :Link(fromNode);
CREATE INDEX ON :Link(toNode);

LOAD CSV FROM "/usr/lib/memgraph/import-data/link.csv" WITH HEADER AS row
CREATE (l:Link {id:row.LINKSEQUENCE_OID})
SET l.fromNode = row.START_NODE_OID, l.toNode = row.END_NODE_OID;

MATCH (l1:Link)
MATCH (l2:Link {fromNode:l1.toNode})
CREATE (l1)-[:NEXT_LINK]->(l2);

LOAD CSV FROM "/usr/lib/memgraph/import-data/lank.csv" WITH HEADER AS row
MATCH (l:Link {id: row.ELEMENT_ID})
SET l.length = toFloat(row.Sparlangd);