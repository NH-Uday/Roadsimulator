🛣️ Roadsimulator – Interactive Road Network Visualizer for Germany
Roadsimulator is a full-stack geospatial web application designed to explore and analyze traffic metrics across German road networks. Built using a Flask backend and a Leaflet-powered frontend, the application allows users to visualize traffic performance data, simulate travel routes, and interact with spatial segments for deeper analysis.

🚦 Ideal for transport analysts, researchers, and urban planners.

🧩 Tech Stack
Layer	Technology
Backend	Python, Flask, DuckDB
Frontend	HTML5, Leaflet.js, JS
Styling	CSS3, Google Fonts
Geospatial	GeoPandas, Shapely
Data	CSV + Parquet files

🎯 Features
🔍 Explore Road Segments with hover and popup info

🧠 Verlustzeit Table showing travel time indicators

📊 Selectable Metrics: Buffer Time, Travel Deviation, Velocity, Loss per km

🗺️ Color-Mapped GeoJSON Layers with dynamic styling

🧭 Route Simulation by selecting origin and destination

🌀 Loading Spinner & Typing Title for improved UX

📎 External Integration with a Shiny Dashboard

🚀 Getting Started
1. Clone the Repository
bash
Copy
Edit
git clone https://github.com/NH-Uday/roadsimulator.git
cd roadsimulator
2. Set Up Python Environment
bash
Copy
Edit
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt
3. Check Data Paths
Make sure these files exist in your system:

bash
Copy
Edit
/home/gut11/data/netz.csv
/home/gut11/data/netzabschnitte_length_jtr.csv
/home/gut11/data/sollgeschwindigkeiten_freier_fluss.csv
/home/gut11/data/indicators_fahrtzeitzuverlaessigkeit.parquet
/home/gut11/shiny_app/data/netze_geom.csv
Adjust the paths in db_manager.py if you're using a different directory structure.

4. Run the Flask App
bash
Copy
Edit
python app.py
App runs at: http://localhost:5000

📁 Project Structure
graphql
Copy
Edit
.
├── app.py               # Flask API and routes
├── db_manager.py        # DuckDB + GeoPandas data logic
├── templates/
│   └── index.html       # Main HTML frontend
├── static/
│   ├── main.js          # Leaflet map & interaction
│   └── style.css        # Styling and animation
├── geojson/             # Output directory for generated GeoJSON
├── requirements.txt     # Python dependencies


🌐 Key API Endpoints
Method	Endpoint	Description
POST	/init_db	Initializes tables in DuckDB
GET	/generate_default_geojson	Saves GeoJSON from netz table
GET	/geojson/<filename>	Serves any GeoJSON from directory
POST	/get_verlustzeit	Retrieves traffic stats per segment
GET	/metric_geojson?date=&vz=&metric=	Returns metric-colored GeoJSON

🎨 Map + UI Features
Built with Leaflet.js and OpenStreetMap tiles

Click segments to:

View detailed metrics

Load data into a popup and table

Navigate to Shiny dashboard

Color mapping via Matplotlib's Viridis scale

Animated title using CSS keyframes

Custom route selection and Haversine-based route logic

📈 Metrics Supported
buffertime_mean_index

sd_traveltime

velocity_65

verlustzeit_pro_km

💡 Future Enhancements
JWT-secured endpoints

Docker container for deployment

Mobile-friendly responsive layout

Expand to real-time traffic feeds (via API)

Export route analysis as PDF/CSV

👤 Author
Md Nahin Hossain Uday
🎓 MSc. in Computer Simulation in Science – University of Wuppertal
📬 nahinu95@gmail.com

🪪 License
This project is licensed under the MIT License.
Feel free to use, fork, and enhance it.
