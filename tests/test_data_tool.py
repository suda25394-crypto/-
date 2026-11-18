import os
import sqlite3
import tempfile
import unittest
from pathlib import Path
from cryptography.fernet import Fernet
from services.couple.database import Database,Settings
from deploy.couple.data_tool import copy_db


class BackupTest(unittest.TestCase):
    def test_snapshot_recovery_preserves_data_and_revokes_old_sessions(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            db=Database(Settings(str(root/"current.sqlite3"),"a","b","c",Fernet(Fernet.generate_key())))
            with db.connection(True) as conn:
                pair=db.settings.pair
                conn.execute("INSERT INTO users VALUES(?,?,?)",(pair,"a","Demo"))
                conn.execute("INSERT INTO sessions VALUES(?,?,?,?,?)",("synthetic",pair,"a",b"unused",900))
            backup,restored=root/"snap.sqlite3",root/"restored.sqlite3"
            copy_db(root/"current.sqlite3",backup)
            with self.assertRaises(FileExistsError):
                copy_db(root/"current.sqlite3",backup)
            copy_db(backup,restored,for_restore=True)
            for path,n in [(root/"current.sqlite3",1),(backup,1),(restored,0)]:
                con=sqlite3.connect(path)
                try:
                    self.assertEqual(con.execute("SELECT count(*) FROM sessions").fetchone()[0],n)
                    self.assertEqual(con.execute("SELECT name FROM users").fetchone()[0],"Demo")
                finally:
                    con.close()
