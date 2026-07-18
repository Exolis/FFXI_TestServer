# database_manager.py

from typing import Any, cast
import mysql.connector


class DatabaseManager:
    def __init__(self, config):
        self.config = config
        self.connection = None

    def connect(self):
        try:
            self.connection = mysql.connector.connect(**self.config)
            return self.connection
        except mysql.connector.Error as err:
            print(f"Error connecting to database: {err}")
            return None

    def disconnect(self):
        if self.connection and self.connection.is_connected():
            self.connection.close()

    def fetch_campaign_map(self) -> list[dict[str, Any]] | None:
        if not self.connect():
            return None
        conn = self.connection
        assert conn is not None  # narrow for type checker; guarded above
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("SELECT * FROM campaign_map")
            result = cursor.fetchall()
            return cast(list[dict[str, Any]], result)
        except mysql.connector.Error as err:
            print(f"Error fetching campaign map data: {err}")
            return None
        finally:
            self.disconnect()

    def fetch_campaign_nation(self) -> list[dict[str, Any]] | None:
        if not self.connect():
            return None
        conn = self.connection
        assert conn is not None
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("SELECT * FROM campaign_nation")
            result = cursor.fetchall()
            return cast(list[dict[str, Any]], result)
        except mysql.connector.Error as err:
            print(f"Error fetching campaign nation data: {err}")
            return None
        finally:
            self.disconnect()

    def fetch_conquest_system(self) -> list[dict[str, Any]] | None:
        if not self.connect():
            return None
        conn = self.connection
        assert conn is not None
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("SELECT * FROM conquest_system")
            result = cursor.fetchall()
            return cast(list[dict[str, Any]], result)
        except mysql.connector.Error as err:
            print(f"Error fetching conquest system data: {err}")
            return None
        finally:
            self.disconnect()

    def fetch_server_variables(self) -> list[dict[str, Any]] | None:
        if not self.connect():
            return None
        conn = self.connection
        assert conn is not None
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("SELECT * FROM server_variables")
            result = cursor.fetchall()
            return cast(list[dict[str, Any]], result)
        except mysql.connector.Error as err:
            print(f"Error fetching server variables data: {err}")
            return None
        finally:
            self.disconnect()

    def fetch_zone_names(self) -> dict[int, str] | None:
        """Fetch mapping of zoneid -> zone name from zone_settings table."""
        if not self.connect():
            return None
        conn = self.connection
        assert conn is not None
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT zoneid, name FROM zone_settings")
            result: dict[int, str] = {}
            for zoneid, name in cursor.fetchall():
                result[int(zoneid)] = str(name)
            return result
        except mysql.connector.Error as err:
            print(f"Error fetching zone names: {err}")
            return None
        finally:
            self.disconnect()

    # ======================================================================
    # Update Methods
    # ======================================================================

    def update_campaign_map(self, record_id, data):
        """Update a campaign_map record by ID. data dict keys should match DB columns."""
        if not self.connect():
            return False
        conn = self.connection
        assert conn is not None
        try:
            cursor = conn.cursor()
            sql = """UPDATE campaign_map SET
                zoneid = %s, isbattle = %s, nation = %s, heroism = %s,
                influence_sandoria = %s, influence_bastok = %s,
                influence_windurst = %s, influence_beastman = %s,
                current_fortifications = %s, current_resources = %s,
                max_fortifications = %s, max_resources = %s
                WHERE id = %s"""
            cursor.execute(
                sql,
                (
                    data.get("zoneid"),
                    data.get("isbattle"),
                    data.get("nation"),
                    data.get("heroism"),
                    data.get("influence_sandoria"),
                    data.get("influence_bastok"),
                    data.get("influence_windurst"),
                    data.get("influence_beastman"),
                    data.get("current_fortifications"),
                    data.get("current_resources"),
                    data.get("max_fortifications"),
                    data.get("max_resources"),
                    record_id,
                ),
            )
            conn.commit()
            return cursor.rowcount > 0
        except mysql.connector.Error as err:
            print(f"Error updating campaign_map: {err}")
            return False
        finally:
            self.disconnect()

    def update_campaign_nation(self, nation_id, data):
        """Update a campaign_nation record by nation ID."""
        if not self.connect():
            return False
        conn = self.connection
        assert conn is not None
        try:
            cursor = conn.cursor()
            sql = "UPDATE campaign_nation SET reconnaissance = %s, morale = %s, prosperity = %s WHERE id = %s"
            cursor.execute(
                sql,
                (
                    data.get("reconnaissance"),
                    data.get("morale"),
                    data.get("prosperity"),
                    nation_id,
                ),
            )
            conn.commit()
            return cursor.rowcount > 0
        except mysql.connector.Error as err:
            print(f"Error updating campaign_nation: {err}")
            return False
        finally:
            self.disconnect()

    def update_conquest_system(self, region_id, data):
        """Update a conquest_system record by region_id."""
        if not self.connect():
            return False
        conn = self.connection
        assert conn is not None
        try:
            cursor = conn.cursor()
            sql = """UPDATE conquest_system SET
                region_control = %s, region_control_prev = %s,
                sandoria_influence = %s, bastok_influence = %s,
                windurst_influence = %s, beastmen_influence = %s
                WHERE region_id = %s"""
            cursor.execute(
                sql,
                (
                    data.get("region_control"),
                    data.get("region_control_prev"),
                    data.get("sandoria_influence"),
                    data.get("bastok_influence"),
                    data.get("windurst_influence"),
                    data.get("beastmen_influence"),
                    region_id,
                ),
            )
            conn.commit()
            return cursor.rowcount > 0
        except mysql.connector.Error as err:
            print(f"Error updating conquest_system: {err}")
            return False
        finally:
            self.disconnect()

    def update_server_variable(self, varname, value, expiry=0):
        """Update a server_variable by name."""
        if not self.connect():
            return False
        conn = self.connection
        assert conn is not None
        try:
            cursor = conn.cursor()
            sql = "UPDATE server_variables SET `value` = %s, `expiry` = %s WHERE `name` = %s"
            cursor.execute(sql, (value, expiry, varname))
            conn.commit()
            return cursor.rowcount > 0
        except mysql.connector.Error as err:
            print(f"Error updating server_variable: {err}")
            return False
        finally:
            self.disconnect()
