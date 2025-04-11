import duckdb
from datetime import datetime
import pandas as pd
import geopandas as gpd
from shapely.wkt import loads as wkt_loads
import os

class DBManager:
    def __init__(self, db_path="my_duckdb.duckdb"):
        self.db_path = db_path

    def get_connection(self):
        return duckdb.connect(database=self.db_path)

    def create_tables(self):
        with self.get_connection() as con:
            commands = [
                "CREATE TABLE IF NOT EXISTS netz AS SELECT * FROM read_csv_auto('/home/gut11/data/netz.csv')",
            ]
            for command in commands:
                try:
                    con.execute(command)
                    print(f"Successfully executed: {command}")
                except Exception as e:
                    print(f"Failed to execute {command}: {str(e)}")

    def load_and_convert_from_db(self):
        with self.get_connection() as con:
            query = "SELECT * FROM netz"
            data = con.execute(query).fetchdf()
            data['geometry'] = data['geometry'].apply(wkt_loads)
            return gpd.GeoDataFrame(data, geometry='geometry', crs="EPSG:4326")

    def save_to_geojson(self, gdf, output_file):
        gdf.to_file(output_file, driver="GeoJSON")

    def get_max_cumulative_time(self, netzabschnitt_id, date=None, start_time=None):
        """
        Returns the maximum cumulative_time_minutes for a given netzabschnitt_id, date, and start_time
        (always reading from dynamic_traveltimes_04_09 as demonstration).
        """
        with self.get_connection() as con:
            query = (
                "SELECT cumulative_time_minutes "
                "FROM '/home/gut11/data/dynamic_traveltimes_04_09/dynamic_traveltime_results_*.csv' "
                f"WHERE netzabschnitt = {netzabschnitt_id}"
            )

            if date:
                query += f" AND wochentag = '{date}'"
            if start_time:
                query += f" AND start_time = '{start_time}'"

            query += " ORDER BY cumulative_time_minutes DESC LIMIT 1"

            try:
                result = con.execute(query).fetchone()
                return result[0] if result else None
            except Exception as e:
                print("[ERROR get_max_cumulative_time]", e)
                raise

    def get_travel_time_index_all(self, netzabschnitt_id):
        """
        Joins dynamic_traveltimes_04_09 with mean_traveltime_4_6.csv to compute travel_time_index_mean/median.
        Casts start_time to VARCHAR so it's JSON-serializable.
        Returns top 5 rows by travel_time_index_mean DESC.
        """
        with self.get_connection() as con:
            query = f"""
                SELECT
                    CAST(a.start_time AS VARCHAR) AS start_time,
                    a.wochentag,
                    a.cumulative_time_minutes,
                    cumulative_time_minutes / mean_traveltime   AS travel_time_index_mean,
                    cumulative_time_minutes / median_traveltime AS travel_time_index_median
                FROM read_csv('/home/gut11/data/dynamic_traveltimes_04_09/*.csv') a
                LEFT JOIN read_csv('/home/gut11/data/mean_traveltime_4_6.csv') b
                       ON a.netzabschnitt = b.netzabschnitt
                WHERE a.netzabschnitt = {netzabschnitt_id}
                ORDER BY travel_time_index_mean DESC
            """
            try:
                df = con.execute(query).fetchdf()
                return df
            except Exception as e:
                print("[ERROR get_travel_time_index_top5]", e)
                raise
