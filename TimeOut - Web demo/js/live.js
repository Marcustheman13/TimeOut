/* TimeOut web demo — ESPN live scores and sportsbook lines. */
(function (TO) {
  'use strict';

  const S = TO.sim;
  const ESPN = 'https://site.api.espn.com/apis/site/v2/sports';
  const ESPN_CORE = 'https://sports.core.api.espn.com/v2/sports';
  const CFB_GROUPS = [
    ['all', 'All College Football'], ['80', 'Top 25'], ['8', 'SEC'], ['4', 'Big 12'], ['1', 'ACC'], ['5', 'Big Ten'],
    ['9', 'Pac-12'], ['151', 'American'], ['17', 'Mountain West'], ['37', 'Sun Belt'],
    ['15', 'MAC'], ['12', 'Conference USA'], ['18', 'Independents'],
  ];
  const LEAGUES = {
    nfl: ['football/nfl', 'football', 'nfl'], ncaaf: ['football/college-football', 'football', 'college-football'],
    nba: ['basketball/nba', 'basketball', 'nba'], mlb: ['baseball/mlb', 'baseball', 'mlb'],
    nhl: ['hockey/nhl', 'hockey', 'nhl'], epl: ['soccer/eng.1', 'soccer', 'eng.1'],
  };
  const cache = new Map();
  const oddsCache = new Map();
  let updatedAt = 0;
  let loading = false;
  let refreshQueued = false;
  let loadError = false;
  let cfbGroup = 'all';

  function todayBounds(now) {
    const d = new Date(now);
    const start = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    return [start, new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime()];
  }

  function gameFrom(event, league, sport) {
    const comp = event.competitions?.[0];
    const home = comp?.competitors?.find((c) => c.homeAway === 'home');
    const away = comp?.competitors?.find((c) => c.homeAway === 'away');
    if (!comp || !home?.team || !away?.team) return null;
    const start = Date.parse(event.date || comp.date || '');
    if (!Number.isFinite(start)) return null;
    const status = comp.status?.type || event.status?.type || {};
    const state = /POSTPONED/.test(status.name || '') ? 'postponed'
      : /CANCELED|CANCELLED|ABANDONED|FORFEIT/.test(status.name || '') ? 'canceled'
        : status.state === 'in' ? 'live' : status.state === 'post' ? 'final' : 'scheduled';
    const team = (c) => ({
      id: c.team.id, abbr: c.team.abbreviation || c.team.shortDisplayName || c.team.displayName,
      name: c.team.shortDisplayName || c.team.displayName || c.team.name,
      fullName: c.team.displayName || c.team.name, city: '', color: `#${c.team.color || '5A6475'}`,
      logo: c.team.logo || c.team.logos?.[0]?.href || null,
      rank: c.curatedRank?.current && c.curatedRank.current <= 25 ? c.curatedRank.current : null,
      record: c.records?.find((record) => record.type === 'total')?.summary || c.records?.[0]?.summary || null,
    });
    return {
      id: `espn-${league}-${event.id}`, eventID: event.id, league, sport, start,
      competitionID: comp.id || event.id,
      end: start + 4 * TO.HOUR, state, home: team(home), away: team(away),
      homeScore: Number(home.score || 0), awayScore: Number(away.score || 0),
      progress: state === 'live' ? 0.5 : state === 'final' ? 1 : 0,
      period: comp.status?.period || 0, clock: status.shortDetail || comp.status?.displayClock || '',
      statusText: status.shortDetail || status.detail || status.description || 'Scheduled',
      conferenceName: comp.groups?.shortName || comp.groups?.name || '',
      simulated: false, _competition: comp,
    };
  }

  function american(value) {
    const n = Number(value);
    return Number.isFinite(n) && n !== 0 ? Math.round(n) : null;
  }

  function hasPrice(value) { return american(value) != null; }

  function marketPrice(teamOdds, market) {
    const value = (entry) => entry?.american ?? entry?.alternateDisplayValue
      ?? (typeof entry === 'number' || typeof entry === 'string' ? entry : null);
    return value(teamOdds?.[market]) ?? value(teamOdds?.current?.[market]);
  }

  function moneylinePrice(book, side) {
    if (side === 'draw') {
      return marketPrice(book?.drawOdds, 'moneyLine')
        ?? book?.drawOdds?.moneyLine
        ?? book?.moneyline?.draw?.current?.odds
        ?? book?.moneyline?.draw?.close?.odds
        ?? book?.moneyline?.draw?.open?.odds;
    }
    const teamOdds = side === 'home' ? book?.homeTeamOdds : book?.awayTeamOdds;
    return marketPrice(teamOdds, 'moneyLine')
      ?? teamOdds?.moneyline
      ?? book?.moneyline?.[side]?.current?.odds
      ?? book?.moneyline?.[side]?.close?.odds
      ?? book?.moneyline?.[side]?.open?.odds;
  }

  function spreadPrice(book, side) {
    const teamOdds = side === 'home' ? book?.homeTeamOdds : book?.awayTeamOdds;
    const market = book?.pointSpread?.[side];
    return marketPrice(teamOdds, 'spread')
      ?? teamOdds?.spreadOdds
      ?? market?.current?.odds
      ?? market?.close?.odds
      ?? market?.open?.odds
      ?? (side === 'home' ? book?.homeSpreadOdds : book?.awaySpreadOdds);
  }

  function totalPrice(book, side) {
    const flat = side === 'over' ? (book?.overOdds ?? book?.overUnderOdds) : (book?.underOdds ?? book?.underUnderOdds);
    const market = book?.total?.[side] || book?.overUnder?.[side];
    return flat ?? market?.current?.odds ?? market?.close?.odds ?? market?.open?.odds;
  }

  function totalLine(book) {
    const raw = Number(book?.overUnder ?? book?.total);
    return Number.isFinite(raw) && raw > 0 ? raw : null;
  }

  function isBookmaker(book) {
    if (!book) return false;
    const name = String(book?.provider?.name || '').toLowerCase();
    if (/numberfire|predictor|win probability/.test(name)) return false;
    return true;
  }

  function spreadFor(book, game, homeOdds, awayOdds) {
    const homeMarketLine = homeOdds.current?.pointSpread?.alternateDisplayValue
      ?? homeOdds.current?.pointSpread?.american
      ?? homeOdds.pointSpread?.alternateDisplayValue
      ?? homeOdds.pointSpread?.american
      ?? book.pointSpread?.home?.current?.line
      ?? book.pointSpread?.home?.close?.line
      ?? book.pointSpread?.home?.open?.line;
    const awayMarketLine = awayOdds.current?.pointSpread?.alternateDisplayValue
      ?? awayOdds.current?.pointSpread?.american
      ?? awayOdds.pointSpread?.alternateDisplayValue
      ?? awayOdds.pointSpread?.american
      ?? book.pointSpread?.away?.current?.line
      ?? book.pointSpread?.away?.close?.line
      ?? book.pointSpread?.away?.open?.line;
    const direct = Number(homeMarketLine ?? homeOdds.spread ?? book.homeSpread);
    if (Number.isFinite(direct) && direct !== 0) return direct;
    const awayLine = Number(awayMarketLine);
    if (Number.isFinite(awayLine) && awayLine !== 0) return -awayLine;
    // ESPN's MLB `details` is the moneyline favorite and price, not a run line.
    if (game.sport === 'baseball') return null;
    const detail = String(book.details || '');
    const match = detail.match(/([+-]\s*\d+(?:\.\d+)?)/);
    const value = match ? Number(match[1].replace(/\s/g, '')) : Number(book.spread);
    if (!Number.isFinite(value) || value === 0 || Math.abs(value) > 50) return null;
    if (homeOdds.favorite === true) return -Math.abs(value);
    if (awayOdds.favorite === true) return Math.abs(value);
    const namedHome = [game.home.abbr, game.home.name, game.home.fullName].filter(Boolean).some((name) => detail.toLowerCase().includes(name.toLowerCase()));
    const namedAway = [game.away.abbr, game.away.name, game.away.fullName].filter(Boolean).some((name) => detail.toLowerCase().includes(name.toLowerCase()));
    if (namedHome) return value;
    if (namedAway) return -value;
    const signedHomeSpread = Number(book.spread);
    return Number.isFinite(signedHomeSpread) && signedHomeSpread !== 0 ? signedHomeSpread : null;
  }

  function makeOdds(game, now = TO.now()) {
    const comp = game._competition || {};
    const candidates = game._oddsBooks?.length
      ? [...game._oddsBooks, ...(game.state === 'live' ? [] : (comp.odds || []))]
      : [game._oddsBook || comp.odds?.[0]].filter(Boolean);
    const books = candidates.filter(isBookmaker);
    const liveBooks = books.filter((book) => /live odds/i.test(book.provider?.name || ''));
    const marketBooks = game.state === 'live' && liveBooks.length ? liveBooks : books;
    const add = (market, side, n, price, title) => {
      const parsedPrice = american(price);
      return parsedPrice == null ? null : {
        id: `${game.id}|${market}|${side}`, kind: 'game', gameId: game.id, market, side,
        line: n, price: parsedPrice, source: title || '',
      };
    };
    const moneyline = ['away', 'home', 'draw'].map((side) => {
      const source = marketBooks.find((book) => hasPrice(moneylinePrice(book, side)));
      const team = side === 'home' ? source?.homeTeamOdds?.team : source?.awayTeamOdds?.team;
      return source ? add('ml', side, null, moneylinePrice(source, side), side === 'draw' ? 'Draw' : team?.displayName) : null;
    }).filter(Boolean);
    const spreads = marketBooks.map((book) => ({ book, line: spreadFor(book, game, book.homeTeamOdds || {}, book.awayTeamOdds || {}) }))
      .filter((entry) => entry.line != null && (hasPrice(spreadPrice(entry.book, 'home')) || hasPrice(spreadPrice(entry.book, 'away'))));
    const spreadSource = spreads.find((entry) => hasPrice(spreadPrice(entry.book, 'home')) && hasPrice(spreadPrice(entry.book, 'away'))) || spreads[0];
    const spreadLine = spreadSource?.line;
    const priceAtLine = (side) => {
      const entry = spreads.find((candidate) => candidate.line === spreadLine && hasPrice(spreadPrice(candidate.book, side)));
      return entry ? spreadPrice(entry.book, side) : null;
    };
    const spread = spreadLine != null ? [
      add('spread', 'away', -spreadLine, priceAtLine('away'), 'Away'),
      add('spread', 'home', spreadLine, priceAtLine('home'), 'Home'),
    ].filter(Boolean) : [];
    const totals = marketBooks.map((book) => ({ book, line: totalLine(book) }))
      .filter((entry) => entry.line != null && (hasPrice(totalPrice(entry.book, 'over')) || hasPrice(totalPrice(entry.book, 'under'))));
    const totalSource = totals.find((entry) => hasPrice(totalPrice(entry.book, 'over')) && hasPrice(totalPrice(entry.book, 'under'))) || totals[0];
    const selectedTotalLine = totalSource?.line;
    const totalAtLine = (side) => {
      const entry = totals.find((candidate) => candidate.line === selectedTotalLine && hasPrice(totalPrice(candidate.book, side)));
      return entry ? totalPrice(entry.book, side) : null;
    };
    const total = selectedTotalLine != null ? [
      add('total', 'over', selectedTotalLine, totalAtLine('over'), 'Over'),
      add('total', 'under', selectedTotalLine, totalAtLine('under'), 'Under'),
    ].filter(Boolean) : [];
    const suspended = !['scheduled', 'live'].includes(game.state) || (books.length > 0 && books.every((book) => book.isClosed === true));
    return { moneyline, spread, total, suspended, all: [...moneyline, ...spread, ...total], move: {}, updatedAt };
  }

  function selectedGroup() { return cfbGroup; }
  async function fetchLeague(league, group = '80') {
    const [path] = LEAGUES[league];
    const params = new URLSearchParams();
    if (league === 'ncaaf') {
      if (group !== 'all') params.set('groups', group);
      params.set('limit', '100');
    }
    const url = `${ESPN}/${path}/scoreboard${params.size ? `?${params}` : ''}`;
    const response = await fetch(url, { cache: 'no-store' });
    if (!response.ok) throw new Error(`ESPN returned ${response.status}`);
    const payload = await response.json();
    return (payload.events || []).map((event) => gameFrom(event, league, LEAGUES[league][1])).filter(Boolean);
  }

  async function resolveOddsItem(item) {
    if (!item?.$ref) return item;
    const response = await fetch(item.$ref.replace(/^http:/, 'https:'), { cache: 'no-store' });
    if (!response.ok) throw new Error(`ESPN odds returned ${response.status}`);
    return response.json();
  }

  async function fetchEventOdds(game, now) {
    const cached = oddsCache.get(game.id);
    if (cached && now - cached.at < 25000) return cached.books || (cached.book ? [cached.book] : []);
    const [,, coreLeague] = LEAGUES[game.league];
    const endpoint = `${ESPN_CORE}/${game.sport}/leagues/${coreLeague}/events/${game.eventID}/competitions/${game.competitionID}/odds?limit=10`;
    try {
      const response = await fetch(endpoint, { cache: 'no-store' });
      if (!response.ok) throw new Error(`ESPN odds returned ${response.status}`);
      const payload = await response.json();
      const items = payload.items || (payload.provider || payload.homeTeamOdds ? [payload] : []);
      const refs = items.filter((item) => isBookmaker(item)).slice(0, 8);
      const books = await Promise.allSettled(refs.map(resolveOddsItem));
      const availableBooks = books.filter((result) => result.status === 'fulfilled').map((result) => result.value)
        .filter((book) => isBookmaker(book) && (book.overUnder != null || book.spread != null || book.homeTeamOdds?.spread != null
          || hasPrice(moneylinePrice(book, 'home')) || hasPrice(moneylinePrice(book, 'away')) || hasPrice(moneylinePrice(book, 'draw')))
          && (hasPrice(book.overOdds ?? book.overUnderOdds) || hasPrice(book.underOdds ?? book.underUnderOdds)
            || hasPrice(book.homeTeamOdds?.spreadOdds) || hasPrice(book.awayTeamOdds?.spreadOdds)
            || hasPrice(moneylinePrice(book, 'home')) || hasPrice(moneylinePrice(book, 'away')) || hasPrice(moneylinePrice(book, 'draw'))));
      const preferred = game.state === 'live'
        ? availableBooks.sort((a, b) => Number(/live odds/i.test(b.provider?.name || '')) - Number(/live odds/i.test(a.provider?.name || '')))
        : availableBooks.sort((a, b) => Number(/live odds/i.test(a.provider?.name || '')) - Number(/live odds/i.test(b.provider?.name || '')));
      oddsCache.set(game.id, { at: now, books: preferred });
      return preferred;
    } catch (error) {
      console.warn('ESPN odds unavailable:', error);
      oddsCache.set(game.id, { at: now, books: [] });
      return [];
    }
  }

  async function loadOdds(games, now) {
    let cursor = 0;
    const worker = async () => {
      while (cursor < games.length) {
        const game = games[cursor++];
        const scoreboardBook = game._competition.odds?.[0];
        const hasScoreboardLines = game.state !== 'live' && isBookmaker(scoreboardBook)
          && hasPrice(scoreboardBook.homeTeamOdds?.spreadOdds)
          && hasPrice(scoreboardBook.awayTeamOdds?.spreadOdds)
          && hasPrice(scoreboardBook.overOdds) && hasPrice(scoreboardBook.underOdds)
          && hasPrice(moneylinePrice(scoreboardBook, 'home'))
          && hasPrice(moneylinePrice(scoreboardBook, 'away'));
        if (!hasScoreboardLines) game._oddsBooks = await fetchEventOdds(game, now);
        game.odds = makeOdds(game, now);
      }
    };
    await Promise.all(Array.from({ length: Math.min(6, games.length) }, worker));
    TO.emit('live:updated');
  }

  async function loadDetails(id) {
    const game = byId(id);
    if (!game || game._detailLoaded || game._detailLoading) return game?._details || null;
    game._detailLoading = true;
    try {
      const [path] = LEAGUES[game.league];
      const response = await fetch(`${ESPN}/${path}/summary?event=${encodeURIComponent(game.eventID)}`, { cache: 'no-store' });
      if (!response.ok) throw new Error(`ESPN summary returned ${response.status}`);
      game._details = await response.json();
      game._detailLoaded = true;
      return game._details;
    } catch (error) {
      console.warn('ESPN game details unavailable:', error);
      return null;
    } finally {
      game._detailLoading = false;
      TO.emit('live:details-updated', game.id);
    }
  }

  function realStats(game) {
    const boxscore = game?._details?.boxscore;
    const teams = boxscore?.teams || [];
    const home = teams.find((item) => String(item.team?.id) === String(game.home.id));
    const away = teams.find((item) => String(item.team?.id) === String(game.away.id));
    if (!home || !away) return [];
    const indexStats = (team) => new Map((team.statistics || []).map((stat) => [stat.name || stat.label, stat]));
    const awayStats = indexStats(away), homeStats = indexStats(home);
    return [...awayStats.keys()].flatMap((key) => {
      const a = awayStats.get(key), h = homeStats.get(key);
      if (!h) return [];
      const label = a.label || a.displayName || a.name || key;
      const av = a.displayValue ?? a.value;
      const hv = h.displayValue ?? h.value;
      if (av == null || hv == null) return [];
      return [{ label, awayValue: String(av), homeValue: String(hv) }];
    });
  }

  async function refresh(now = TO.now()) {
    if (loading) { refreshQueued = true; return; }
    if (now - updatedAt < 25000) return;
    loading = true;
    loadError = false;
    const leagues = TO.data?.settings?.sports?.filter((key) => LEAGUES[key]) || Object.keys(LEAGUES);
    const results = await Promise.allSettled(leagues.map((league) => fetchLeague(league, cfbGroup)));
    const [dayStart, dayEnd] = todayBounds(now);
    let failed = false;
    results.forEach((result, index) => {
      if (result.status !== 'fulfilled') { failed = true; return; }
      const league = leagues[index];
      const todays = result.value.filter((game) => game.start >= dayStart && game.start < dayEnd);
      const games = league === 'ncaaf' && cfbGroup === '80'
        ? todays.filter((game) => game.home.rank || game.away.rank)
        : todays;
      games.forEach((game) => { game.odds = makeOdds(game, now); });
      cache.set(league, games);
    });
    loadError = failed && !results.some((r) => r.status === 'fulfilled');
    updatedAt = now;
    loading = false;
    TO.emit('live:updated');
    const todaysGames = [...cache.values()].flat();
    loadOdds(todaysGames, now);
    if (refreshQueued) {
      refreshQueued = false;
      updatedAt = 0;
      refresh();
    }
  }

  function byId(id) {
    for (const games of cache.values()) {
      const game = games.find((item) => item.id === id || item.eventID === id);
      if (game) return game;
    }
    return null;
  }

  // Keep the existing selection, slip and settlement code, but supply ESPN game data and prices.
  const simGame = S.game, simBoard = S.board, simOdds = S.odds, simCurrent = S.currentSelection, simGrade = S.grade;
  S.game = (id, now) => byId(id) || simGame(id, now);
  S.board = (now = TO.now(), options = {}) => {
    if (now - updatedAt > 25000) refresh(now);
    const leagues = options.leagues || S.LEAGUE_ORDER;
    return leagues.flatMap((league) => {
      const games = [...(cache.get(league) || [])];
      return games;
    }).filter((game) => {
      const [start, end] = todayBounds(now);
      return game.start >= start && game.start < end;
    }).sort((a, b) => (a.state === 'live' ? 0 : 1) - (b.state === 'live' ? 0 : 1) || a.start - b.start);
  };
  S.odds = (id, now) => byId(id)?.odds || simOdds(id, now);
  S.currentSelection = (id, now) => {
    const [ref] = id.split('|');
    const game = byId(ref);
    if (!game) return simCurrent(id, now);
    const selection = game.odds.all.find((item) => item.id === id);
    return { sel: selection || null, open: !!selection && !game.odds.suspended && game.state !== 'final' };
  };
  S.grade = (selection, now) => {
    const game = byId(selection.gameId);
    if (!game) return simGrade(selection, now);
    if (game.state === 'postponed' || game.state === 'canceled') return 'void';
    if (game.state !== 'final') return 'pending';
    return S.gradeScore(selection, game.homeScore, game.awayScore);
  };

  TO.live = {
    refresh, loadDetails, stats: realStats, selectedGroup, setGroup(group) {
      cfbGroup = CFB_GROUPS.some(([id]) => id === group) ? group : 'all';
      cache.delete('ncaaf'); updatedAt = 0; refresh();
    },
    groups: CFB_GROUPS, get loading() { return loading; }, get failed() { return loadError; },
  };
})(window.TO);
