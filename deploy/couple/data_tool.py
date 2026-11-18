"""Offline operator utility. A restored copy is always written to a NEW pathname."""
import argparse
import os
import sqlite3
from contextlib import closing
from pathlib import Path


def copy_db(source: Path, target: Path, *, for_restore=False):
    source=source.resolve(strict=True)
    target=target.resolve()
    if source==target or not target.parent.is_dir():
        raise ValueError("Choose a different, existing target directory")
    # O_EXCL prevents two operators or a typo from overwriting a backup/live volume.
    fd=os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    os.close(fd)
    try:
        with closing(sqlite3.connect(source.as_uri()+"?mode=ro",uri=True)) as src, closing(sqlite3.connect(target)) as dst:
            if src.execute("pragma quick_check").fetchone()!=("ok",):
                raise ValueError("Source failed integrity check")
            version=src.execute("pragma user_version").fetchone()[0]
            if version not in (1,2,3): raise ValueError("This release expects schema 1, 2 or 3")
            if not src.execute("select count(*) from couples").fetchone()[0]:
                raise ValueError("Not an initialized product database")
            src.backup(dst)
            if dst.execute("pragma integrity_check").fetchone()!=("ok",): raise ValueError("Copy failed integrity check")
            if dst.execute("pragma foreign_key_check").fetchone(): raise ValueError("Invalid foreign keys in copy")
            if for_restore:
                # A past backup must not re-enable a handset session revoked since the snapshot.
                dst.execute("delete from sessions")
                dst.commit()
    except BaseException:
        target.unlink(missing_ok=True)
        raise


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("operation",choices=("backup","restore"))
    parser.add_argument("source",type=Path)
    parser.add_argument("new_file",type=Path)
    args=parser.parse_args()
    copy_db(args.source,args.new_file,for_restore=args.operation=="restore")
    print("Integrity verified. New file written; existing database untouched.")
