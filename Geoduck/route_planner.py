# route_planner.py

import duckdb
import pandas as pd
import geopandas as gpd
from shapely.wkt import loads as wkt_loads
from shapely.geometry import Point
import numpy as np
import networkx as nx
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
import pickle
import os

# -----------------------------------------------
# Step 1: Extract & prepare training data from DuckDB
# -----------------------------------------------

class RoutePlanner:
    def __init__(self, db_path="my_duckdb.duckdb", model_path="travel_time_model.pkl"):
        self.db_path = db_path
        self.model_path = model_path
        self.model = None
        self.G = None  # will hold our NetworkX graph
        # We'll store a GeoDataFrame of 'netz' so we can locate endpoints for arbitrary lat/lon
        self.netz_gdf = None  

    def get_connection(self):
        return duckdb.connect(database=self.db_path)

    def load_network_segments(self):
        """
        Load the 'netz' table (CSV) from DuckDB, parse WKT into geometry,
        and store as a GeoDataFrame.
        """
        with self.get_connection() as con:
            df = con.execute("SELECT * FROM netz").fetchdf()
        # Parse WKT → shapely
        df['geometry'] = df['geometry'].apply(wkt_loads)
        gdf = gpd.GeoDataFrame(df, geometry='geometry', crs="EPSG:4326")
        self.netz_gdf = gdf
        return gdf

    def assemble_training_dataframe(self):
        """
        Join historical travel‐time data to segment metadata so we can train a regression.
        Returns a pandas.DataFrame with one row per (netzabschnitt, date, traffic_period).
        """
        with self.get_connection() as con:
            # 1) Read indicators (Parquet) + length + free-flow speed + date/time features
            qry = """
            WITH hist AS (
                SELECT 
                    a.netzabschnitt,
                    a.wochentag AS date_iso,
                    a.verkehrszeit_agg AS verkehrszeit,
                    a.avg_traveltime AS traveltime_seconds,
                    a.avg_traveltime_velocity AS velocity_kmh,
                    b.laenge_netzabschnitt_km,
                    c.free_flow_speed_kmh
                FROM read_parquet('/home/gut11/data/indicators_fahrtzeitzuverlaessigkeit.parquet') a
                JOIN read_csv('/home/gut11/data/netzabschnitte_length_jtr.csv') b
                  ON a.netzabschnitt = b.netzabschnitt
                LEFT JOIN read_csv('/home/gut11/data/sollgeschwindigkeiten_freier_fluss.csv') c
                  ON a.netzabschnitt = c.netzabschnitts_id
                WHERE a.sd_traveltime > 0
                  AND a.avg_traveltime_velocity <= 110
                  AND a.netzabschnitt != 259
            )
            SELECT 
                h.*,
                EXTRACT(DOW FROM CAST(h.date_iso AS DATE)) AS wochentag_num
            FROM hist h
            """
            train_df = con.execute(qry).fetchdf()

        # Convert categorical 'verkehrszeit' to one‐hot encoding
        train_df = pd.get_dummies(train_df, columns=['verkehrszeit'], drop_first=True)

        # Drop any rows with missing free_flow_speed or length
        train_df = train_df.dropna(subset=['laenge_netzabschnitt_km', 'free_flow_speed_kmh', 'traveltime_seconds'])

        return train_df

    def train_or_load_model(self):
        """
        Either load a pre‐trained RandomForest model from disk, or train from scratch.
        We predict target = traveltime_seconds, features = [length, free_flow_speed, velocity_kmh, wochentag, one‐hot(verkehrszeit)]
        """
        if os.path.exists(self.model_path):
            with open(self.model_path, 'rb') as f:
                self.model = pickle.load(f)
            print("Loaded existing model from disk.")
            return self.model

        df = self.assemble_training_dataframe()

        # Features
        features = [
            'laenge_netzabschnitt_km',
            'free_flow_speed_kmh',
            'velocity_kmh',
            'wochentag_num'
        ] + [col for col in df.columns if col.startswith('verkehrszeit_')]
        X = df[features]
        y = df['traveltime_seconds']

        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

        rf = RandomForestRegressor(n_estimators=100, max_depth=10, random_state=42, n_jobs=-1)
        rf.fit(X_train, y_train)

        print("Train R² score:", rf.score(X_test, y_test))

        # Save to disk
        with open(self.model_path, 'wb') as f:
            pickle.dump(rf, f)
        self.model = rf
        return rf

    # -----------------------------------------------
    # Step 2: Build a graph (NetworkX) from netz_gdf
    # -----------------------------------------------

    def build_graph(self):
        """
        For each network segment (netzabschnitt) in netz_gdf:
          - extract its two endpoints (shapely LineString → coords[0], coords[-1])
          - create two nodes in the graph (if they don't exist already), keyed by their lat/lon tuple
          - add a directed edge from start→end and end→start with a placeholder weight (we'll update later)
        The node names will simply be the coordinate tuples. 
        We'll store 'netzabschnitt' as an edge attribute so we can look it up later.
        """
        if self.netz_gdf is None:
            self.load_network_segments()

        G = nx.DiGraph()

        for idx, row in self.netz_gdf.iterrows():
            line = row.geometry
            if line is None or line.geom_type not in ['LineString', 'MultiLineString']:
                continue

            # For simplicity, handle only simple LineString
            if line.geom_type == 'LineString':
                coords = list(line.coords)
            else:
                # If MultiLineString, break into its first part
                coords = list(list(line.geoms)[0].coords)

            start_pt = tuple(coords[0])  # (lon, lat)
            end_pt = tuple(coords[-1])   # (lon, lat)
            seg_id = row['netzabschnitt']

            # Add nodes if they don't exist
            if start_pt not in G:
                G.add_node(start_pt, pos=start_pt)
            if end_pt not in G:
                G.add_node(end_pt, pos=end_pt)

            # Add edges both directions
            G.add_edge(start_pt, end_pt, netz_id=seg_id, weight=1.0)
            G.add_edge(end_pt, start_pt, netz_id=seg_id, weight=1.0)

        self.G = G
        return G

    # ---------------------------------------------------
    # Step 3: A function to recompute edge weights (travel time)
    # ---------------------------------------------------

    def update_edge_weights(self, date_iso: str, verkehrszeit: str):
        """
        Use the regression model to predict travel time on each segment 
        for the specified date_iso and verkehrszeit. Then update G[u][v]['weight'] accordingly.
        """
        if self.model is None:
            self.train_or_load_model()
        if self.G is None:
            self.build_graph()

        # 1) Gather required metadata for each edge (netzabschnitt)
        # We'll query DuckDB to get length, free_flow_speed, velocity_kmh for that date & traffic period.

        # Create a temporary table (or DataFrame) keyed by netzabschnitt for the given date/verkehrszeit
        with self.get_connection() as con:
            qry = f"""
            WITH stats AS (
              SELECT 
                a.netzabschnitt,
                a.avg_traveltime_velocity AS velocity_kmh,
                b.laenge_netzabschnitt_km,
                c.free_flow_speed_kmh,
                EXTRACT(DOW FROM CAST('{date_iso}' AS DATE)) AS wochentag_num,
                a.verkehrszeit_agg
              FROM read_parquet('/home/gut11/data/indicators_fahrtzeitzuverlaessigkeit.parquet') a
              JOIN read_csv('/home/gut11/data/netzabschnitte_length_jtr.csv') b
                ON a.netzabschnitt = b.netzabschnitt
              LEFT JOIN read_csv('/home/gut11/data/sollgeschwindigkeiten_freier_fluss.csv') c
                ON a.netzabschnitt = c.netzabschnitts_id
              WHERE CAST(a.wochentag AS DATE) = CAST('{date_iso}' AS DATE)
                AND a.verkehrszeit_agg = '{verkehrszeit}'
                AND a.sd_traveltime > 0
                AND a.avg_traveltime_velocity <= 110
                AND a.netzabschnitt != 259
            )
            SELECT 
              netzabschnitt, 
              velocity_kmh,
              laenge_netzabschnitt_km,
              free_flow_speed_kmh,
              wochentag_num,
              verkehrszeit_agg
            FROM stats
            """
            edge_stats = con.execute(qry).fetchdf()

        # One-hot encode 'verkehrszeit'
        edge_stats = pd.get_dummies(edge_stats, columns=['verkehrszeit_agg'], drop_first=True)

        # For any segment missing in this specific period, fall back to historical average:
        #   compute its mean velocity_kmh & free_flow_speed & wochentag_num from the entire history
        if not edge_stats.empty and len(edge_stats) < len(self.netz_gdf):
            hist = self.assemble_training_dataframe()
            hist_mean = (
                hist.groupby('netzabschnitt')
                    .agg({
                      'velocity_kmh':'mean',
                      'laenge_netzabschnitt_km':'first',
                      'free_flow_speed_kmh':'mean',
                      'wochentag_num':'mean'
                    })
                    .reset_index()
            )
            # Identify missing segments
            missing = set(self.netz_gdf['netzabschnitt']) - set(edge_stats['netzabschnitt'])
            if missing:
                missing_df = hist_mean[hist_mean['netzabschnitt'].isin(missing)].copy()
                # Add dummy one-hot columns (all zeros) for verkehrszeit
                for col in [c for c in edge_stats.columns if c.startswith('verkehrszeit_')]:
                    missing_df[col] = 0
                missing_df['verkehrszeit_agg'] = verkehrszeit
                missing_df['wochentag_num'] = missing_df['wochentag_num'].round().astype(int)
                edge_stats = pd.concat([edge_stats, missing_df[edge_stats.columns]], ignore_index=True)

        # Now, for every edge in the graph, look up its netzabschnitt and predict travel time
        features = [
            'laenge_netzabschnitt_km',
            'free_flow_speed_kmh',
            'velocity_kmh',
            'wochentag_num'
        ] + [col for col in edge_stats.columns if col.startswith('verkehrszeit_')]

        edge_stats = edge_stats.set_index('netzabschnitt')  # so we can lookup by segment ID

        # Loop through each directed edge, update weight
        for u, v, data in self.G.edges(data=True):
            seg_id = data['netz_id']
            if seg_id not in edge_stats.index:
                # If still missing, assign a very high weight so it's avoided
                self.G[u][v]['weight'] = 1e6
                continue

            row = edge_stats.loc[seg_id:seg_id]
            X_feat = row[features].values.reshape(1, -1)
            pred_t = float(self.model.predict(X_feat))  # predicted travel time in seconds
            self.G[u][v]['weight'] = max(pred_t, 0.1)  # ensure positive
        return True

    # ---------------------------------------------------
    # Step 4: Find the nearest graph‐node to an arbitrary lat/lon
    # ---------------------------------------------------

    def nearest_node(self, lat, lon):
        """
        Given a latitude/longitude, find the closest node (in Euclidean distance)
        among the Graph’s nodes. 
        """
        if self.G is None:
            self.build_graph()

        # Convert node keys → np.array for fast distance
        coords = np.array(list(self.G.nodes))
        # Each node is stored as (lon, lat)
        lats = coords[:, 1]
        lons = coords[:, 0]

        # Compute squared Euclidean distance (in degrees).
        # For Germany-scale, this is fine for nearest. 
        d2 = (lats - lat)**2 + (lons - lon)**2
        idx = np.argmin(d2)
        chosen = tuple(coords[idx])
        return chosen  # (lon, lat)

    # ---------------------------------------------------
    # Step 5: Compute fastest route between two lat/lon points
    # ---------------------------------------------------

    def find_fastest_route(self, latA, lonA, latB, lonB, date_iso, verkehrszeit):
        """
        1) Rebuild/update weights for all edges based on date_iso & verkehrszeit 
        2) Locate nearest graph nodes to (latA, lonA) & (latB, lonB) 
        3) Run Dijkstra’s algorithm to get the shortest path
        Returns: 
          - path_nodes: list of node coordinates (lon, lat)
          - path_edges: list of (u→v) with segment IDs & predicted time
          - total_time_seconds
        """
        # 1) Update weights
        self.update_edge_weights(date_iso, verkehrszeit)

        # 2) Find nearest nodes
        src_node = self.nearest_node(latA, lonA)
        dst_node = self.nearest_node(latB, lonB)

        # 3) Dijkstra
        try:
            node_path = nx.shortest_path(self.G, source=src_node, target=dst_node, weight='weight')
            total_time = nx.shortest_path_length(self.G, source=src_node, target=dst_node, weight='weight')
        except nx.NetworkXNoPath:
            return None, None, float('inf')

        # 4) Convert nodes → edges with segment IDs + predicted time
        path_edges = []
        for i in range(len(node_path) - 1):
            u = node_path[i]
            v = node_path[i+1]
            edge_data = self.G[u][v]
            seg_id = edge_data['netz_id']
            seg_time = edge_data['weight']
            path_edges.append({
                'netzabschnitt': seg_id,
                'predicted_traveltime_sec': seg_time
            })

        # Convert node_path from (lon, lat) → (lat, lon) if desired, but we keep as (lon,lat)
        return node_path, path_edges, total_time


# ---------------------------
# Example usage:
# ---------------------------

if __name__ == "__main__":
    rp = RoutePlanner(db_path="my_duckdb.duckdb", model_path="travel_time_model.pkl")

    # 1) Train model (if not already saved)
    rp.train_or_load_model()

    # 2) Build graph once
    rp.build_graph()

    # 3) Query fastest route between two locations (lat/lon)
    #    For example: Berlin Alexanderplatz → Hamburg Hauptbahnhof
    latA, lonA = 52.521918, 13.413215  # Berlin Alexanderplatz
    latB, lonB = 53.552639, 10.006774  # Hamburg HBf
    date_iso = "2025-06-03"
    verkehrszeit = "abendliche Hauptverkehrszeit"

    nodes, edges, total_sec = rp.find_fastest_route(latA, lonA, latB, lonB, date_iso, verkehrszeit)

    if nodes is None:
        print("No path found.")
    else:
        print("Node‐sequence (lon,lat):", nodes)
        print("Segment IDs with predicted times (sec):")
        for e in edges:
            print(f"  Netz‐ID {e['netzabschnitt']} → {e['predicted_traveltime_sec']:.1f}s")
        print(f"Total predicted travel time: {total_sec/60:.2f} minutes")
