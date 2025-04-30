const map = L.map('map', {center:[51.1657,10.4515],zoom:6,preferCanvas:true});
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            {attribution:'© OpenStreetMap'}).addTo(map);

let baseLayer;      
let metricLayer;    // dynamic layer coloure

/* -------- helpers ----------------------- */
const isoDate  = () => document.getElementById('dateInput'   ).value || null;
const vz       = () => document.getElementById('trafficSelect').value || null;
const metric   = () => document.getElementById('metricSelect' ).value || null;

/* -------- Verlustzeit table  -------- */
function renderVerlustzeit(rows){
  const div = document.getElementById('verlustzeitTable');
  div.innerHTML = '';
  if(!Array.isArray(rows)||!rows.length) return;
  const all = ['buffertime_mean_index','sd_traveltime','velocity_65','verlustzeit_pro_km'];
  const cols = metric() ? [metric()] : all;
  let html='<table border="1"><thead><tr>'+cols.map(c=>`<th>${c}</th>`).join('')+
           '</tr></thead><tbody>';
  rows.forEach(r=>{
    html+='<tr>'+cols.map(c=>`<td>${r[c]??''}</td>`).join('')+'</tr>';
  });
  html+='</tbody></table>';
  div.innerHTML = html;
}

/* -------- coloured metric layer fetcher ------------------------------ */
function refreshMetricLayer(){
  if (!metric()) {               
    if(metricLayer) map.removeLayer(metricLayer);
    return;
  }

  const params = new URLSearchParams({
    metric : metric(),
    date   : isoDate()  || '',
    vz     : vz()       || ''
  });
  fetch(`/metric_geojson?${params.toString()}`)
    .then(r=>r.json())
    .then(gjson=>{
      if(metricLayer) map.removeLayer(metricLayer);
      metricLayer = L.geoJSON(gjson,{
        style:f=>({color:f.properties.color,weight:4,opacity:0.9})
      }).addTo(map);
    })
    .catch(err=>console.error('metric layer fetch error:',err));
}

/* -------- base network ----------------------------------- */
function loadBaseNetwork(){
  fetch('/geojson/joined_netz_data.geojson')
    .then(r=>r.json())
    .then(gjson=>{
      if(baseLayer) map.removeLayer(baseLayer);
      baseLayer = L.geoJSON(gjson,{
        style:f=>({color:f.properties.color||'#3388ff',weight:4,opacity:0.8}),
        onEachFeature:(feat,layer)=>{
          const v65=feat.properties.velocity_65, netz=feat.properties.netzabschnitts_id;
          layer.on('click',()=>{
            let pop=`<div><strong>Netz Abschnitts ID:</strong> ${netz}</div>`;
            if(v65!=null) pop+=`<div><strong>35 %-Speed (NVZ):</strong> ${v65.toFixed(2)} km/h</div>`;
            
            pop += `
              <div style="margin-top:6px">
                <a href="http://127.0.0.1:4295/?netzabschnitt=${netz}"
                   target="_blank"
                   style="color:#005ca9;font-weight:bold;text-decoration:underline">
                  Open in Shiny Dashboard&nbsp;&rarr;
                </a>
              </div>`;

            layer.bindPopup(pop).openPopup();
                        
            renderVerlustzeit([]);
            fetch('/get_verlustzeit',{
              method:'POST',headers:{'Content-Type':'application/json'},
              body:JSON.stringify({netzabschnitt_id:netz,date:isoDate(),verkehrszeit:vz()})
            })
            .then(r=>r.json()).then(rows=>renderVerlustzeit(rows));
          });
        }
      }).addTo(map);
    });
}

loadBaseNetwork();

function refreshMetricLayer(){
  if(metricLayer){                 
    map.removeLayer(metricLayer);
    metricLayer = null;
  }

  if(!metric()){                   
    return;
  }

  const p = new URLSearchParams({
    metric : metric(),
    date   : isoDate() || '',
    vz     : vz()      || ''
  });

  fetch('/metric_geojson?'+p.toString())
    .then(r=>r.json())
    .then(gjson=>{
      if(!gjson.features || !gjson.features.length){
        alert('Keine Daten für die gewählte Kombination gefunden.');
        return;
      }
      metricLayer = L.geoJSON(gjson,{
        style:f=>({ color:f.properties.color, weight:4, opacity:0.9 })
      }).addTo(map);
    })
    .catch(e=>{
      console.error('metric layer fetch error:',e);
      alert('Fehler beim Laden der Kennzahl-Karte.');
    });
}


/* -------- headline  ---------------------------------- */
document.addEventListener('DOMContentLoaded',()=>{
  document.getElementById('btnMetricRefresh')
          .addEventListener('click', refreshMetricLayer);
  const t='Welcome to Roadsimulator', el=document.getElementById('title'); let i=0;
  (function tw(){ if(i<t.length){el.innerHTML+=t[i++];setTimeout(tw,200);}else el.style.borderRight='none';})();
});
