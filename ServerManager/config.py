# config.py

DB_CONFIG = {
    "host": "127.0.0.1",
    "user": "root",
    "password": "exolis",  # Matches settings/network.lua
    "database": "xidb",  # Matches settings/network.lua
    "port": 3306,  # Matches settings/network.lua SQL_PORT
    "auth_plugin": "mysql_native_password",  # Explicitly avoid GSSAPI auth
}

HTTP_SERVER_URL = "http://127.0.0.1:8088/api"  # Matches settings/network.lua HTTP_PORT
