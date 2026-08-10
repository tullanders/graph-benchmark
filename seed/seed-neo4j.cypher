    CREATE CONSTRAINT link_id IF NOT EXISTS FOR (n:Link) REQUIRE n.id IS UNIQUE;
    CREATE INDEX link_id IF NOT EXISTS FOR (n:Link) ON (n.id);
    CREATE INDEX link_from IF NOT EXISTS FOR (n:Link) ON (n.from);
    CREATE INDEX link_to IF NOT EXISTS FOR (n:Link) ON (n.to);

    LOAD CSV WITH HEADERS FROM 'file:///link.csv' AS row

    CREATE (l:Link {id:row.LINKSEQUENCE_OID})
    SET l.from = row.START_NODE_OID, l.to = row.END_NODE_OID;

    MATCH (l1:Link)
    MATCH (l2:Link {from:l1.to})
    CREATE (l1)-[:NEXT_LINK]->(l2);

    LOAD CSV WITH HEADERS FROM 'file:///lank.csv' AS row
    MATCH (l:Link {id: row.ELEMENT_ID})
    SET l.length = toFloat(row.Sparlangd);