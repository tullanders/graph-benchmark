# graph-benchmark

Comparison of graph databases (Neo4j, Memgraph, ArcadeDB) against the same dataset and queries.

## Prerequisites

- Docker and Docker Compose

## Starting databases

Start one at a time or all at once:

```bash
docker compose up -d neo4j
docker compose up -d memgraph memgraph-lab
docker compose up -d arcadedb
```

```bash
# or all at once
docker compose up -d
```

## Web interfaces

| Database  | URL                        | Credentials              |
|-----------|----------------------------|--------------------------|
| Neo4j     | http://localhost:7474       | neo4j / benchmark        |
| Memgraph  | http://localhost:3000       | –                        |
| ArcadeDB  | http://localhost:2480       | root / benchmark         |

## Bolt ports

| Database  | Port  |
|-----------|-------|
| Neo4j     | 7687  |
| Memgraph  | 7688  |

## Data

CSV files in `data/` are mounted into each container:

| Database  | Path in container                     |
|-----------|---------------------------------------|
| Neo4j     | `/var/lib/neo4j/import/`              |
| Memgraph  | `/usr/lib/memgraph/import-data/`      |
| ArcadeDB  | `/home/arcadedb/import/`              |

Seed scripts are located in `seed/`.

## Shut down

```bash
docker compose down
```
