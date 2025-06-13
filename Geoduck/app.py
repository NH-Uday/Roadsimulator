from flask import Flask, jsonify, request, Response, render_template, send_from_directory
from flask_cors import CORS
from flask import send_file, request, jsonify
from db_manager import DBManager
import numpy as np
import os

app = Flask(__name__)
CORS(app)
db_manager = DBManager()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/init_db', methods=['POST'])
def init_db():
    try:
        results = db_manager.create_tables()
        return jsonify({"message": "Database initialized", "details": results}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/geojson/<filename>')
def serve_geojson(filename):
    return send_from_directory(os.path.join(app.root_path, 'geojson'), filename)

@app.route('/generate_default_geojson', methods=['GET'])
def generate_default_geojson():
    gdf = db_manager.load_and_convert_from_db()
    output_file = os.path.join('geojson', 'default_netz_data.geojson')
    db_manager.save_to_geojson(gdf, output_file)
    return jsonify({"message": "GeoJSON generated successfully.", "file_path": output_file})
    
    
@app.route('/get_verlustzeit', methods=['POST'])
def get_verlustzeit():
    try:
        data = request.get_json(force=True)
        df = db_manager.get_verlustzeit_table(
                netzabschnitt_id = data.get('netzabschnitt_id'),
                date_iso         = data.get('date'),
                verkehrszeit     = data.get('verkehrszeit')  
             )
        return jsonify(df.replace({np.nan: None, np.inf: None, -np.inf: None})
                         .to_dict(orient="records")), 200
    except Exception as exc:
        print("[ERROR /get_verlustzeit]", exc)
        return jsonify({"error": str(exc)}), 500
    

@app.route('/metric_geojson', methods=['GET'])
def metric_geojson():

    date_iso      = request.args.get('date')        
    verkehrszeit  = request.args.get('vz')         
    metric_column = request.args.get('metric')     

    if metric_column not in {
        'buffertime_mean_index', 'sd_traveltime',
        'velocity_65', 'verlustzeit_pro_km'
    }:
        return jsonify({"error": "invalid metric"}), 400

    try:
        geojson = db_manager.build_metric_geojson(date_iso, verkehrszeit, metric_column)
        return jsonify(geojson), 200
    except Exception as exc:
        print("[ERROR /metric_geojson]", exc)
        return jsonify({"error": str(exc)}), 500

@app.route('/fastest_route', methods=['POST'])
def fastest_route():
    data = request.get_json(force=True)
    origin = data['origin']      # { "lat": 52.52, "lon": 13.40 }
    dest   = data['destination'] # { "lat": 53.55, "lon": 10.01 }
    date_iso     = data.get('date')        # e.g. "2025-06-03"
    verkehrszeit = data.get('verkehrszeit')# e.g. "abendliche Hauptverkehrszeit"

    node_path, path_edges, total_sec = rp.find_fastest_route(
        origin['lat'], origin['lon'],
        dest['lat'],   dest['lon'],
        date_iso, verkehrszeit
    )
    if node_path is None:
        return jsonify({"error":"no path found"}), 404

    return jsonify({
        "node_sequence": node_path,
        "edges": path_edges,
        "total_time_seconds": total_sec
    }), 200


if __name__ == "__main__":
    app.run(debug=True, port=5000)
