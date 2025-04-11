const map = L.map('map', {
    center: [51.1657, 10.4515],
    zoom: 6,
    preferCanvas: true,
  });
  
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
  }).addTo(map);
  
  let geoJsonLayer;
  
  /**
   * Builds a minimal D3 line chart for 'travel_time_index_mean'.
   * The chart will appear in the <div id="timeIndexChart">.
   * - data: array of objects, each with travel_time_index_mean
   */
  function buildLineChart(data) {
    // Clear any existing chart
    d3.select('#timeIndexChart').selectAll('*').remove();
  
    if (!Array.isArray(data) || data.length === 0) {
      return;
    }
  
    // Chart dimensions
    const width = 400;
    const height = 200;
    const margin = { top: 20, right: 20, bottom: 30, left: 40 };
  
    // Create SVG
    const svg = d3
      .select('#timeIndexChart')
      .append('svg')
      .attr('width', width + margin.left + margin.right)
      .attr('height', height + margin.top + margin.bottom);
  
    // Group to hold line + axes
    const g = svg.append('g').attr('transform', `translate(${margin.left},${margin.top})`);
  
    // x-scale from index 0..(n-1)
    const x = d3
      .scaleLinear()
      .domain([0, data.length - 1]) // data is sorted by TTI desc, but we'll just treat them in index order
      .range([0, width]);
  
    // y-scale from 0..150
    const y = d3
      .scaleLinear()
      .domain([0, 10])
      .range([height, 0]);
  
    // line generator
    const line = d3
      .line()
      .x((d, i) => x(i))
      .y((d) => y(d.travel_time_index_mean || 0));
  
    // x-axis
    g.append('g')
      .attr('transform', `translate(0, ${height})`)
      .call(d3.axisBottom(x).ticks(data.length));
  
    // y-axis
    g.append('g').call(d3.axisLeft(y));
  
    // draw the line
    g.append('path')
      .datum(data)
      .attr('fill', 'none')
      .attr('stroke', '#ff6600')
      .attr('stroke-width', 2)
      .attr('d', line);
  
    // optional circles at each data point
    g.selectAll('.dot')
      .data(data)
      .enter()
      .append('circle')
      .attr('class', 'dot')
      .attr('cx', (d, i) => x(i))
      .attr('cy', (d) => y(d.travel_time_index_mean || 0))
      .attr('r', 3)
      .attr('fill', '#ff6600');
  }
  
  function loadDefaultGeoJSON() {
    fetch('/geojson/default_netz_data.geojson')
      .then((response) => response.json())
      .then((data) => {
        if (geoJsonLayer) {
          map.removeLayer(geoJsonLayer);
        }
        geoJsonLayer = L.geoJSON(data, {
          style: { color: '#3388ff', weight: 2 },
          onEachFeature: (feature, layer) => {
            if (feature.properties) {
              let popupContent = `
                <div><strong>Netz Abschnitts ID:</strong> ${
                  feature.properties.netzabschnitts_id || 'N/A'
                }</div>
              `;
  
              layer.on('click', function () {
                const date = document.getElementById('dateInput').value;
                const startTime = document.getElementById('timeInput').value;
                const netzabschnittId = feature.properties.netzabschnitts_id;
  
                // 1) get_cumulative_time -> single value
                fetch('/get_cumulative_time', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    netzabschnitt_id: netzabschnittId,
                    date: date,
                    start_time: startTime,
                  }),
                })
                  .then((res) => res.json())
                  .then((result) => {
                    if (result.error) {
                      console.error('Server error:', result.error);
                      popupContent += `
                        <div><strong>Max Cumulative Time:</strong> Error fetching data</div>
                      `;
                    } else {
                      const cumulativeTime = result.cumulative_time_minutes
                        ? `${result.cumulative_time_minutes} minutes`
                        : 'Data is not available';
                      popupContent += `
                        <div><strong>Max Cumulative Time:</strong> ${cumulativeTime}</div>
                      `;
                    }
                    layer.bindPopup(popupContent).openPopup();
                  })
                  .catch((error) => {
                    console.error('Error fetching cumulative time:', error);
                    alert('Failed to fetch cumulative time data.');
                  });
  
                // 2) get_travel_time_index -> all data, then top 5 in table, line chart for all
                fetch('/get_travel_time_index', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ netzabschnitt_id: netzabschnittId }),
                })
                  .then((res) => res.json())
                  .then((data) => {
                    if (data.error) {
                      console.error('Server error (TTI):', data.error);
                      return;
                    }
                    if (!Array.isArray(data)) {
                      console.error('Expected array but got:', data);
                      return;
                    }
  
                    // top 5 in the table
                    const topFive = data.slice(0, 5); // data is presumably sorted descending
  
                    let html = `
                      <table border="1" style="margin: 10px 0;">
                        <thead>
                          <tr>
                            <th>start_time</th>
                            <th>wochentag</th>
                            <th>cumulative_time_minutes</th>
                            <th>travel_time_index_mean</th>
                            <th>travel_time_index_median</th>
                          </tr>
                        </thead>
                        <tbody>
                    `;
                    topFive.forEach((row) => {
                      html += `
                        <tr>
                          <td>${row.start_time || ''}</td>
                          <td>${row.wochentag || ''}</td>
                          <td>${row.cumulative_time_minutes || ''}</td>
                          <td>${
                            row.travel_time_index_mean
                              ? row.travel_time_index_mean.toFixed(2)
                              : ''
                          }</td>
                          <td>${
                            row.travel_time_index_median
                              ? row.travel_time_index_median.toFixed(2)
                              : ''
                          }</td>
                        </tr>
                      `;
                    });
                    html += '</tbody></table>';
  
                    const tableContainer = document.getElementById('timeIndexTable');
                    if (tableContainer) {
                      tableContainer.innerHTML = html;
                    }
  
                    // Build the line chart with ALL data, not just top 5
                    buildLineChart(data);
                  })
                  .catch((error) => {
                    console.error('Error fetching travel_time_index:', error);
                    alert('Failed to fetch travel time index data.');
                  });
              });
  
              layer.bindPopup(popupContent);
            }
          },
        }).addTo(map);
      })
      .catch((error) => {
        console.error('Error loading default GeoJSON:', error);
        alert('Failed to load default GeoJSON data.');
      });
  }
  
  // Always load the default GeoJSON when the page is loaded
  loadDefaultGeoJSON();
  
  document.addEventListener('DOMContentLoaded', function () {
    const title = 'Welcome to Roadsimulator';
    const container = document.getElementById('title');
    let i = 0;
  
    function typeWriter() {
      if (i < title.length) {
        container.innerHTML += title.charAt(i);
        i++;
        setTimeout(typeWriter, 200);
      } else {
        container.style.borderRight = 'none';
      }
    }
  
    typeWriter();
  });
  