# FFXI Server Manager

A PyQt6-based UI program to monitor and manage the FFXI Test Server's campaign functions and other server-side statistics.

## Features

*   Monitor active sessions, unique IPs, and players per zone.
*   View and modify campaign-related data (campaign_map, campaign_nation, conquest_system, server_variables) directly in the database.
*   Trigger campaign events through database updates.

## Setup

1.  **Prerequisites:**
    *   Python 3.x
    *   FFXI Test Server running (with MariaDB database and HTTP API enabled).

2.  **Clone the Repository:**
    ```bash
    cd FFXI_TestServer
    # Assuming this project is within the FFXI_TestServer directory
    ```

3.  **Navigate to ServerManager:**
    ```bash
    cd ServerManager
    ```

4.  **Create and Activate Virtual Environment:**
    ```bash
    python -m venv venv
    .\venv\Scripts\activate  # On Windows
    # source venv/bin/activate  # On macOS/Linux
    ```

5.  **Install Dependencies:**
    ```bash
    pip install -r requirements.txt
    ```

    > The pinned dependencies (`PyQt6`, `mysql-connector-python`, `requests`) live in
    > [`requirements.txt`](requirements.txt). They must be installed into the
    > `ServerManager/venv` virtualenv — not into the system Python — so that Pylance
    > and the GUI can both find them.
    >
    > If you prefer the manual route, the equivalent command is:
    > ```bash
    > pip install PyQt6 mysql-connector-python requests
    > ```

6.  **Configure Database and HTTP Server Settings:**
    *   Open `config.py`.
    *   Update `DB_CONFIG` with your MariaDB credentials (especially the password).
    *   Verify `HTTP_SERVER_URL` matches your FFXI Test Server's HTTP API address.

## Usage

1.  **Run the application:**
    ```bash
    python main.py
    ```

2.  **Interact with the UI:**
    *   Use the "Refresh Data" button to fetch and display the latest server and campaign information.
    *   (Future: More UI components for detailed monitoring and modification will be added here.)

## Project Structure

```
ServerManager/
├── venv/                 # Python virtual environment
├── config.py             # Configuration for database and HTTP server
├── database_manager.py   # Handles database connections and operations
├── http_client.py        # Handles HTTP requests to the server's API
├── main.py               # Main application entry point and UI setup
└── README.md             # Project README
```
