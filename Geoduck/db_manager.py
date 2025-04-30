import duckdb
from datetime import datetime
import pandas as pd
import geopandas as gpd
from shapely.wkt import loads as wkt_loads
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import os

def colorize_viridis(gdf, colname='median_traveltime'):

    if colname not in gdf.columns:
        print(f"WARNING: Column '{colname}' not found. Using gray #cccccc.")
        gdf['color'] = '#cccccc'
        return gdf

    vmin = gdf[colname].min()
    vmax = gdf[colname].max()
    if pd.isna(vmin) or pd.isna(vmax):
        print(f"WARNING: All values in '{colname}' are NaN. Using #cccccc.")
        gdf['color'] = '#cccccc'
        return gdf

    norm = mcolors.Normalize(vmin=vmin, vmax=vmax, clip=True)
    cmap = plt.get_cmap('viridis')

    def val_to_hex(val):
        if pd.isna(val):
            return '#cccccc'
        rgba = cmap(norm(val))  # (r, g, b, alpha)
        return mcolors.to_hex(rgba, keep_alpha=False)

    gdf['color'] = gdf[colname].apply(val_to_hex)
    return gdf

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
        

    def get_verlustzeit_table(self,
                          netzabschnitt_id: int | None = None,
                          date_iso: str | None = None,
                          verkehrszeit: str | None = None):
               
        base_sql = """
        SELECT *,
                a.netzabschnitt,
                buffertime_mean_index,
                sd_traveltime,
                avg_traveltime_velocity velocity_65,
               (avg_traveltime - 60 * (laenge_netzabschnitt_km / velocity_65))
               / laenge_netzabschnitt_km AS verlustzeit_pro_km
        FROM  read_parquet('/home/gut11/data/indicators_fahrtzeitzuverlaessigkeit.parquet') a
        JOIN  read_csv('/home/gut11/data/netzabschnitte_length_jtr.csv')  b
              ON a.netzabschnitt = b.netzabschnitt
        LEFT JOIN read_csv('/home/gut11/data/sollgeschwindigkeiten_freier_fluss.csv') c
              ON a.netzabschnitt = c.netzabschnitts_id
        LEFT JOIN read_csv('/home/gut11/shiny_app/data/netze_geom.csv')                     g
              ON a.netzabschnitt = g.netzabschnitt
        WHERE sd_traveltime > 0
          AND avg_traveltime_velocity <= 110
          AND a.netzabschnitt != 259
        """
        extra = []
        if netzabschnitt_id is not None:
            extra.append(f"a.netzabschnitt = {netzabschnitt_id}")

        if date_iso:        
            extra.append(f"wochentag = CAST('{date_iso}' AS DATE)")

        if verkehrszeit:
            extra.append(f"verkehrszeit_agg = '{verkehrszeit}'")

        if extra:
            base_sql += " AND " + " AND ".join(extra)

        with self.get_connection() as con:
            return con.execute(base_sql).fetchdf()
          

    def build_metric_geojson(
            self,
            date_iso: str | None,
            verkehrszeit: str | None,
            metric_col: str
        ) -> dict:
    
        df = self.get_verlustzeit_table(
                netzabschnitt_id = None,
                date_iso         = date_iso,
                verkehrszeit     = verkehrszeit
            )

        if df.empty:
            return { "type":"FeatureCollection", "features":[] }

        if metric_col == "velocity_65":           
            df["velocity_65_dyn"] = df["avg_traveltime_velocity"]
            metric_col = "velocity_65_dyn"  
        
        # 2) build geometry
        if 'wkt' not in df.columns:
            raise ValueError("Column 'wkt' missing – check the join in get_verlustzeit_table")

        df['geometry'] = df['wkt'].apply(lambda w: wkt_loads(w) if pd.notna(w) else None)
        gdf = gpd.GeoDataFrame(df, geometry='geometry', crs='EPSG:4326')

        # 3) colourise by requested metric
        gdf = colorize_viridis(gdf, colname=metric_col)

        # 4) return as plain dict 
        return gdf.__geo_interface__


def loads_wkt(val):
    if val is None:
        return None
    return wkt_loads(val)