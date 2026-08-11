# graph-benchmark

Jämförelse av grafdatabaser (Neo4j, Memgraph, ArcadeDB) mot samma dataset och frågor.

## Förutsättningar

- Docker och Docker Compose

## Starta databaser

Starta en i taget eller alla samtidigt:

```bash
docker compose up -d neo4j
docker compose up -d memgraph memgraph-lab
docker compose up -d arcadedb
```

```bash
# eller alla på en gång
docker compose up -d
```

## Gränssnitt

| Databas   | URL                        | Credentials              |
|-----------|----------------------------|--------------------------|
| Neo4j     | http://localhost:7474       | neo4j / benchmark        |
| Memgraph  | http://localhost:3000       | –                        |
| ArcadeDB  | http://localhost:2480       | root / benchmark         |

## Bolt-portar

| Databas   | Port  |
|-----------|-------|
| Neo4j     | 7687  |
| Memgraph  | 7688  |

## Data

CSV-filer i `data/` monteras in i respektive container:

| Databas   | Sökväg i container                    |
|-----------|---------------------------------------|
| Neo4j     | `/var/lib/neo4j/import/`              |
| Memgraph  | `/usr/lib/memgraph/import-data/`      |
| ArcadeDB  | `/home/arcadedb/import/`              |

Seed-skript finns i `seed/`.

## Stänga ner

```bash
docker compose down
```
