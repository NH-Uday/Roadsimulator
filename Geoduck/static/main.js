// Updated main.js with Fastest Route functionality

// Initialize Leaflet map with zoom‑out and panning limits
const germanyBounds = [
  [47.0, 5.5],   // southwest (lat, lon)
  [55.5, 16.5]   // northeast (lat, lon)
];

const map = L.map('map', {
  center: [51.1657, 10.4515],
  zoom: 7,
  preferCanvas: true,
  minZoom: 5,                // prevent zooming out too far
  maxBounds: germanyBounds,  // constrain panning to this box
  maxBoundsViscosity: 1.0    // “stick” to bounds so you can’t pan outside
});

L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
  attribution: '© OpenStreetMap'
}).addTo(map);

let baseLayer;
let metricLayer;
let legend;
let routeLayer;      // polyline for the fastest route
let routeMarkers = []; // markers for origin/destination selections
let routeMode = false;
let routePoints = [];

// Create and configure a spinner element, initially hidden
const spinner = document.createElement('div');
spinner.id = 'loadingSpinner';
Object.assign(spinner.style, {
  position: 'fixed',
  top: '50%',
  left: '50%',
  width: '60px',
  height: '60px',
  margin: '-30px 0 0 -30px',
  border: '8px solid #f3f3f3',
  borderTop: '8px solid #3498db',
  borderRadius: '50%',
  zIndex: 10000,
  display: 'none',
  animation: 'spin 1s linear infinite'
});
document.body.appendChild(spinner);

// Add keyframes for spin animation via a <style> block
const styleEl = document.createElement('style');
styleEl.textContent = `
  @keyframes spin {
    from { transform: rotate(0deg); }
    to   { transform: rotate(360deg); }
  }
`;
document.head.appendChild(styleEl);

/* -------- helpers ----------------------- */
const isoDate = () => document.getElementById('dateInput').value || null;
const vz      = () => document.getElementById('trafficSelect').value || null;
const metric  = () => document.getElementById('metricSelect').value || null;

/* -------- utility to show/hide spinner -------- */
function showSpinner() {
  spinner.style.display = 'block';
}
function hideSpinner() {
  spinner.style.display = 'none';
}

/* -------- Haversine distance (km) -------- */
function haversine(lat1, lon1, lat2, lon2) {
  function toRad(x) { return x * Math.PI / 180; }
  const R = 6371; // Earth radius in km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
            Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
            Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

/* -------- Verlustzeit table renderer  -------- */
function renderVerlustzeit(rows) {
  const div = document.getElementById('verlustzeitTable');
  div.innerHTML = '';
  if (!Array.isArray(rows) || !rows.length) return;

  // If a metric is selected, show only that column; otherwise show all
  const allCols = ['buffertime_mean_index', 'sd_traveltime', 'velocity_65', 'verlustzeit_pro_km'];
  const cols = metric() ? [metric()] : allCols;

  let html = '<table border="1"><thead><tr>' +
             cols.map(c => `<th>${c}</th>`).join('') +
             '</tr></thead><tbody>';
  rows.slice(0,10).forEach(r => {
    html += '<tr>' +
            cols.map(c => `<td>${r[c] ?? ''}</td>`).join('') +
            '</tr>';
  });
  html += '</tbody></table>';
  div.innerHTML = html;
}

/* -------- Base network loader ----------------------------------- */
function loadBaseNetwork() {
  showSpinner();
  fetch('/geojson/joined_netz_data.geojson')
    .then(r => r.json())
    .then(gjson => {
      if (baseLayer) {
        map.removeLayer(baseLayer);
        baseLayer = null;
      }
      baseLayer = L.geoJSON(gjson, {
        style: f => ({
          color: f.properties.color || '#3388ff',
          weight: 4,
          opacity: 0.8
        }),
        onEachFeature: (feat, layer) => {
          const v65 = feat.properties.velocity_65;
          const netz = feat.properties.netzabschnitts_id;
          const originalColor = feat.properties.color || '#3388ff';

          layer.on('mouseover', () => {
            layer.setStyle({ weight: 6, opacity: 1, color: '#ff7800' });
          });
          layer.on('mouseout', () => {
            layer.setStyle({ weight: 4, opacity: 0.8, color: originalColor });
          });

          layer.on('click', () => {
            let popupContent = `<div><strong>Netz Abschnitts ID:</strong> ${netz}</div>`;
            if (v65 != null) {
              popupContent += `<div><strong>35 %-Speed (NVZ):</strong> ${v65.toFixed(2)} km/h</div>`;
            }

            popupContent += `
              <div style="margin-top:6px">
                <a href="http://127.0.0.1:4295/?netzabschnitt=${netz}"
                   target="_blank"
                   style="color:#005ca9;font-weight:bold;text-decoration:underline">
                  Open in Shiny Dashboard&nbsp;&rarr;
                </a>
              </div>`;

            layer.bindPopup(popupContent).openPopup();

            // Clear table and fetch new Verlustzeit rows
            renderVerlustzeit([]);
            showSpinner();
            fetch('/get_verlustzeit', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                netzabschnitt_id: netz,
                date: isoDate(),
                verkehrszeit: vz()
              })
            })
            .then(r => r.json())
            .then(rows => {
              renderVerlustzeit(rows);
              hideSpinner();
            })
            .catch(() => hideSpinner());
          });
        }
      }).addTo(map);
      hideSpinner();
    })
    .catch(err => {
      console.error('Error loading base network:', err);
      hideSpinner();
    });
}

loadBaseNetwork();

/* -------- Coloured metric layer fetcher + click handling ------------------------------ */
function refreshMetricLayer() {
  // Remove old metric layer if it exists
  if (metricLayer) {
    map.removeLayer(metricLayer);
    metricLayer = null;
  }
  // Remove existing legend if present
  if (legend) {
    map.removeControl(legend);
    legend = null;
  }

  // If no metric is selected, restore and show only the base network
  if (!metric()) {
    if (!baseLayer) {
      loadBaseNetwork();
    }
    return;
  }

  // When a metric is selected, remove the base network so it doesn't sit behind
  if (baseLayer) {
    map.removeLayer(baseLayer);
    baseLayer = null;
  }

  const params = new URLSearchParams({
    metric: metric(),
    date: isoDate() || '',
    vz: vz() || ''
  });

  showSpinner();
  fetch(`/metric_geojson?${params.toString()}`)
    .then(r => r.json())
    .then(gjson => {
      if (!gjson.features || !gjson.features.length) {
        alert('Keine Daten für die gewählte Kombination gefunden.');
        hideSpinner();
        return;
      }

      // Extract the metric values to compute min/max
      const values = gjson.features
        .map(f => parseFloat(f.properties[metric()]))
        .filter(v => !isNaN(v));
      const minVal = Math.min(...values);
      const maxVal = Math.max(...values);

      metricLayer = L.geoJSON(gjson, {
        style: f => ({
          color: f.properties.color,
          weight: 4,
          opacity: 0.9
        }),
        onEachFeature: (feat, layer) => {
          // Use dynamic or original velocity for popup
          const v65 = feat.properties.velocity_65_dyn ?? feat.properties.velocity_65;
          const netz = feat.properties.netzabschnitts_id;
          const originalColor = feat.properties.color;

          layer.on('mouseover', () => {
            layer.setStyle({ weight: 6, opacity: 1, color: '#ff7800' });
          });
          layer.on('mouseout', () => {
            layer.setStyle({ weight: 4, opacity: 0.9, color: originalColor });
          });

          layer.on('click', () => {
            let popupContent = `<div><strong>Netz Abschnitts ID:</strong> ${netz}</div>`;
            if (v65 != null) {
              popupContent += `<div><strong>35 %-Speed (NVZ):</strong> ${v65.toFixed(2)} km/h</div>`;
            }
            popupContent += `
              <div style="margin-top:6px">
                <a href="http://127.0.0.1:4295/?netzabschnitt=${netz}"
                   target="_blank"
                   style="color:#005ca9;font-weight:bold;text-decoration:underline">
                  Open in Shiny Dashboard&nbsp;&rarr;
                </a>
              </div>`;

            layer.bindPopup(popupContent).openPopup();

            // Clear table and fetch updated Verlustzeit rows
            renderVerlustzeit([]);
            showSpinner();
            fetch('/get_verlustzeit', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                netzabschnitt_id: netz,
                date: isoDate(),
                verkehrszeit: vz()
              })
            })
            .then(r => r.json())
            .then(rows => {
              renderVerlustzeit(rows);
              hideSpinner();
            })
            .catch(() => hideSpinner());
          });
        }
      }).addTo(map);

      // Create and add a continuous-gradient legend control
      legend = L.control({ position: 'bottomright' });
      legend.onAdd = function(map) {
        const div = L.DomUtil.create('div', 'info legend');
        div.innerHTML += `<b>${metric()}</b><br>`;

        // Viridis approximate gradient: #440154 → #31688e → #35b779 → #fde725
        const gradientBar = `
          <div style="
            width: 180px;
            height: 12px;
            background: linear-gradient(
              to right,
              #440154 0%,
              #31688e 33%,
              #35b779 66%,
              #fde725 100%
            );
            margin-bottom: 4px;
          "></div>`;

        div.innerHTML += gradientBar;
        div.innerHTML += `<span style="float:left;">${minVal.toFixed(2)}</span>`;
        div.innerHTML += `<span style="float:right;">${maxVal.toFixed(2)}</span>`;
        div.innerHTML += `<div style="clear: both;"></div>`;

        return div;
      };
      legend.addTo(map);

      hideSpinner();
    })
    .catch(err => {
      console.error('metric layer fetch error:', err);
      alert('Fehler beim Laden der Kennzahl-Karte.');
      hideSpinner();
    });
}

/* -------- Fastest Route selection and fetching ---------------------------------- */
function enableRouteMode() {
  routeMode = true;
  routePoints = [];
  routeMarkers.forEach(m => map.removeLayer(m));
  routeMarkers = [];
  if (routeLayer) {
    map.removeLayer(routeLayer);
    routeLayer = null;
  }
  alert('Please click to select ORIGIN and DESTINATION on the map');
}

function onMapClick(e) {
  if (!routeMode) return;
  const { lat, lng } = e.latlng;
  routePoints.push([lat, lng]);

  const marker = L.circleMarker([lat, lng], { radius: 6, color: 'red' }).addTo(map);
  routeMarkers.push(marker);

  if (routePoints.length === 2) {
    routeMode = false;
    fetchRoute();
  }
}

map.on('click', onMapClick);

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('btnMetricRefresh')
          .addEventListener('click', refreshMetricLayer);
  document.getElementById('btnRoute')
          .addEventListener('click', enableRouteMode);

  // Typing animation for the title (using textContent to preserve spaces correctly)
  const t = 'Welcome to Roadsimulator';
  const el = document.getElementById('title');
  let i = 0;
  (function typeWriter() {
    if (i < t.length) {
      el.textContent += t[i++];
      setTimeout(typeWriter, 200);
    } else {
      el.style.borderRight = 'none';
    }
  })();
});