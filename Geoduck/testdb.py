def create_geojson_with_colors(self, output_file):
        
        df = self.get_joined_netze_data()

        df['geometry'] = df['wkt'].apply(wkt_loads)

        # Convert to GeoDataFrame
        gdf = gpd.GeoDataFrame(df, geometry='geometry', crs="EPSG:4326")

        # Colorize by velocity_65
        gdf = colorize_viridis(gdf, colname='velocity_65')

        # Save to GeoJSON
        gdf.to_file(output_file, driver="GeoJSON")
        print(f"Saved joined netze data with color to {output_file}")
        
        
        def create_color_map_for_date_time(
        self,
        date_str: str,
        time_str: str,
        netzabschnitt_id: int | None,          
        output_dir: str = "geojson"
            ) -> str:

        safe_time = time_str.replace(":", "-")
        file_name = f"dynamic_color_map_{date_str}_{safe_time}.geojson"
        output_file = os.path.join(output_dir, file_name)

        query = f"""
        SELECT
            CAST(a.start_time AS VARCHAR)                  AS start_time,
                a.wochentag,
                a.cumulative_time_minutes,
                b.mean_traveltime,
                b.median_traveltime,
                a.cumulative_time_minutes / b.mean_traveltime   AS travel_time_index_mean,
                a.cumulative_time_minutes / b.median_traveltime AS travel_time_index_median,
                c.wkt,
                a.netzabschnitt
        FROM read_csv('/home/gut11/data/dynamic_traveltimes_04_09/*.csv') a
        LEFT JOIN read_csv('/home/gut11/data/mean_traveltime_4_6.csv')   b
           ON a.netzabschnitt = b.netzabschnitt
        LEFT JOIN read_csv('/home/gut11/shiny_app/data/netze_geom.csv')  c
           ON a.netzabschnitt = c.netzabschnitt
        WHERE a.start_time = '{time_str}'
            AND a.wochentag  = '{date_str}'
           
        """

        with self.get_connection() as con:
            print("[DEBUG] Running query:\n", query)
            df = con.execute(query).fetchdf()

        df["geometry"] = df["wkt"].apply(
            lambda w: wkt_loads(w) if pd.notna(w) else None
        )
        gdf = gpd.GeoDataFrame(df, geometry="geometry", crs="EPSG:4326")
        gdf = colorize_viridis(gdf, colname="median_traveltime")

        os.makedirs(output_dir, exist_ok=True)
        gdf.to_file(output_file, driver="GeoJSON")
        print(f"[INFO] Saved map ➜ {output_file}")
        return output_file