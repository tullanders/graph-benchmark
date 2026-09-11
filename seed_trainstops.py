"""
Seedar en grafdatabas (Neo4j eller Memgraph, båda pratar Bolt) med data från
Trafikverkets öppna API, objekttyp TrainAnnouncement.

Modell:
  (:Location {signature})<-[:PASSES]-(:TrainStop {trainRef, locationSignature})
  (:OperativeTrainStop {activityId, ...tider...})-[:FOR]->(:TrainStop)

Körning (kräver uv, https://docs.astral.sh/uv/):
  export TRAFIKVERKET_API_KEY=din_nyckel

  # Neo4j
  uv run seed_trainstops.py --start 2026-09-01 --days 9 \
      --uri bolt://localhost:7687 --user neo4j --password benchmark

  # Memgraph (samma script, annan port, inget lösenord)
  uv run seed_trainstops.py --start 2026-09-01 --days 9 \
      --uri bolt://localhost:7688 --user "" --password ""
"""

# /// script
# requires-python = ">=3.11"
# dependencies = ["requests", "neo4j"]
# ///

import argparse
import datetime
import os
import sys
from typing import Iterator

import requests
from neo4j import GraphDatabase

API_URL = "https://api.trafikinfo.trafikverket.se/v2/data.json"
PAGE_SIZE = 10000
SCHEMA_VERSION = "1.9"  # kontrollera i API-konsolen om fält saknas/ändrats


# ---------------------------------------------------------------------------
# Hämtning från Trafikverket
# ---------------------------------------------------------------------------

def build_query_xml(api_key: str, date_str: str, skip: int) -> str:
    return f"""<REQUEST>
  <LOGIN authenticationkey="{api_key}"/>
  <QUERY objecttype="TrainAnnouncement" schemaversion="{SCHEMA_VERSION}" limit="{PAGE_SIZE}" skip="{skip}">
    <FILTER>
      <EQ name="DepartureDateOTN" value="{date_str}T00:00:00.000+02:00"/>
    </FILTER>
  </QUERY>
</REQUEST>"""


def fetch_page(api_key: str, date_str: str, skip: int) -> list:
    xml = build_query_xml(api_key, date_str, skip)
    resp = requests.post(
        API_URL,
        data=xml.encode("utf-8"),
        headers={"Content-Type": "text/xml"},
        timeout=60,
    )
    resp.raise_for_status()
    data = resp.json()

    results = data.get("RESPONSE", {}).get("RESULT", [])
    if not results:
        return []
    return results[0].get("TrainAnnouncement", [])


def fetch_all_for_date(api_key: str, date_str: str) -> Iterator[dict]:
    """Itererar med skip/limit tills en sida returnerar färre poster än PAGE_SIZE."""
    skip = 0
    while True:
        batch = fetch_page(api_key, date_str, skip)
        if not batch:
            return
        yield from batch
        if len(batch) < PAGE_SIZE:
            return
        skip += PAGE_SIZE


def daterange(start: datetime.date, end: datetime.date) -> Iterator[datetime.date]:
    d = start
    while d <= end:
        yield d
        d += datetime.timedelta(days=1)


# ---------------------------------------------------------------------------
# Mappning JSON -> radformat för Cypher
# ---------------------------------------------------------------------------

def parse_date(value: str | None) -> datetime.date | None:
    if not value:
        return None
    # DepartureDateOTN kommer som en full datetime-sträng ("...T00:00:00.000+02:00"),
    # inte bara ett datum, så vi parsar som datetime och tar dagen.
    return datetime.datetime.fromisoformat(value).date()


def parse_datetime(value: str | None) -> datetime.datetime | None:
    if not value:
        return None
    return datetime.datetime.fromisoformat(value)


def to_row(a: dict) -> dict:
    # Location.signature är alltid versaler (se seed-neo4j.cypher); Trafikverket
    # skickar t.ex. "Cst" så vi normaliserar innan MERGE, annars skapas en ny
    # Location per skrivning istället för att matcha den befintliga.
    location_signature = a.get("LocationSignature")
    if location_signature:
        location_signature = location_signature.upper()
    train_ref = a.get("AdvertisedTrainReference") or a.get("AdvertisedTrainIdent")

    # date()/datetime() istället för rå sträng, så Neo4j lagrar riktiga temporala
    # typer (Date/DateTime) och inte STRING. Neo4j-drivern serialiserar Pythons
    # date/datetime-objekt till dessa automatiskt.
    ots_props_raw = {
        "activityType": a.get("ActivityType"),
        "advertisedTime": parse_datetime(a.get("AdvertisedTimeAtLocation")),
        "estimatedTime": parse_datetime(a.get("EstimatedTimeAtLocation")),
        "actualTime": parse_datetime(a.get("TimeAtLocation")),  # finns ej i exempeldatat men i schemat
        "trackAtLocation": a.get("TrackAtLocation"),
        "departureDate": parse_date(a.get("DepartureDateOTN")),
        "canceled": a.get("Canceled", False),
        "deleted": a.get("Deleted", False),
        "modifiedTime": parse_datetime(a.get("ModifiedTime")),
        "operator": a.get("Operator"),
        "informationOwner": a.get("InformationOwner"),
    }
    # Samma activityId kan dyka upp igen med fler fält ifyllda (t.ex. actualTime
    # tillkommer senare). SET += skulle då skriva över redan satta fält med null
    # om vi la in dem här, så vi utelämnar dem tills de faktiskt har ett värde.
    ots_props = {k: v for k, v in ots_props_raw.items() if v is not None}

    return {
        "locationSignature": location_signature,
        "trainRef": train_ref,
        "trainId": a.get("AdvertisedTrainIdent"),
        "activityType": a.get("ActivityType"),
        "activityId": a.get("ActivityId"),
        "otsProps": ots_props,
    }


REQUIRED_ROW_FIELDS = ("locationSignature", "trainRef", "activityId")


def is_valid_row(row: dict) -> bool:
    """Trafikverket levererar enstaka announcements utan LocationSignature/
    TrainReference/ActivityId (t.ex. inställda tåg). De saknar det som krävs
    för MERGE-nycklarna och hoppas därför över istället för att krascha batchen."""
    return all(row.get(field) is not None for field in REQUIRED_ROW_FIELDS)


# ---------------------------------------------------------------------------
# Skrivning till grafdatabasen
# ---------------------------------------------------------------------------

CONSTRAINTS = [
    "CREATE CONSTRAINT IF NOT EXISTS FOR (l:Location) REQUIRE l.signature IS UNIQUE",
    "CREATE CONSTRAINT IF NOT EXISTS FOR (o:OperativeTrainStop) REQUIRE o.activityId IS UNIQUE",
    # TrainStop har en sammansatt nyckel - hanteras med index istället för unique constraint
    "CREATE INDEX IF NOT EXISTS FOR (t:TrainStop) ON (t.trainRef, t.locationSignature)",
]

UPSERT_CYPHER = """
UNWIND $rows AS row
MERGE (loc:Location {signature: row.locationSignature})

MERGE (ts:TrainStop {trainRef: row.trainRef, locationSignature: row.locationSignature})
  ON CREATE SET ts.trainId = row.trainId, ts.activityType = row.activityType
MERGE (loc)<-[:PASSES]-(ts)

MERGE (ots:OperativeTrainStop {activityId: row.activityId})
SET ots += row.otsProps
MERGE (ots)-[:FOR]->(ts)
"""

# Bygger en (:TrainStop)-[:NEXT_STOP]->(:TrainStop)-kedja per trainId: för varje
# trainId+avgångsdatum samlas stoppen i tidsordning, och den mest kompletta dagen
# (flest stopp) väljs som facit för det trainId:et.
NEXT_STOP_CYPHER = """
MATCH (o:OperativeTrainStop)--(ts:TrainStop)--(l:Location)
WITH o, ts, l ORDER BY o.departureDate, o.advertisedTime, l.trainId
WITH ts.trainId AS trainId, o.departureDate AS dd, collect(ts) AS ts ORDER BY trainId, size(ts) DESC
WITH trainId, collect(ts)[0] AS ts
UNWIND range(0, size(ts) - 2) AS r
WITH trainId, ts[r] AS from, ts[r + 1] AS to
MERGE (from)-[:NEXT_STOP]->(to)
"""


def ensure_constraints(driver):
    with driver.session() as session:
        for stmt in CONSTRAINTS:
            session.run(stmt)


def write_batch(driver, rows: list):
    if not rows:
        return
    with driver.session() as session:
        session.run(UPSERT_CYPHER, rows=rows)


def build_next_stop_chains(driver):
    with driver.session() as session:
        session.run(NEXT_STOP_CYPHER)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", required=True, help="Startdatum YYYY-MM-DD")
    parser.add_argument("--days", type=int, required=True, help="Antal dagar att hämta, räknat från startdatum")
    parser.add_argument(
        "--api-key",
        default=os.environ.get("TRAFIKVERKET_API_KEY"),
        help="Trafikverket API-nyckel (annars läses TRAFIKVERKET_API_KEY)",
    )
    parser.add_argument("--uri", default="bolt://localhost:7687", help="Bolt-URI, funkar för både Neo4j och Memgraph")
    parser.add_argument("--user", default="neo4j")
    parser.add_argument("--password", default="")
    args = parser.parse_args()

    if not args.api_key:
        sys.exit("Ingen API-nyckel: sätt TRAFIKVERKET_API_KEY eller använd --api-key")

    if args.days < 1:
        sys.exit("--days måste vara minst 1")

    start = datetime.date.fromisoformat(args.start)
    end = start + datetime.timedelta(days=args.days - 1)

    driver = GraphDatabase.driver(args.uri, auth=(args.user, args.password))
    ensure_constraints(driver)

    total = 0
    total_skipped = 0
    for day in daterange(start, end):
        day_str = day.isoformat()
        day_count = 0
        day_skipped = 0
        page_rows = []

        for announcement in fetch_all_for_date(args.api_key, day_str):
            row = to_row(announcement)
            if not is_valid_row(row):
                day_skipped += 1
                continue
            page_rows.append(row)
            day_count += 1

            # Skriv i batchar om PAGE_SIZE för att hålla transaktionerna hanterbara
            if len(page_rows) >= PAGE_SIZE:
                write_batch(driver, page_rows)
                page_rows = []

        write_batch(driver, page_rows)  # sista, ofullständiga batchen
        total += day_count
        total_skipped += day_skipped
        skip_note = f" ({day_skipped} hoppade över, saknade obligatoriska fält)" if day_skipped else ""
        print(f"{day_str}: {day_count} annonser inlästa{skip_note}")

    print(f"Klart. Totalt {total} annonser bearbetade, {total_skipped} hoppade över.")

    print("Bygger NEXT_STOP-kedjor...")
    build_next_stop_chains(driver)
    print("Klart med NEXT_STOP-kedjor.")

    driver.close()


if __name__ == "__main__":
    main()
