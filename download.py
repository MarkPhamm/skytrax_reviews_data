#!/usr/bin/env python3
"""Download tables from an Xóm Dataset SQL Server schema as CSV files.

Reads connection details from a local .env file.

Examples:
    .venv/bin/python download.py --list
    .venv/bin/python download.py --schema skytrax
    .venv/bin/python download.py
"""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path

import pandas as pd
import pytds
from dotenv import load_dotenv

load_dotenv()

REQUIRED_ENV = (
    "XOMDATA_HOST",
    "XOMDATA_PORT",
    "XOMDATA_DATABASE",
    "XOMDATA_USERNAME",
    "XOMDATA_PASSWORD",
)

SYSTEM_SCHEMAS = {
    "sys",
    "INFORMATION_SCHEMA",
    "guest",
    "db_accessadmin",
    "db_backupoperator",
    "db_datareader",
    "db_datawriter",
    "db_ddladmin",
    "db_denydatareader",
    "db_denydatawriter",
    "db_owner",
    "db_securityadmin",
}


def env_config() -> dict[str, str | int]:
    missing = [name for name in REQUIRED_ENV if not os.getenv(name)]
    if missing:
        raise SystemExit(
            "Missing environment variables: "
            + ", ".join(missing)
            + "\nSet them in .env before running this script."
        )
    return {
        "host": os.environ["XOMDATA_HOST"],
        "port": int(os.environ["XOMDATA_PORT"]),
        "database": os.environ["XOMDATA_DATABASE"],
        "username": os.environ["XOMDATA_USERNAME"],
        "password": os.environ["XOMDATA_PASSWORD"],
    }


def quote_ident(name: str) -> str:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise SystemExit(f"Invalid identifier: {name}")
    return f"[{name}]"


def connect(cfg: dict[str, str | int]) -> pytds.Connection:
    return pytds.connect(
        server=str(cfg["host"]),
        port=int(cfg["port"]),
        user=str(cfg["username"]),
        password=str(cfg["password"]),
        database=str(cfg["database"]),
        login_timeout=10,
        timeout=300,
    )


def list_schemas(cursor: pytds.Cursor) -> list[str]:
    cursor.execute(
        """
        SELECT DISTINCT TABLE_SCHEMA
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_SCHEMA
        """
    )
    return [
        row[0]
        for row in cursor.fetchall()
        if row[0] not in SYSTEM_SCHEMAS
    ]


def list_tables(cursor: pytds.Cursor, schema: str) -> list[str]:
    cursor.execute(
        """
        SELECT TABLE_NAME
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = %s
          AND TABLE_TYPE = 'BASE TABLE'
        ORDER BY TABLE_NAME
        """,
        (schema,),
    )
    return [row[0] for row in cursor.fetchall()]


def print_schemas(schemas: list[str]) -> None:
    if not schemas:
        print("No user schemas with tables found.")
        return
    print("Available schemas:")
    for index, name in enumerate(schemas, start=1):
        print(f"  {index}. {name}")


def pick_schema(schemas: list[str], requested: str | None) -> str:
    if requested:
        if requested not in schemas:
            raise SystemExit(
                f"Schema '{requested}' not found. Choose one of: {', '.join(schemas)}"
            )
        return requested

    print_schemas(schemas)
    choice = input("Schema name or number: ").strip()
    if choice.isdigit():
        index = int(choice)
        if 1 <= index <= len(schemas):
            return schemas[index - 1]
        raise SystemExit(f"Invalid selection: {choice}")
    if choice in schemas:
        return choice
    raise SystemExit(f"Schema '{choice}' not found.")


def export_table(
    conn: pytds.Connection,
    schema: str,
    table: str,
    output_dir: Path,
) -> Path:
    qualified = f"{quote_ident(schema)}.{quote_ident(table)}"
    print(f"Downloading {qualified} ...", flush=True)
    cursor = conn.cursor()
    cursor.execute(f"SELECT * FROM {qualified}")
    columns = [col[0] for col in cursor.description]
    df = pd.DataFrame.from_records(cursor.fetchall(), columns=columns)
    output_path = output_dir / f"{table}.csv"
    df.to_csv(output_path, index=False)
    print(f"  saved {output_path} ({len(df):,} rows, {len(df.columns)} columns)")
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "-s",
        "--schema",
        help="Schema to download. If omitted, available schemas are listed and you can pick one.",
    )
    parser.add_argument(
        "-l",
        "--list",
        action="store_true",
        help="List available schemas and exit.",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        default="data",
        help="Directory to write CSV files (default: data/<schema>)",
    )
    args = parser.parse_args()

    cfg = env_config()
    print(
        f"Connecting to {cfg['host']}:{cfg['port']}/{cfg['database']} "
        f"as {cfg['username']} ..."
    )
    conn = connect(cfg)
    try:
        cursor = conn.cursor()
        schemas = list_schemas(cursor)
        if args.list:
            print_schemas(schemas)
            return

        schema = pick_schema(schemas, args.schema)
        tables = list_tables(cursor, schema)
        if not tables:
            raise SystemExit(f"No tables found in schema [{schema}].")

        output_dir = Path(args.output_dir) / schema
        output_dir.mkdir(parents=True, exist_ok=True)
        print(f"Found {len(tables)} table(s) in [{schema}]: {', '.join(tables)}")
        for table in tables:
            export_table(conn, schema, table, output_dir)
        print(f"Done. CSVs are in {output_dir.resolve()}")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
