from flask import Flask, jsonify, request, render_template, send_from_directory
from flask_cors import CORS
from db_manager import DBManager
import os
import pandas as pd

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

@app.route('/get_cumulative_time', methods=['POST'])
def get_cumulative_time():
    """
    Returns a single cumulative_time_minutes for given netzabschnitt_id, date, start_time
    """
    try:
        data = request.json
        netzabschnitt_id = data.get('netzabschnitt_id')
        date = data.get('date')
        start_time = data.get('start_time')

        cumulative_time = db_manager.get_max_cumulative_time(netzabschnitt_id, date, start_time)
        return jsonify({"cumulative_time_minutes": cumulative_time}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/get_travel_time_index', methods=['POST'])
def get_travel_time_index():

    try:
        data = request.json
        netzabschnitt_id = data.get('netzabschnitt_id')

        df = db_manager.get_travel_time_index_all(netzabschnitt_id)
        result_list = df.to_dict(orient='records')
        return jsonify(result_list), 200
    except Exception as e:
        # if an error occurs, we return a JSON with key 'error'
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True, port=5000)
