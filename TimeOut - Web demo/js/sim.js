/* TimeOut web demo — simulated sports feed, live stats, fair odds and prediction markets.
 *
 * Every league runs on rolling 20-minute slots. Each game lasts 12 real minutes (sped up for the demo),
 * and every score, stat and price is a pure function of the game ID and the (demo) clock, so the same
 * game looks the same on every refresh and can be graded at any time.
 */
(function (TO) {
  'use strict';
  const MIN = TO.MIN;
  const SLOT = 20 * MIN;
  const DURATION = 12 * MIN;
  const STEP = 5000;
  const STEPS = DURATION / STEP; // 144
  const ODDS_BUCKET_LIVE = 15000;
  const ODDS_BUCKET_PRE = 2 * MIN;

  const SPORTS = {
    football: { periods: 4, periodMin: 15, marginSigma: 13.5, totalSigma: 10, perTeam: 21.6, homeEdge: 1.5, spread: 'dynamic', spreadLabel: 'Spread', discrete: false, unit: 'pts' },
    basketball: { periods: 4, periodMin: 12, marginSigma: 12, totalSigma: 15, perTeam: 111, homeEdge: 2.5, spread: 'dynamic', spreadLabel: 'Spread', discrete: false, unit: 'pts' },
    baseball: { periods: 9, marginSigma: 4.2, totalSigma: 3.2, perTeam: 4.3, homeEdge: 0.25, spread: 'fixed', spreadLabel: 'Run line', discrete: true, unit: 'runs' },
    hockey: { periods: 3, periodMin: 20, marginSigma: 2.4, totalSigma: 2.2, perTeam: 3.0, homeEdge: 0.2, spread: 'fixed', spreadLabel: 'Puck line', discrete: true, unit: 'goals' },
    soccer: { periods: 2, marginSigma: 1.6, totalSigma: 1.6, perTeam: 1.35, homeEdge: 0.3, spread: null, draw: true, discrete: true, unit: 'goals' },
  };

  const t = (abbr, name, city, color) => ({ abbr, name, city, color });
  const LEAGUES = {
    nfl: {
      id: 'nfl', title: 'NFL', short: 'NFL', sport: 'football', offset: 0, stagger: 4 * MIN, perSlot: 2, gp: 4,
      teams: [t('KC', 'Chiefs', 'Kansas City', '#E31837'), t('BUF', 'Bills', 'Buffalo', '#00338D'), t('PHI', 'Eagles', 'Philadelphia', '#004C54'), t('DAL', 'Cowboys', 'Dallas', '#003594'), t('SF', '49ers', 'San Francisco', '#AA0000'), t('GB', 'Packers', 'Green Bay', '#203731'), t('BAL', 'Ravens', 'Baltimore', '#241773'), t('DET', 'Lions', 'Detroit', '#0076B6'), t('MIA', 'Dolphins', 'Miami', '#008E97'), t('CIN', 'Bengals', 'Cincinnati', '#FB4F14'), t('LAR', 'Rams', 'Los Angeles', '#003594'), t('NYJ', 'Jets', 'New York', '#125740')],
    },
    ncaaf: {
      id: 'ncaaf', title: 'College Football', short: 'NCAAF', sport: 'football', offset: 15 * MIN, stagger: 3 * MIN, perSlot: 2, gp: 5,
      teams: [t('BYU', 'Cougars', 'BYU', '#002E5D'), t('UTAH', 'Utes', 'Utah', '#CC0000'), t('ALA', 'Crimson Tide', 'Alabama', '#9E1B32'), t('UGA', 'Bulldogs', 'Georgia', '#BA0C2F'), t('OSU', 'Buckeyes', 'Ohio State', '#BB0000'), t('MICH', 'Wolverines', 'Michigan', '#00274C'), t('TEX', 'Longhorns', 'Texas', '#BF5700'), t('ORE', 'Ducks', 'Oregon', '#154733'), t('USC', 'Trojans', 'USC', '#990000'), t('ND', 'Fighting Irish', 'Notre Dame', '#0C2340')],
    },
    nba: {
      id: 'nba', title: 'NBA', short: 'NBA', sport: 'basketball', offset: 3 * MIN, stagger: 4 * MIN, perSlot: 2, gp: 12,
      teams: [t('BOS', 'Celtics', 'Boston', '#007A33'), t('LAL', 'Lakers', 'Los Angeles', '#552583'), t('GSW', 'Warriors', 'Golden State', '#1D428A'), t('DEN', 'Nuggets', 'Denver', '#0E2240'), t('MIL', 'Bucks', 'Milwaukee', '#00471B'), t('PHX', 'Suns', 'Phoenix', '#1D1160'), t('MIA', 'Heat', 'Miami', '#98002E'), t('NYK', 'Knicks', 'New York', '#F58426'), t('DAL', 'Mavericks', 'Dallas', '#00538C'), t('OKC', 'Thunder', 'Oklahoma City', '#007AC1'), t('UTA', 'Jazz', 'Utah', '#4B2A8E'), t('MIN', 'Timberwolves', 'Minnesota', '#236192')],
    },
    mlb: {
      id: 'mlb', title: 'MLB', short: 'MLB', sport: 'baseball', offset: 6 * MIN, stagger: 4 * MIN, perSlot: 2, gp: 158,
      teams: [t('NYY', 'Yankees', 'New York', '#0C2340'), t('LAD', 'Dodgers', 'Los Angeles', '#005A9C'), t('ATL', 'Braves', 'Atlanta', '#CE1141'), t('HOU', 'Astros', 'Houston', '#EB6E1F'), t('CHC', 'Cubs', 'Chicago', '#0E3386'), t('BOS', 'Red Sox', 'Boston', '#BD3039'), t('SEA', 'Mariners', 'Seattle', '#005C5C'), t('SD', 'Padres', 'San Diego', '#7A5C3A'), t('PHI', 'Phillies', 'Philadelphia', '#E81828'), t('TOR', 'Blue Jays', 'Toronto', '#134A8E')],
    },
    nhl: {
      id: 'nhl', title: 'NHL', short: 'NHL', sport: 'hockey', offset: 9 * MIN, stagger: 4 * MIN, perSlot: 2, gp: 8,
      teams: [t('COL', 'Avalanche', 'Colorado', '#6F263D'), t('VGK', 'Golden Knights', 'Vegas', '#8C7650'), t('EDM', 'Oilers', 'Edmonton', '#FF4C00'), t('TOR', 'Maple Leafs', 'Toronto', '#00205B'), t('BOS', 'Bruins', 'Boston', '#A87D00'), t('NYR', 'Rangers', 'New York', '#0038A8'), t('TBL', 'Lightning', 'Tampa Bay', '#002868'), t('FLA', 'Panthers', 'Florida', '#C8102E'), t('DAL', 'Stars', 'Dallas', '#006847'), t('CAR', 'Hurricanes', 'Carolina', '#CC0000')],
    },
    epl: {
      id: 'epl', title: 'Premier League', short: 'EPL', sport: 'soccer', offset: 12 * MIN, stagger: 4 * MIN, perSlot: 2, gp: 6,
      teams: [t('ARS', 'Arsenal', 'London', '#EF0107'), t('MCI', 'Man City', 'Manchester', '#4A90C8'), t('LIV', 'Liverpool', 'Liverpool', '#C8102E'), t('CHE', 'Chelsea', 'London', '#034694'), t('MUN', 'Man United', 'Manchester', '#DA291C'), t('TOT', 'Tottenham', 'London', '#132257'), t('NEW', 'Newcastle', 'Newcastle', '#3A3A3A'), t('AVL', 'Aston Villa', 'Birmingham', '#670E36')],
    },
    sim: {
      id: 'sim', title: 'Sim League', short: 'SIM', sport: 'basketball', offset: 1 * MIN, stagger: 6 * MIN, perSlot: 3, gp: 20, simulated: true,
      teams: [t('NCV', 'Volts', 'Neon City', '#00B8D4'), t('HBK', 'Kraken', 'Harbor', '#1E5EB8'), t('DSC', 'Scorpions', 'Desert', '#E09A00'), t('SMY', 'Yetis', 'Summit', '#7E8CC7'), t('BYG', 'Gators', 'Bayou', '#2E7D32'), t('MTC', 'Comets', 'Metro', '#D93A3A'), t('PRS', 'Storm', 'Prairie', '#8E3FB5'), t('IBA', 'Anchors', 'Iron Bay', '#4F6572')],
    },
  };
  const REAL_LEAGUES = ['nfl', 'ncaaf', 'nba', 'mlb', 'nhl', 'epl'];
  const LEAGUE_ORDER = ['nfl', 'ncaaf', 'nba', 'mlb', 'nhl', 'epl', 'sim'];

  const strength = (league, team) => 0.9 * TO.unit(`str-${league}-${team.abbr}`);

  function record(league, team) {
    const L = LEAGUES[league];
    const s = strength(league, team);
    const gp = L.gp;
    if (L.sport === 'soccer') {
      const w = TO.clamp(Math.round(gp * (0.42 + 0.3 * s) + TO.unit(`rw-${team.abbr}`)), 0, gp);
      const d = TO.clamp(Math.round((gp - w) * 0.35), 0, gp - w);
      return `${w}-${d}-${gp - w - d}`;
    }
    const w = TO.clamp(Math.round(gp * (0.5 + 0.3 * s) + 1.2 * TO.unit(`rw-${league}-${team.abbr}`)), 0, gp);
    return `${w}-${gp - w}`;
  }

  function form(league, team) {
    const s = strength(league, team);
    return Array.from({ length: 5 }, (_, i) => (TO.u01(`form-${league}-${team.abbr}-${i}`) < 0.5 + 0.3 * s ? 'W' : 'L'));
  }

  // ---------- Overrides set by the tester panel ----------
  const overrides = () => TO.store.get('timeout.gameOverrides', {});
  const setOverride = (id, patch) => {
    const all = overrides();
    all[id] = Object.assign({}, all[id], patch);
    TO.store.set('timeout.gameOverrides', all);
  };

  // ---------- Scoring timeline ----------
  const timelines = new Map();

  function scoringRoll(sport, r, r2, mult, step) {
    switch (sport) {
      case 'football': {
        if (r < 0.0165 * mult) {
          const pts = r2 < 0.9 ? 7 : r2 < 0.95 ? 6 : 8;
          const yds = 1 + Math.floor(r2 * 1000) % 45;
          return { pts, kind: (Math.floor(r2 * 100) % 2 ? `${yds}-yd TD pass` : `${yds}-yd TD run`) + (pts === 6 ? ' (missed PAT)' : pts === 8 ? ' + 2-pt conversion' : '') };
        }
        if (r < (0.0165 + 0.0115) * mult) return { pts: 3, kind: `${25 + (Math.floor(r2 * 1000) % 30)}-yd field goal` };
        return null;
      }
      case 'basketball': {
        if (r < 0.335 * mult) {
          const three = r2 < 0.3;
          const kinds = three ? ['3-pointer', 'Corner three', 'Step-back three'] : ['Layup', 'Jumper', 'Dunk', 'Floater', 'Free throws (2)'];
          return { pts: three ? 3 : 2, kind: kinds[Math.floor(r2 * 1000) % kinds.length] };
        }
        return null;
      }
      case 'baseball': {
        if (r < 0.042 * mult) {
          const runs = r2 < 0.68 ? 1 : r2 < 0.88 ? 2 : r2 < 0.97 ? 3 : 4;
          const kinds = { 1: ['RBI single', 'Solo home run', 'Sacrifice fly', 'RBI double'], 2: ['2-run double', '2-run homer'], 3: ['3-run homer', 'Bases-clearing double'], 4: ['Grand slam'] }[runs];
          return { pts: runs, kind: kinds[Math.floor(r2 * 1000) % kinds.length] };
        }
        return null;
      }
      case 'hockey': {
        if (r < 0.021 * mult) {
          const kinds = ['Even-strength goal', 'Power-play goal', 'Wrist shot goal', 'Rebound goal', 'Breakaway goal'];
          return { pts: 1, kind: kinds[Math.floor(r2 * 1000) % kinds.length] };
        }
        return null;
      }
      case 'soccer': {
        if (r < 0.0095 * mult) {
          const kinds = ['Goal (header)', 'Goal (left foot)', 'Goal (right foot)', 'Penalty goal', 'Goal (volley)'];
          return { pts: 1, kind: kinds[Math.floor(r2 * 1000) % kinds.length] };
        }
        return null;
      }
    }
    return null;
  }

  function timeline(game) {
    if (timelines.has(game.id)) return timelines.get(game.id);
    const L = LEAGUES[game.league];
    const S = SPORTS[L.sport];
    const rand = TO.rng(`game-${game.id}`);
    const d = strength(game.league, game.home) - strength(game.league, game.away);
    const homeBoost = S.homeEdge / S.perTeam;
    const multHome = Math.max(0.3, 1 + 0.06 * d + homeBoost);
    const multAway = Math.max(0.3, 1 - 0.06 * d);
    const events = [];
    let h = 0, a = 0;
    for (let step = 0; step < STEPS; step++) {
      for (const side of ['away', 'home']) {
        const r = rand(), r2 = rand();
        if (L.sport === 'baseball') {
          const half = Math.floor(step / (STEPS / 18));
          if ((half % 2 === 0) !== (side === 'away')) continue;
        }
        const ev = scoringRoll(L.sport, r, r2, side === 'home' ? multHome : multAway, step);
        if (ev) {
          if (side === 'home') h += ev.pts; else a += ev.pts;
          events.push({ step, side, pts: ev.pts, kind: ev.kind });
        }
      }
    }
    let extra = null;
    if (h === a && !S.draw) {
      const r = rand();
      const side = r < 0.5 + 0.1 * d ? 'home' : 'away';
      let pts = 1, kind = 'Overtime winner', lose = 0, label = 'OT';
      if (L.sport === 'football') { pts = rand() < 0.6 ? 3 : 6; kind = pts === 3 ? 'Overtime field goal' : 'Overtime touchdown'; }
      if (L.sport === 'basketball') { pts = 4 + Math.floor(rand() * 7); lose = Math.max(0, pts - 1 - Math.floor(rand() * 5)); kind = 'Won in overtime'; }
      if (L.sport === 'baseball') { kind = side === 'home' ? 'Walk-off single in the 10th' : 'Go-ahead run in the 10th'; label = '10'; }
      if (L.sport === 'hockey') { kind = rand() < 0.5 ? 'Overtime goal' : 'Shootout winner'; }
      extra = { side, pts, lose, kind, label };
      if (side === 'home') { h += pts; a += lose; } else { a += pts; h += lose; }
    }
    const tl = { events, extra, finalHome: h, finalAway: a };
    timelines.set(game.id, tl);
    return tl;
  }

  // ---------- Clock text ----------
  function clockText(sport, prog) {
    const S = SPORTS[sport];
    prog = TO.clamp(prog, 0, 0.9999);
    if (sport === 'baseball') {
      const half = Math.floor(prog * 18);
      return `${half % 2 === 0 ? 'Top' : 'Bot'} ${TO.ordinal(Math.floor(half / 2) + 1)}`;
    }
    if (sport === 'soccer') {
      const minute = Math.floor(prog * 90) + 1;
      return `${minute}'`;
    }
    const x = prog * S.periods;
    const per = Math.floor(x);
    const secsLeft = Math.round((1 - (x - per)) * S.periodMin * 60);
    const clock = `${Math.floor(secsLeft / 60)}:${String(secsLeft % 60).padStart(2, '0')}`;
    if (sport === 'hockey') return `${TO.ordinal(per + 1)} · ${clock}`;
    return `Q${per + 1} · ${clock}`;
  }

  // ---------- Games ----------
  function teamsFor(league, slot) {
    const L = LEAGUES[league];
    const order = TO.shuffle(L.teams.map((_, i) => i), TO.rng(`slot-${league}-${slot}`));
    return order;
  }

  function game(id, now = TO.now()) {
    const [league, slotStr, idxStr] = id.split('-');
    const L = LEAGUES[league];
    if (!L) return null;
    const slot = Number(slotStr), idx = Number(idxStr);
    const order = teamsFor(league, slot);
    const home = L.teams[order[idx * 2]];
    const away = L.teams[order[idx * 2 + 1]];
    const start = slot * SLOT + L.offset + idx * L.stagger;
    const ov = overrides()[id] || {};
    const S = SPORTS[L.sport];
    const g = {
      id, league, sport: L.sport, slot, idx, start, end: start + DURATION, home, away,
      state: 'scheduled', homeScore: 0, awayScore: 0, progress: 0, statusText: '', clock: '', ot: null,
      simulated: !!L.simulated,
    };
    const elapsed = now - start + (ov.warp || 0);
    const naturalPpd = !L.simulated && TO.hash(`ppd-${id}`) % 29 === 0;
    if ((naturalPpd && now >= start - 8 * MIN) || ov.state === 'postponed') {
      g.state = 'postponed';
      g.statusText = 'Postponed';
      return g;
    }
    if (elapsed < 0) {
      g.statusText = TO.fmtTime(start);
      return g;
    }
    const tl = timeline(g);
    if (elapsed >= DURATION) {
      g.state = 'final';
      g.progress = 1;
      g.homeScore = tl.finalHome;
      g.awayScore = tl.finalAway;
      g.ot = tl.extra;
      g.statusText = tl.extra ? `Final/${tl.extra.label}` : 'Final';
      g.endedAt = start + DURATION - (ov.warp || 0);
      return g;
    }
    const steps = Math.floor(elapsed / STEP);
    let h = 0, a = 0;
    for (const ev of tl.events) {
      if (ev.step >= steps) break;
      if (ev.side === 'home') h += ev.pts; else a += ev.pts;
    }
    g.state = 'live';
    g.homeScore = h;
    g.awayScore = a;
    g.progress = elapsed / DURATION;
    g.clock = clockText(L.sport, g.progress);
    g.statusText = g.clock;
    g.stepsPlayed = steps;
    return g;
  }

  /** Scoring plays so far, newest first. */
  function plays(g) {
    if (g.state !== 'live' && g.state !== 'final') return [];
    const tl = timeline(g);
    const steps = g.state === 'final' ? STEPS : g.stepsPlayed;
    let h = 0, a = 0;
    const list = [];
    for (const ev of tl.events) {
      if (ev.step >= steps) break;
      if (ev.side === 'home') h += ev.pts; else a += ev.pts;
      list.push({ team: ev.side === 'home' ? g.home : g.away, kind: ev.kind, clock: clockText(g.sport, ev.step / STEPS), score: `${g.away.abbr} ${a} – ${g.home.abbr} ${h}` });
    }
    if (g.state === 'final' && tl.extra) {
      list.push({ team: tl.extra.side === 'home' ? g.home : g.away, kind: tl.extra.kind, clock: tl.extra.label === '10' ? 'Top 10th' : 'OT', score: `${g.away.abbr} ${g.awayScore} – ${g.home.abbr} ${g.homeScore}` });
    }
    return list.reverse();
  }

  /** Live team stats for the game page and open-bet cards. */
  function stats(g) {
    if (g.state !== 'live' && g.state !== 'final') return [];
    const p = g.progress;
    const u = (k) => TO.unit(`${g.id}-${k}`);
    const u01 = (k) => TO.u01(`${g.id}-${k}`);
    const A = g.awayScore, H = g.homeScore;
    const row = (label, a, h, opts = {}) => ({ label, a, h, ...opts });
    switch (g.sport) {
      case 'football': {
        const yd = (pts, k) => Math.round(p * (250 + 14 * pts) * (1 + 0.12 * u(k)));
        const ya = yd(A, 'ya'), yh = yd(H, 'yh');
        const sa = 0.55 + 0.15 * u('pa'), sh = 0.55 + 0.15 * u('ph');
        const top = Math.round(50 + 8 * u('top'));
        return [
          row('Total yards', ya, yh),
          row('Passing yards', Math.round(ya * sa), Math.round(yh * sh)),
          row('Rushing yards', ya - Math.round(ya * sa), yh - Math.round(yh * sh)),
          row('First downs', Math.round(ya / 17), Math.round(yh / 17)),
          row('Turnovers', Math.floor(p * 2.4 * u01('toa')), Math.floor(p * 2.4 * u01('toh')), { lowerBetter: true }),
          row('Possession', top, 100 - top, { suffix: '%' }),
        ];
      }
      case 'basketball': {
        const fg = (pts, opp, k) => Math.round(TO.clamp(45 + 4 * u(k) + (pts - opp) / 8, 34, 58));
        return [
          row('Field goal %', fg(A, H, 'fga'), fg(H, A, 'fgh'), { suffix: '%' }),
          row('3-pointers made', Math.round(p * 12 * (1 + 0.25 * u('3a'))), Math.round(p * 12 * (1 + 0.25 * u('3h')))),
          row('Rebounds', Math.round(p * 44 * (1 + 0.1 * u('ra'))), Math.round(p * 44 * (1 + 0.1 * u('rh')))),
          row('Assists', Math.round(p * 25 * (1 + 0.15 * u('aa'))), Math.round(p * 25 * (1 + 0.15 * u('ah')))),
          row('Turnovers', Math.round(p * 13 * (1 + 0.25 * u('ta'))), Math.round(p * 13 * (1 + 0.25 * u('th'))), { lowerBetter: true }),
        ];
      }
      case 'baseball': {
        const hits = (r, k) => Math.max(r, Math.round(p * 7.5 * (1 + 0.25 * u(k)) + r * 0.5));
        return [
          row('Hits', hits(A, 'ha'), hits(H, 'hh')),
          row('Home runs', Math.min(A, Math.floor(p * 1.6 * u01('hra') + A * 0.2)), Math.min(H, Math.floor(p * 1.6 * u01('hrh') + H * 0.2))),
          row('Strikeouts (pitching)', Math.round(p * 9 * (1 + 0.2 * u('ka'))), Math.round(p * 9 * (1 + 0.2 * u('kh')))),
          row('Errors', Math.floor(p * 1.6 * u01('ea')), Math.floor(p * 1.6 * u01('eh')), { lowerBetter: true }),
          row('Left on base', Math.round(p * 6.5 * (1 + 0.3 * u('la'))), Math.round(p * 6.5 * (1 + 0.3 * u('lh'))), { lowerBetter: true }),
        ];
      }
      case 'hockey': {
        const sog = (gl, k) => Math.max(gl * 3, Math.round(p * 30 * (1 + 0.15 * u(k))));
        const fo = Math.round(50 + 6 * u('fo'));
        const ppa = Math.floor(p * 4 * u01('ppa')), pph = Math.floor(p * 4 * u01('pph'));
        return [
          row('Shots on goal', sog(A, 'sa'), sog(H, 'sh')),
          row('Power plays', ppa, pph, { text: [`${Math.min(ppa, Math.floor(A / 2))}/${ppa}`, `${Math.min(pph, Math.floor(H / 2))}/${pph}`] }),
          row('Faceoff %', fo, 100 - fo, { suffix: '%' }),
          row('Hits', Math.round(p * 24 * (1 + 0.2 * u('hia'))), Math.round(p * 24 * (1 + 0.2 * u('hih')))),
          row('Blocked shots', Math.round(p * 14 * (1 + 0.2 * u('ba'))), Math.round(p * 14 * (1 + 0.2 * u('bh')))),
        ];
      }
      case 'soccer': {
        const pos = Math.round(50 + 10 * u('pos'));
        const sh = (gl, k) => Math.max(gl, Math.round(p * 13 * (1 + 0.25 * u(k))));
        const sa = sh(A, 'sa'), shh = sh(H, 'sh');
        return [
          row('Possession', pos, 100 - pos, { suffix: '%' }),
          row('Shots', sa, shh),
          row('Shots on target', Math.max(A, Math.round(sa * 0.38)), Math.max(H, Math.round(shh * 0.38))),
          row('Corners', Math.round(p * 5.5 * (1 + 0.3 * u('ca'))), Math.round(p * 5.5 * (1 + 0.3 * u('ch')))),
          row('Fouls', Math.round(p * 11 * (1 + 0.2 * u('fa'))), Math.round(p * 11 * (1 + 0.2 * u('fh'))), { lowerBetter: true }),
          row('Yellow cards', Math.floor(p * 2.4 * u01('ya')), Math.floor(p * 2.4 * u01('yh')), { lowerBetter: true }),
        ];
      }
    }
    return [];
  }

  /** Season research for the game page. */
  function research(g) {
    const S = SPORTS[g.sport];
    const side = (team) => {
      const s = strength(g.league, team);
      return {
        team,
        record: record(g.league, team),
        form: form(g.league, team),
        pf: +(S.perTeam * (1 + 0.1 * s)).toFixed(1),
        pa: +(S.perTeam * (1 - 0.1 * s + 0.03 * TO.unit(`pa-${team.abbr}`))).toFixed(1),
      };
    };
    const hw = TO.u01(`h2h-${g.league}-${[g.home.abbr, g.away.abbr].sort().join('')}`) < 0.5;
    const winner = hw ? g.home : g.away, loser = hw ? g.away : g.home;
    const w = Math.round(S.perTeam * (1.05 + 0.2 * TO.u01(`h2hw-${g.id}`)));
    const l = Math.max(0, Math.round(w - 1 - S.marginSigma * 0.6 * TO.u01(`h2hl-${g.id}`)));
    return { away: side(g.away), home: side(g.home), lastMeeting: `${winner.abbr} ${w}, ${loser.abbr} ${l}`, unit: S.unit };
  }

  /** Games on the board right now: recent finals, live games and the next ~45 minutes. */
  function board(now = TO.now(), { offDay = false, leagues = LEAGUE_ORDER } = {}) {
    const list = [];
    for (const league of leagues) {
      if (offDay && league !== 'sim') continue;
      const L = LEAGUES[league];
      const base = Math.floor((now - L.offset) / SLOT);
      for (let slot = base - 1; slot <= base + 2; slot++) {
        for (let i = 0; i < L.perSlot; i++) {
          const g = game(`${league}-${slot}-${i}`, now);
          if (g.state === 'scheduled' && g.start - now > 45 * MIN) continue;
          if (g.state === 'final' && now - (g.endedAt || g.end) > 8 * MIN) continue;
          if (g.state === 'postponed' && now > g.end) continue;
          list.push(g);
        }
      }
    }
    const rank = { live: 0, scheduled: 1, postponed: 2, final: 3 };
    return list.sort((a, b) => rank[a.state] - rank[b.state] || a.start - b.start);
  }

  // ---------- Odds ----------
  const oddsCache = new Map();

  function expectedMargin(g, now) {
    const S = SPORTS[g.sport];
    const d = strength(g.league, g.home) - strength(g.league, g.away);
    let mu = S.perTeam * 0.12 * d + S.homeEdge;
    if (g.state === 'scheduled') mu += 0.05 * S.marginSigma * TO.unit(`drift-${g.id}-${Math.floor(now / ODDS_BUCKET_PRE)}`);
    const ov = overrides()[g.id];
    if (ov && ov.nudge) mu += ov.nudge * S.marginSigma;
    return mu;
  }

  function computeOdds(g, now) {
    const S = SPORTS[g.sport];
    const rem = g.state === 'live' ? 1 - g.progress : 1;
    const suspended = !(g.state === 'scheduled' || g.state === 'live') || (g.state === 'live' && rem < 0.03);
    const mu0 = expectedMargin(g, now);
    const minSD = S.discrete ? 0.35 : 0.8;
    let mu, sd;
    if (g.state === 'live') {
      mu = (g.homeScore - g.awayScore) + mu0 * rem;
      sd = Math.max(S.marginSigma * Math.pow(rem, 0.4), minSD);
    } else { mu = mu0; sd = S.marginSigma; }
    const sel = (market, side, line, p) => ({ id: `${g.id}|${market}|${side}`, kind: 'game', gameId: g.id, market, side, line, price: TO.odds.fromProb(p) });

    let moneyline;
    if (S.draw) {
      const pHome = 1 - TO.phi((0.5 - mu) / sd);
      const pAway = TO.phi((-0.5 - mu) / sd);
      const pDraw = Math.max(1 - pHome - pAway, 0.02);
      moneyline = [sel('ml', 'away', null, pAway), sel('ml', 'draw', null, pDraw), sel('ml', 'home', null, pHome)];
    } else {
      const pHome = TO.phi(mu / sd);
      moneyline = [sel('ml', 'away', null, 1 - pHome), sel('ml', 'home', null, pHome)];
    }
    let spread = [];
    if (S.spread) {
      const homeLine = S.spread === 'fixed' ? (mu >= 0 ? -1.5 : 1.5) : -TO.hook(mu);
      const pCover = 1 - TO.phi((-homeLine - mu) / sd);
      spread = [sel('spread', 'away', -homeLine, 1 - pCover), sel('spread', 'home', homeLine, pCover)];
    }
    const base = LEAGUES[g.league].id === 'sim' ? 222 : S.perTeam * 2;
    const baseTotal = base * (1 + 0.06 * TO.unit(`total-${g.id}`));
    let projected, sdT;
    if (g.state === 'live') {
      projected = g.homeScore + g.awayScore + baseTotal * rem;
      sdT = Math.max(S.totalSigma * Math.pow(rem, 0.4), minSD);
    } else { projected = baseTotal; sdT = S.totalSigma; }
    const line = TO.hook(projected);
    const pOver = 1 - TO.phi((line - projected) / sdT);
    const total = [sel('total', 'over', line, pOver), sel('total', 'under', line, 1 - pOver)];
    return { moneyline, spread, total, suspended, all: [...moneyline, ...spread, ...total] };
  }

  /** Current odds for a game. Live prices refresh every 15 seconds; pre-game every 2 minutes. */
  function odds(id, now = TO.now()) {
    const g = game(id, now);
    if (!g) return null;
    const bucketLen = g.state === 'live' ? ODDS_BUCKET_LIVE : ODDS_BUCKET_PRE;
    const bucket = Math.floor(now / bucketLen) * bucketLen;
    const nudge = (overrides()[id] || {}).nudge || 0;
    const key = `${id}|${bucket}|${nudge}|${g.state}`;
    if (!oddsCache.has(key)) {
      const gb = g.state === 'live' ? game(id, Math.max(bucket, g.start)) : g;
      const o = computeOdds(gb.state === 'live' || gb.state === 'scheduled' ? gb : g, bucket);
      if (g.state !== 'live' && g.state !== 'scheduled') o.suspended = true;
      if (g.state === 'live' && 1 - g.progress < 0.03) o.suspended = true;
      o.updatedAt = bucket;
      // Movement vs the previous refresh, for the up/down arrows.
      const prevT = bucket - bucketLen;
      const gp = game(id, prevT);
      if (gp && (gp.state === 'live' || gp.state === 'scheduled')) {
        const prev = computeOdds(gp, prevT);
        o.move = {};
        for (const s of o.all) {
          const p = prev.all.find((x) => x.id === s.id);
          if (p && p.price !== s.price) o.move[s.id] = s.price > p.price ? 1 : -1;
        }
      } else o.move = {};
      oddsCache.set(key, o);
      if (oddsCache.size > 3000) oddsCache.clear();
    }
    return oddsCache.get(key);
  }

  // ---------- Prediction markets (Could-have) ----------
  const PRED_CYCLE = 60 * MIN;
  const PREDICTIONS = [
    { q: 'Will the top movie this weekend earn over $60M?', cat: 'Movies', p: 0.42 },
    { q: 'Will it rain in Salt Lake City tomorrow?', cat: 'Weather', p: 0.3 },
    { q: 'Will a brand-new song debut at #1 on the charts this week?', cat: 'Music', p: 0.36 },
    { q: 'Will the next rocket launch from Cape Canaveral go up on schedule?', cat: 'Science', p: 0.68 },
    { q: 'Will average gas prices in Utah drop below $3.40 this week?', cat: 'Economy', p: 0.45 },
    { q: 'Will any Sim League team score 130+ in the next hour?', cat: 'Sim League', p: 0.4 },
    { q: 'Will a first-time winner take the next pro golf tournament?', cat: 'Sports', p: 0.55 },
  ];

  function prediction(id, now = TO.now()) {
    const [, iStr, cStr] = id.split('-');
    const i = Number(iStr), cycle = Number(cStr);
    const def = PREDICTIONS[i];
    if (!def) return null;
    const opens = cycle * PRED_CYCLE + i * 8 * MIN;
    const resolves = opens + PRED_CYCLE;
    const closes = resolves - 2 * MIN;
    const drift = 0.12 * TO.unit(`${id}-${Math.floor(now / ODDS_BUCKET_PRE)}`);
    const pYes = TO.clamp(def.p + drift, 0.08, 0.92);
    const outcome = TO.u01(`out-${id}`) < def.p ? 'yes' : 'no';
    const state = now >= resolves ? 'resolved' : now >= closes ? 'closed' : 'open';
    const prevDrift = 0.12 * TO.unit(`${id}-${Math.floor(now / ODDS_BUCKET_PRE) - 1}`);
    const prevYes = TO.clamp(def.p + prevDrift, 0.08, 0.92);
    const yes = { id: `${id}|pred|yes`, kind: 'pred', predId: id, market: 'pred', side: 'yes', line: null, price: TO.odds.fromProb(pYes) };
    const no = { id: `${id}|pred|no`, kind: 'pred', predId: id, market: 'pred', side: 'no', line: null, price: TO.odds.fromProb(1 - pYes) };
    const move = {};
    const py = TO.odds.fromProb(prevYes), pn = TO.odds.fromProb(1 - prevYes);
    if (py !== yes.price) move[yes.id] = yes.price > py ? 1 : -1;
    if (pn !== no.price) move[no.id] = no.price > pn ? 1 : -1;
    return { id, q: def.q, cat: def.cat, opens, closes, resolves, state, outcome: state === 'resolved' ? outcome : null, pYes, yes, no, move, suspended: state !== 'open' };
  }

  function predictions(now = TO.now()) {
    return PREDICTIONS.map((_, i) => {
      const cycle = Math.floor((now - i * 8 * MIN) / PRED_CYCLE);
      return prediction(`pm-${i}-${cycle}`, now);
    }).sort((a, b) => a.resolves - b.resolves);
  }

  // ---------- Selections ----------
  /** Current version of a selection (same pick, latest line and price). */
  function currentSelection(selId, now = TO.now()) {
    const [ref, market, side] = selId.split('|');
    if (market === 'pred') {
      const p = prediction(ref, now);
      if (!p) return null;
      return { sel: side === 'yes' ? p.yes : p.no, open: p.state === 'open' };
    }
    const o = odds(ref, now);
    if (!o) return null;
    const sel = o.all.find((s) => s.id === selId);
    return { sel, open: !!sel && !o.suspended };
  }

  function teamOf(g, side) { return side === 'home' ? g.home : side === 'away' ? g.away : null; }

  /** e.g. "Chiefs −3.5", "Over 44.5", "Lakers ML", "Draw", "Yes". */
  function selectionLabel(sel, g) {
    if (sel.market === 'pred') return sel.side === 'yes' ? 'Yes' : 'No';
    const team = g ? teamOf(g, sel.side) : null;
    switch (sel.market) {
      case 'ml': return team ? `${team.name} to win` : 'Draw';
      case 'spread': return `${team.name} ${TO.odds.fmtLine(sel.line)}`;
      case 'total': return `${sel.side === 'over' ? 'Over' : 'Under'} ${TO.odds.fmtLine(sel.line, false)}`;
    }
    return '';
  }

  function marketLabel(sel, g) {
    if (sel.market === 'pred') return 'Prediction';
    if (sel.market === 'ml') return 'Moneyline';
    if (sel.market === 'spread') return g ? SPORTS[g.sport].spreadLabel : 'Spread';
    return 'Total';
  }

  /** Grades a pick against a game or prediction. Returns pending | won | lost | push | void. */
  function grade(sel, now = TO.now()) {
    if (sel.market === 'pred') {
      const p = prediction(sel.predId || sel.id.split('|')[0], now);
      if (!p || p.state !== 'resolved') return 'pending';
      return p.outcome === sel.side ? 'won' : 'lost';
    }
    const g = game(sel.gameId, now);
    if (!g) return 'pending';
    if (g.state === 'postponed') return 'void';
    if (g.state !== 'final') return 'pending';
    return gradeScore(sel, g.homeScore, g.awayScore);
  }

  function gradeScore(sel, H, A) {
    switch (sel.market) {
      case 'ml':
        if (sel.side === 'draw') return H === A ? 'won' : 'lost';
        if (H === A) return 'lost';
        return (sel.side === 'home') === (H > A) ? 'won' : 'lost';
      case 'spread': {
        const m = (sel.side === 'home' ? H - A : A - H) + sel.line;
        return m > 0 ? 'won' : m < 0 ? 'lost' : 'push';
      }
      case 'total': {
        const tot = H + A;
        if (tot === sel.line) return 'push';
        return (sel.side === 'over') === (tot > sel.line) ? 'won' : 'lost';
      }
    }
    return 'pending';
  }

  /** How an open pick is doing right now: winning | losing | even | upcoming. */
  function liveStanding(sel, now = TO.now()) {
    if (sel.market === 'pred') {
      const p = prediction(sel.predId || sel.id.split('|')[0], now);
      if (!p) return 'upcoming';
      return (sel.side === 'yes' ? p.pYes : 1 - p.pYes) >= 0.5 ? 'winning' : 'losing';
    }
    const g = game(sel.gameId, now);
    if (!g || g.state === 'scheduled') return 'upcoming';
    if (g.state === 'postponed') return 'void';
    if (sel.market === 'total') {
      // Compare pace, not the raw score, so an over isn't "losing" in the first minute.
      const pace = g.progress > 0.05 ? (g.homeScore + g.awayScore) / g.progress : sel.line;
      if (Math.abs(pace - sel.line) < 0.5) return 'even';
      return (sel.side === 'over') === (pace > sel.line) ? 'winning' : 'losing';
    }
    const r = gradeScore(sel, g.homeScore, g.awayScore);
    if (r === 'push') return 'even';
    if (sel.market === 'ml' && g.homeScore === g.awayScore) return sel.side === 'draw' ? 'winning' : 'even';
    return r === 'won' ? 'winning' : 'losing';
  }

  /** The other side of a pick, used when accepting a friend's challenge. */
  function oppositeSelection(sel) {
    const flip = { home: 'away', away: 'home', over: 'under', under: 'over', yes: 'no', no: 'yes' };
    const side = flip[sel.side];
    const [ref, market] = sel.id.split('|');
    const line = sel.market === 'spread' ? -sel.line : sel.line;
    return Object.assign({}, sel, { id: `${ref}|${market}|${side}`, side, line });
  }

  TO.sim = {
    SLOT, DURATION, STEP, SPORTS, LEAGUES, REAL_LEAGUES, LEAGUE_ORDER, PREDICTIONS,
    game, board, odds, plays, stats, research, record, form, strength,
    prediction, predictions, currentSelection, selectionLabel, marketLabel, grade, gradeScore, liveStanding, oppositeSelection, teamOf,
    overrides, setOverride,
  };
})(window.TO);
