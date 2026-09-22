/* Screen definitions and bootstrap for the ParkLife design mockup. */

const params = new URLSearchParams(location.search);
const screen = params.get('screen') || 'ipad-bookings';

const map = CATALOG.maps.find(m => m.id === 'nl-zandheuvel');
const world = generateMap(map);
const park = buildDemoPark(world, map);
park.hot = { x: map.entranceX + 9, y: map.entranceY - 30 };   // the pool, for the crowding overlay

const baseState = {
  cash: 41_250_00 * 10,
  netWorth: 268_400_00,
  debt: 0,
  profit7: 18_420_00,
  revenue30: 96_750_00,
  guests: 184,
  occupancy: 73,
  rating: 3.8,
  speed: 2,
  date: 'Fri 12 June, Year 1 — 16:20',
  weather: 'Partly cloudy',
  weatherIcon: '⛅️',
  temp: 21,
  arrivals: 6,
  departures: 4,
  dirty: 3,
  profitSeries: [-1200, -800, -300, 200, 900, 1400, 1100, 1800, 2400, 2100, 2800, 3300,
                 3050, 3600, 4100, 3800, 4400, 4900, 4700, 5200, 5800, 5500, 6100, 6600,
                 6300, 6900, 7400, 7100, 7800, 8200],
  forecast: [2100, 2400, 3900, 4200, 3100, 1800, 1700, 2000, 2300, 4100, 4400, 3000,
             1900, 1800, 2200, 2500, 4300, 4600, 3200, 2000, 1900],
  occupancyGrid: [
    [0.62, 0.58, 0.55, 0.60, 0.88, 0.92, 0.74],
    [0.55, 0.52, 0.50, 0.58, 0.85, 0.90, 0.70],
    [0.68, 0.64, 0.62, 0.70, 0.95, 0.98, 0.82],
    [0.72, 0.70, 0.68, 0.75, 1.00, 1.00, 0.88]
  ],
  revenueBreakdown: [
    ['Accommodation', '€3,214'], ['Food & drink', '€742'],
    ['Shops', '€388'], ['Activities', '€196']
  ],
  arrivalsList: [
    { unit: 'Comfort Cottage (6) #14', party: '2 adults, 3 children', nights: 4, status: 'Arriving', price: '€624' },
    { unit: 'Basic Cottage (4) #19', party: '4 adults', nights: 2, status: 'Paid', price: '€178' },
    { unit: 'Comfort Cottage (4) #11', party: '2 adults, 1 child', nights: 7, status: 'Paid', price: '€826' },
    { unit: 'Comfort Cottage (6) #22', party: '3 adults, 2 children', nights: 3, status: 'Paid', price: '€468' }
  ],
  ratings: { overall: 0.71, cleanliness: 0.83, service: 0.64, safety: 0.88, sustainability: 0.57 },
  objectives: [
    { title: 'Hold 70% occupancy for a month', progress: 1.0, done: false, detail: 'Held for 21 of 30 days' },
    { title: 'Keep guest satisfaction above 75%', progress: 0.96, done: false, detail: 'Held for 14 of 30 days' },
    { title: 'Reach €500,000 of annual revenue', progress: 0.42, done: false, detail: '€209,400 so far' }
  ],
  thoughts: [
    { good: true, text: 'The swimming pool is fantastic.', count: 42 },
    { good: false, text: 'Our cottage is a long way from the pool.', count: 17 },
    { good: true, text: 'What a beautiful park this is.', count: 15 },
    { good: false, text: 'The queue is far too long.', count: 9 },
    { good: true, text: 'That was good value.', count: 8 },
    { good: false, text: "There isn't enough for the children to do.", count: 4 }
  ],
  reviews: [
    { stars: '★★★★☆', score: '4.2', body: 'The swimming pool is fantastic. Our cottage is a long way from the pool.' },
    { stars: '★★★★★', score: '4.8', body: 'What a beautiful park this is. That was good value.' },
    { stars: '★★★☆☆', score: '2.9', body: 'We waited ages to check in. The food was disappointing.' }
  ],
  paths: [
    { name: 'Footpath', sub: '€42 per tile', on: true },
    { name: 'Paved Plaza', sub: '€68 per tile' },
    { name: 'Cycle Path', sub: 'Needs research: Cycle Paths' }
  ],
  accommodation: CATALOG.buildings
    .filter(b => b.accommodation && !b.researchID)
    .map(b => ({
      name: ({ tinyHouseBasic2: 'Tiny House', cottageBasic4: 'Basic Cottage (4)',
               cottageComfort4: 'Comfort Cottage (4)', cottageComfort6: 'Comfort Cottage (6)',
               cottagePremium6: 'Premium Cottage (6)' })[b.nameKey.split('.')[1]] || b.id,
      sub: `€${(b.constructionCost / 100).toLocaleString('en-GB')} · ` +
           `${b.footprintWidth}×${b.footprintHeight} · sleeps ${b.accommodation.capacity} · ` +
           b.accommodation.tier
    })),
  food: CATALOG.buildings
    .filter(b => b.category === 'food' && !b.researchID)
    .map(b => ({
      name: ({ snackBar: 'Snack Bar', cafeTerrace: 'Café & Terrace',
               restaurantFamily: 'Family Restaurant' })[b.nameKey.split('.')[1]] || b.id,
      sub: `€${(b.constructionCost / 100).toLocaleString('en-GB')} · ` +
           `${b.footprintWidth}×${b.footprintHeight} · €${(b.facility.basePrice / 100).toFixed(2)}`
    }))
};

const SCREENS = {
  'ipad-bookings': {
    panel: 'bookings', nav: 'Bookings', overlay: null, people: 260,
    zoom: 0.52, centre: { x: map.entranceX, y: map.entranceY - 23 }, anchor: 0.50,
    inspector: {
      title: 'Comfort Cottage (6)', sub: 'Occupied',
      meters: [['Condition', 0.97, false], ['Cleanliness', 0.72, false]],
      rows: [['Sleeps', '6'], ['Nightly rate', '€168'], ['Nights sold', '94']]
    },
    build: null
  },
  'ipad-park': {
    panel: 'park', nav: 'Park', overlay: 'congestion', people: 280, legend: true,
    zoom: 0.50, centre: { x: map.entranceX + 1, y: map.entranceY - 24 }, anchor: 0.48,
    inspector: null, build: null
  },
  'iphone-build': {
    sheet: null, nav: 'Build', overlay: null, people: 150,
    zoom: 0.62, centre: { x: map.entranceX - 1, y: map.entranceY - 20 }, anchor: 0.44,
    inspector: null,
    build: { name: 'Comfort Cottage (4)', demolish: false },
    preview: { x: map.entranceX - 4, y: map.entranceY - 30, w: 3, h: 3, valid: true }
  },
  'iphone-finances': {
    sheet: 'finances', nav: 'Finances', overlay: null, people: 140,
    zoom: 0.44, centre: { x: map.entranceX, y: map.entranceY - 19 }, anchor: 0.27,
    inspector: null, build: null
  },
  'iphone-guest': {
    sheet: null, nav: null, overlay: 'scenery', people: 190, legend: true,
    zoom: 0.72, centre: { x: map.entranceX - 3, y: map.entranceY - 21 }, anchor: 0.42,
    inspector: {
      title: 'Marit, 34', sub: 'Walking to their cottage',
      meters: [['Happiness', 0.81, false], ['Hunger', 0.34, true],
               ['Thirst', 0.52, true], ['Tiredness', 0.41, true]],
      rows: [],
      thought: '👍 The swimming pool is fantastic.'
    },
    build: null
  }
};

function renderScreen() {
  const config = SCREENS[screen] || SCREENS['ipad-bookings'];
  const state = baseState;

  const compact = window.innerWidth < 520;
  document.body.classList.toggle('compact', compact);
  renderHUD(state, compact);
  renderNav(config.nav, 3);

  const canvas = document.getElementById('park');
  drawWorld(canvas, world, park, {
    zoom: config.zoom,
    centre: config.centre,
    verticalAnchor: config.anchor,
    overlay: config.overlay,
    people: config.people,
    preview: config.preview || null
  });

  const legend = document.getElementById('legend');
  if (config.legend) {
    const entries = config.overlay === 'congestion'
      ? [['Quiet', hsv(0.08, 0.75, 0.45)], ['Busy', hsv(0.04, 0.75, 0.65)], ['Crowded', hsv(0.0, 0.75, 0.85)]]
      : [['Built up', hsv(0.33, 0.35, 0.50)], ['Green', hsv(0.33, 0.55, 0.80)]];
    legend.classList.add('show');
    legend.innerHTML = `<div style="font-weight:600;margin-bottom:2px">${
      config.overlay === 'congestion' ? 'Crowding' : 'Scenery'}</div>` +
      entries.map(([l, c]) => `<div class="sw"><i style="background:${rgbStr(c)}"></i>${l}</div>`).join('');
  } else {
    legend.classList.remove('show');
  }

  const inspector = document.getElementById('inspector');
  if (config.inspector) {
    const i = config.inspector;
    inspector.style.display = 'flex';
    inspector.innerHTML = `<h3>${i.title}</h3><div class="sub">${i.sub}</div>` +
      i.meters.map(([l, v, inv]) => meter(l, v, inv)).join('') +
      i.rows.map(([a, b]) => `<div class="kv"><span>${a}</span><span>${b}</span></div>`).join('') +
      (i.thought ? `<div class="sub" style="color:var(--good)">${i.thought}</div>` : '');
  } else {
    inspector.style.display = 'none';
  }

  const buildbar = document.getElementById('buildbar');
  if (config.build) {
    buildbar.style.display = 'flex';
    buildbar.innerHTML = `<div class="name">${config.build.name}</div>` +
      `<div style="flex:1"></div><div class="pill">⟳ Rotate</div><div class="pill">↩︎</div>` +
      `<div class="pill">↪︎</div><div class="pill primary">✕</div>`;
  } else {
    buildbar.style.display = 'none';
  }

  const panel = document.getElementById('panel');
  if (config.panel) {
    const built = PANELS[config.panel](state);
    panel.classList.add('show');
    panel.innerHTML = `<div class="panel-head">${built.title}</div><div class="panel-body">${built.body}</div>`;
  } else {
    panel.classList.remove('show');
  }

  const sheet = document.getElementById('sheet');
  if (config.sheet) {
    const built = PANELS[config.sheet](state);
    sheet.classList.add('show');
    sheet.innerHTML = `<div class="grab"></div><div class="panel-head" style="justify-content:center">${built.title}</div>` +
      `<div class="panel-body">${built.body}</div>`;
  } else {
    sheet.classList.remove('show');
  }

  document.body.dataset.ready = 'true';
}

renderScreen();
window.addEventListener('resize', renderScreen);
