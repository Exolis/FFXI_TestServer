# main.py

import sys

try:
    from PyQt6.QtWidgets import (
        QApplication,
        QMainWindow,
        QVBoxLayout,
        QWidget,
        QPushButton,
        QLabel,
        QTabWidget,
        QTableWidget,
        QTableWidgetItem,
        QHBoxLayout,
        QMessageBox,
        QHeaderView,
    )
except ImportError:
    import sys

    sys.stderr.write(
        "ERROR: PyQt6 is not installed in the active Python interpreter.\n"
        "       ServerManager requires a virtualenv with PyQt6 installed.\n"
        "       Fix:\n"
        "           python -m venv ServerManager/venv\n"
        "           ServerManager\\venv\\Scripts\\activate      (Windows)\n"
        "           source ServerManager/venv/bin/activate    (macOS/Linux)\n"
        "           pip install -r ServerManager/requirements.txt\n"
    )
    sys.exit(1)
from database_manager import DatabaseManager
from http_client import HTTPClient
from config import DB_CONFIG, HTTP_SERVER_URL


class ServerManagerApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("FFXI Server Manager")
        self.setGeometry(100, 100, 1200, 800)

        self.db_manager = DatabaseManager(DB_CONFIG)
        self.http_client = HTTPClient(HTTP_SERVER_URL)

        # Load zone name mapping (zoneid -> zone name)
        self.zone_id_to_name: dict[int, str] = {}
        zone_data = self.db_manager.fetch_zone_names()
        if zone_data is not None:
            self.zone_id_to_name = zone_data
        # Build reverse map (zone name -> zoneid) for update round-trip
        self.zone_name_to_id: dict[str, int] = {
            name: zid for zid, name in self.zone_id_to_name.items()
        }

        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        self.main_layout = QVBoxLayout()
        self.central_widget.setLayout(self.main_layout)

        # Create tabs
        self.tabs = QTabWidget()
        self.main_layout.addWidget(self.tabs)

        # Dashboard Tab
        self.dashboard_tab = QWidget()
        self.setup_dashboard_tab()
        self.tabs.addTab(self.dashboard_tab, "Dashboard")

        # Campaign Map Tab
        self.campaign_map_tab = QWidget()
        self.setup_campaign_map_tab()
        self.tabs.addTab(self.campaign_map_tab, "Campaign Map")

        # Campaign Nation Tab
        self.campaign_nation_tab = QWidget()
        self.setup_campaign_nation_tab()
        self.tabs.addTab(self.campaign_nation_tab, "Campaign Nation")

        # Conquest System Tab
        self.conquest_system_tab = QWidget()
        self.setup_conquest_system_tab()
        self.tabs.addTab(self.conquest_system_tab, "Conquest System")

        # Server Variables Tab
        self.server_variables_tab = QWidget()
        self.setup_server_variables_tab()
        self.tabs.addTab(self.server_variables_tab, "Server Variables")

    # ======================================================================
    # Dashboard Tab
    # ======================================================================
    def setup_dashboard_tab(self):
        layout = QVBoxLayout()
        self.dashboard_label = QLabel("Server Statistics")
        layout.addWidget(self.dashboard_label)

        self.refresh_button = QPushButton("Refresh Data")
        self.refresh_button.clicked.connect(self.refresh_data)
        layout.addWidget(self.refresh_button)

        self.dashboard_info = QLabel("Press 'Refresh Data' to load statistics.")
        layout.addWidget(self.dashboard_info)

        self.dashboard_tab.setLayout(layout)

    def refresh_data(self):
        # Gather statistics from database
        info_parts = []
        campaign_map_data = self.db_manager.fetch_campaign_map()
        campaign_nation_data = self.db_manager.fetch_campaign_nation()

        if campaign_map_data is not None:
            info_parts.append(f"Campaign Map Records: {len(campaign_map_data)}")
        else:
            info_parts.append("Campaign Map: Error loading")

        if campaign_nation_data is not None:
            info_parts.append(f"Campaign Nation Records: {len(campaign_nation_data)}")
        else:
            info_parts.append("Campaign Nation: Error loading")

        self.dashboard_info.setText("\n".join(info_parts))

        # Also reload campaign tabs
        self.load_campaign_map_data()
        self.load_campaign_nation_data()

    # ======================================================================
    # Campaign Map Tab
    # ======================================================================
    def setup_campaign_map_tab(self):
        layout = QVBoxLayout()

        # Nation name mapping
        self.nation_map_labels = {
            0: "Neutral",
            2: "San d'Oria",
            4: "Bastok",
            6: "Windurst",
            8: "Beastmen",
        }

        self.campaign_map_table = QTableWidget()
        self.campaign_map_table.setColumnCount(13)
        self.campaign_map_table.setHorizontalHeaderLabels(
            [
                "ID",
                "Zone",
                "Is Battle",
                "Nation",
                "Heroism",
                "Influence San d'Oria",
                "Influence Bastok",
                "Influence Windurst",
                "Influence Beastmen",
                "Current Fortifications",
                "Current Resources",
                "Max Fortifications",
                "Max Resources",
            ]
        )
        self.campaign_map_table.horizontalHeader().setStretchLastSection(True)
        self.campaign_map_table.setSelectionBehavior(
            QTableWidget.SelectionBehavior.SelectRows
        )
        layout.addWidget(self.campaign_map_table)

        # Update button
        btn_layout = QHBoxLayout()
        self.campaign_map_update_btn = QPushButton("Update Selected")
        self.campaign_map_update_btn.clicked.connect(self.update_campaign_map)
        btn_layout.addWidget(self.campaign_map_update_btn)

        self.campaign_map_reload_btn = QPushButton("Reload Data")
        self.campaign_map_reload_btn.clicked.connect(self.load_campaign_map_data)
        btn_layout.addWidget(self.campaign_map_reload_btn)

        layout.addLayout(btn_layout)

        self.campaign_map_tab.setLayout(layout)

    def load_campaign_map_data(self):
        data = self.db_manager.fetch_campaign_map()
        if data is None:
            QMessageBox.warning(
                self, "Error", "Failed to load Campaign Map data from database."
            )
            return

        self.campaign_map_table.setRowCount(len(data))
        for row_idx, record in enumerate(data):
            self.campaign_map_table.setItem(
                row_idx, 0, QTableWidgetItem(str(record.get("id", "")))
            )
            # Display zone name with ID for round-trip parsing
            zone_id = int(record.get("zoneid", 0))
            zone_name = self.zone_id_to_name.get(zone_id, f"Unknown ({zone_id})")
            self.campaign_map_table.setItem(
                row_idx, 1, QTableWidgetItem(f"{zone_name} ({zone_id})")
            )
            self.campaign_map_table.setItem(
                row_idx, 2, QTableWidgetItem(str(record.get("isbattle", "")))
            )
            nation_val = record.get("nation", "")
            nation_str = self.nation_map_labels.get(nation_val, str(nation_val))
            self.campaign_map_table.setItem(row_idx, 3, QTableWidgetItem(nation_str))
            self.campaign_map_table.setItem(
                row_idx, 4, QTableWidgetItem(str(record.get("heroism", "")))
            )
            self.campaign_map_table.setItem(
                row_idx, 5, QTableWidgetItem(str(record.get("influence_sandoria", "")))
            )
            self.campaign_map_table.setItem(
                row_idx, 6, QTableWidgetItem(str(record.get("influence_bastok", "")))
            )
            self.campaign_map_table.setItem(
                row_idx, 7, QTableWidgetItem(str(record.get("influence_windurst", "")))
            )
            self.campaign_map_table.setItem(
                row_idx, 8, QTableWidgetItem(str(record.get("influence_beastman", "")))
            )
            self.campaign_map_table.setItem(
                row_idx,
                9,
                QTableWidgetItem(str(record.get("current_fortifications", ""))),
            )
            self.campaign_map_table.setItem(
                row_idx, 10, QTableWidgetItem(str(record.get("current_resources", "")))
            )
            self.campaign_map_table.setItem(
                row_idx, 11, QTableWidgetItem(str(record.get("max_fortifications", "")))
            )
            self.campaign_map_table.setItem(
                row_idx, 12, QTableWidgetItem(str(record.get("max_resources", "")))
            )

        self.campaign_map_table.resizeColumnsToContents()

    def _parse_zone_id_from_display(self, display_text: str) -> str:
        """Parse the numeric zone ID from 'ZoneName (zoneid)' display format."""
        if "(" in display_text and display_text.endswith(")"):
            return display_text.split("(")[-1].rstrip(")")
        # Fallback: try reverse lookup from zone_name_to_id
        return str(self.zone_name_to_id.get(display_text, display_text))

    def update_campaign_map(self):
        selected_rows = self.campaign_map_table.selectedItems()
        if not selected_rows:
            QMessageBox.information(
                self, "No Selection", "Please select a row to update."
            )
            return

        # Get the unique rows selected
        rows = set()
        for item in selected_rows:
            rows.add(item.row())

        # Build reverse mapping from nation name -> numeric value
        name_to_nation = {name: val for val, name in self.nation_map_labels.items()}

        success_count = 0
        for row in rows:
            record_id = self.campaign_map_table.item(row, 0).text()
            zone_display = self.campaign_map_table.item(row, 1).text()
            zone_id = self._parse_zone_id_from_display(zone_display)
            is_battle = self.campaign_map_table.item(row, 2).text()
            nation_display = self.campaign_map_table.item(row, 3).text()
            # Convert nation name back to numeric value for DB
            nation_numeric = name_to_nation.get(nation_display, nation_display)
            heroism = self.campaign_map_table.item(row, 4).text()
            influence_sandoria = self.campaign_map_table.item(row, 5).text()
            influence_bastok = self.campaign_map_table.item(row, 6).text()
            influence_windurst = self.campaign_map_table.item(row, 7).text()
            influence_beastman = self.campaign_map_table.item(row, 8).text()
            current_fortifications = self.campaign_map_table.item(row, 9).text()
            current_resources = self.campaign_map_table.item(row, 10).text()
            max_fortifications = self.campaign_map_table.item(row, 11).text()
            max_resources = self.campaign_map_table.item(row, 12).text()

            data = {
                "id": record_id,
                "zoneid": zone_id,
                "isbattle": is_battle,
                "nation": nation_numeric,
                "heroism": heroism,
                "influence_sandoria": influence_sandoria,
                "influence_bastok": influence_bastok,
                "influence_windurst": influence_windurst,
                "influence_beastman": influence_beastman,
                "current_fortifications": current_fortifications,
                "current_resources": current_resources,
                "max_fortifications": max_fortifications,
                "max_resources": max_resources,
            }

            if self.db_manager.update_campaign_map(record_id, data):
                success_count += 1

        # After direct DB edits, ask the world server to reload the
        # campaign state from the DB and broadcast it to map servers,
        # so the change takes effect in-game without waiting for the
        # next scheduled tally.
        if success_count > 0:
            self.http_client.trigger_campaign_refresh()

        QMessageBox.information(
            self,
            "Update Complete",
            f"Updated {success_count} of {len(rows)} selected campaign map records.",
        )

    # ======================================================================
    # Campaign Nation Tab
    # ======================================================================
    def setup_campaign_nation_tab(self):
        layout = QVBoxLayout()

        self.nation_names = {
            0: "San d'Oria",
            1: "Bastok",
            2: "Windurst",
            3: "Orcish",
            4: "Quadav",
            5: "Yagudo",
            6: "Kindred",
        }

        self.campaign_nation_table = QTableWidget()
        self.campaign_nation_table.setColumnCount(4)
        self.campaign_nation_table.setHorizontalHeaderLabels(
            ["ID", "Reconnaissance", "Morale", "Prosperity"]
        )
        self.campaign_nation_table.horizontalHeader().setStretchLastSection(True)
        self.campaign_nation_table.setSelectionBehavior(
            QTableWidget.SelectionBehavior.SelectRows
        )
        layout.addWidget(self.campaign_nation_table)

        btn_layout = QHBoxLayout()
        self.campaign_nation_reload_btn = QPushButton("Reload Data")
        self.campaign_nation_reload_btn.clicked.connect(self.load_campaign_nation_data)
        btn_layout.addWidget(self.campaign_nation_reload_btn)

        self.campaign_nation_update_btn = QPushButton("Update Selected")
        self.campaign_nation_update_btn.clicked.connect(self.update_campaign_nation)
        btn_layout.addWidget(self.campaign_nation_update_btn)

        layout.addLayout(btn_layout)

        self.campaign_nation_tab.setLayout(layout)

    def load_campaign_nation_data(self):
        data = self.db_manager.fetch_campaign_nation()
        if data is None:
            QMessageBox.warning(
                self, "Error", "Failed to load Campaign Nation data from database."
            )
            return

        self.campaign_nation_table.setRowCount(len(data))
        for row_idx, record in enumerate(data):
            nation_id = record.get("id", "")
            nation_name = self.nation_names.get(nation_id, str(nation_id))
            self.campaign_nation_table.setItem(
                row_idx, 0, QTableWidgetItem(f"{nation_name} ({nation_id})")
            )
            self.campaign_nation_table.setItem(
                row_idx, 1, QTableWidgetItem(str(record.get("reconnaissance", "")))
            )
            self.campaign_nation_table.setItem(
                row_idx, 2, QTableWidgetItem(str(record.get("morale", "")))
            )
            self.campaign_nation_table.setItem(
                row_idx, 3, QTableWidgetItem(str(record.get("prosperity", "")))
            )

        self.campaign_nation_table.resizeColumnsToContents()

    def update_campaign_nation(self):
        selected_rows = self.campaign_nation_table.selectedItems()
        if not selected_rows:
            QMessageBox.information(
                self, "No Selection", "Please select a row to update."
            )
            return

        rows = set()
        for item in selected_rows:
            rows.add(item.row())

        success_count = 0
        for row in rows:
            # Parse nation id from the display text "Name (id)"
            id_text = self.campaign_nation_table.item(row, 0).text()
            nation_id = id_text.split("(")[-1].rstrip(")")
            reconnaissance = self.campaign_nation_table.item(row, 1).text()
            morale = self.campaign_nation_table.item(row, 2).text()
            prosperity = self.campaign_nation_table.item(row, 3).text()

            data = {
                "reconnaissance": reconnaissance,
                "morale": morale,
                "prosperity": prosperity,
            }

            if self.db_manager.update_campaign_nation(nation_id, data):
                success_count += 1

        QMessageBox.information(
            self,
            "Update Complete",
            f"Updated {success_count} of {len(rows)} selected campaign nation records.",
        )

    # ======================================================================
    # Conquest System Tab
    # ======================================================================
    def setup_conquest_system_tab(self):
        layout = QVBoxLayout()

        self.conquest_table = QTableWidget()
        self.conquest_table.setColumnCount(7)
        self.conquest_table.setHorizontalHeaderLabels(
            [
                "Region ID",
                "Region Control",
                "Region Control Prev",
                "Influence San d'Oria",
                "Influence Bastok",
                "Influence Windurst",
                "Influence Beastmen",
            ]
        )
        self.conquest_table.horizontalHeader().setStretchLastSection(True)
        self.conquest_table.setSelectionBehavior(
            QTableWidget.SelectionBehavior.SelectRows
        )
        layout.addWidget(self.conquest_table)

        btn_layout = QHBoxLayout()
        self.conquest_reload_btn = QPushButton("Reload Data")
        self.conquest_reload_btn.clicked.connect(self.load_conquest_data)
        btn_layout.addWidget(self.conquest_reload_btn)

        self.conquest_update_btn = QPushButton("Update Selected")
        self.conquest_update_btn.clicked.connect(self.update_conquest)
        btn_layout.addWidget(self.conquest_update_btn)

        layout.addLayout(btn_layout)

        self.conquest_system_tab.setLayout(layout)

    def load_conquest_data(self):
        data = self.db_manager.fetch_conquest_system()
        if data is None:
            QMessageBox.warning(
                self, "Error", "Failed to load Conquest System data from database."
            )
            return

        self.conquest_table.setRowCount(len(data))
        for row_idx, record in enumerate(data):
            self.conquest_table.setItem(
                row_idx, 0, QTableWidgetItem(str(record.get("region_id", "")))
            )
            self.conquest_table.setItem(
                row_idx, 1, QTableWidgetItem(str(record.get("region_control", "")))
            )
            self.conquest_table.setItem(
                row_idx, 2, QTableWidgetItem(str(record.get("region_control_prev", "")))
            )
            self.conquest_table.setItem(
                row_idx, 3, QTableWidgetItem(str(record.get("sandoria_influence", "")))
            )
            self.conquest_table.setItem(
                row_idx, 4, QTableWidgetItem(str(record.get("bastok_influence", "")))
            )
            self.conquest_table.setItem(
                row_idx, 5, QTableWidgetItem(str(record.get("windurst_influence", "")))
            )
            self.conquest_table.setItem(
                row_idx, 6, QTableWidgetItem(str(record.get("beastmen_influence", "")))
            )

        self.conquest_table.resizeColumnsToContents()

    def update_conquest(self):
        selected_rows = self.conquest_table.selectedItems()
        if not selected_rows:
            QMessageBox.information(
                self, "No Selection", "Please select a row to update."
            )
            return

        rows = set()
        for item in selected_rows:
            rows.add(item.row())

        success_count = 0
        for row in rows:
            region_id = self.conquest_table.item(row, 0).text()
            data = {
                "region_control": self.conquest_table.item(row, 1).text(),
                "region_control_prev": self.conquest_table.item(row, 2).text(),
                "sandoria_influence": self.conquest_table.item(row, 3).text(),
                "bastok_influence": self.conquest_table.item(row, 4).text(),
                "windurst_influence": self.conquest_table.item(row, 5).text(),
                "beastmen_influence": self.conquest_table.item(row, 6).text(),
            }
            if self.db_manager.update_conquest_system(region_id, data):
                success_count += 1

        QMessageBox.information(
            self,
            "Update Complete",
            f"Updated {success_count} of {len(rows)} selected conquest records.",
        )

    # ======================================================================
    # Server Variables Tab
    # ======================================================================
    def setup_server_variables_tab(self):
        layout = QVBoxLayout()

        self.server_vars_table = QTableWidget()
        self.server_vars_table.setColumnCount(3)
        self.server_vars_table.setHorizontalHeaderLabels(
            ["Variable Name", "Value", "Expiry"]
        )
        self.server_vars_table.horizontalHeader().setStretchLastSection(True)
        self.server_vars_table.setSelectionBehavior(
            QTableWidget.SelectionBehavior.SelectRows
        )
        layout.addWidget(self.server_vars_table)

        btn_layout = QHBoxLayout()
        self.server_vars_reload_btn = QPushButton("Reload Data")
        self.server_vars_reload_btn.clicked.connect(self.load_server_variables)
        btn_layout.addWidget(self.server_vars_reload_btn)

        self.server_vars_update_btn = QPushButton("Update Selected")
        self.server_vars_update_btn.clicked.connect(self.update_server_variable)
        btn_layout.addWidget(self.server_vars_update_btn)

        layout.addLayout(btn_layout)

        self.server_variables_tab.setLayout(layout)

    def load_server_variables(self):
        data = self.db_manager.fetch_server_variables()
        if data is None:
            QMessageBox.warning(
                self, "Error", "Failed to load Server Variables from database."
            )
            return

        self.server_vars_table.setRowCount(len(data))
        for row_idx, record in enumerate(data):
            self.server_vars_table.setItem(
                row_idx, 0, QTableWidgetItem(str(record.get("name", "")))
            )
            self.server_vars_table.setItem(
                row_idx, 1, QTableWidgetItem(str(record.get("value", "")))
            )
            self.server_vars_table.setItem(
                row_idx, 2, QTableWidgetItem(str(record.get("expiry", "")))
            )

        self.server_vars_table.resizeColumnsToContents()

    def update_server_variable(self):
        selected_rows = self.server_vars_table.selectedItems()
        if not selected_rows:
            QMessageBox.information(
                self, "No Selection", "Please select a row to update."
            )
            return

        rows = set()
        for item in selected_rows:
            rows.add(item.row())

        success_count = 0
        for row in rows:
            name = self.server_vars_table.item(row, 0).text()
            value = self.server_vars_table.item(row, 1).text()
            expiry = self.server_vars_table.item(row, 2).text()
            if self.db_manager.update_server_variable(name, value, expiry):
                success_count += 1

        QMessageBox.information(
            self,
            "Update Complete",
            f"Updated {success_count} of {len(rows)} selected server variables.",
        )


def main():
    app = QApplication(sys.argv)
    window = ServerManagerApp()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
