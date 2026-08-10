/*
    Simple Shortest Path
*/ 

// Neo4j:
MATCH (l1:Link {id:'0004502c-cb0b-421d-8542-a0294dfd8001'})
MATCH (l2:Link {id:'0001cd0d-2492-4f3c-a225-2fe70b50172c'})
MATCH p = SHORTEST 1 (l1)-[:NEXT_LINK]-+(l2)
RETURN p;

// Memgraph:
MATCH (l1:Link {id:'0004502c-cb0b-421d-8542-a0294dfd8001'})
MATCH (l2:Link {id:'0001cd0d-2492-4f3c-a225-2fe70b50172c'})
MATCH p = (l1)-[:NEXT_LINK *BFS]-(l2)
RETURN p;

// ArcadeDB:
MATCH (l1:Link {id:'0004502c-cb0b-421d-8542-a0294dfd8001'})
MATCH (l2:Link {id:'0001cd0d-2492-4f3c-a225-2fe70b50172c'})
MATCH p = shortestPath(
  (l1)-[:NEXT_LINK*]-(l2)
)
RETURN p;

//----------------------

/*
    Weighted Shortest Path
*/ 

// Neo4j:
MATCH (l1:Link {id:'0004502c-cb0b-421d-8542-a0294dfd8001'})
MATCH (l2:Link {id:'0001cd0d-2492-4f3c-a225-2fe70b50172c'})
MATCH (l1)-[r:NEXT_LINK]->(l2)
RETURN gds.graph.project(
  'myGraph',
  l1,
  l2,
  { relationshipProperties: r { .length } }
)

// Memgraph:
// Note that some weights are negative, so we run absolute value of the weights to avoid negative cycles.
MATCH (l1:Link {id:'0004502c-cb0b-421d-8542-a0294dfd8001'})
MATCH (l2:Link {id:'0001cd0d-2492-4f3c-a225-2fe70b50172c'})
MATCH path=(l1)-[:NEXT_LINK *WSHORTEST (r, n )]-(l2)
RETURN path;