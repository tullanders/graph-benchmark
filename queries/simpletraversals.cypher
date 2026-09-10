// Neo4j, Memgraph, and ArcadeDB simple traversals
MATCH p=(:Location {signature:'FLN'})-[:NEXT_LOCATION*..12]-(:Location {signature:'AVKY'}) 
RETURN nodes(p), relationships(p)