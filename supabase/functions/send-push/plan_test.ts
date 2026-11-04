// Run with: deno test supabase/functions/send-push/plan_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { espnEventId, gradeScore, type GameState, outcome, parseSummary, pickLabel, planChallenge, planRequest, summaryPath, type WorkChallenge, type WorkPick } from "./plan.ts";

const pick = (over: Partial<WorkPick> = {}): WorkPick => ({
  eventId: "espn-nba-401909907",
  league: "nba",
  matchup: "Hawks @ Wizards",
  market: "winner",
  side: "home",
  line: null,
  price: 100,
  result: "pending",
  ...over,
});

const challenge = (over: Partial<WorkChallenge> = {}): WorkChallenge => ({
  id: "c1",
  userId: "u1",
  status: "pending",
  pledgeMinutes: 20,
  rewardMinutes: null,
  insured: false,
  multiplier: 1,
  picks: [pick()],
  ...over,
});

const final = (home: number, away: number): GameState => ({ state: "final", home, away });
const games = (entries: Record<string, GameState>) => new Map(Object.entries(entries));

Deno.test("event ids come from the stored game id", () => {
  assertEquals(espnEventId("espn-nba-401909907"), "401909907");
  assertEquals(espnEventId("401909907"), "401909907");
  assertEquals(espnEventId("sim-game-a"), null);
  assertEquals(summaryPath(pick()), "basketball/nba/summary?event=401909907");
  assertEquals(summaryPath(pick({ league: "unknown" })), null);
  assertEquals(summaryPath(pick({ eventId: "sim-game-a" })), null);
});

Deno.test("grading matches Sim.gradeScore", () => {
  assertEquals(gradeScore("winner", "home", null, 3, 1), "won");
  assertEquals(gradeScore("winner", "away", null, 3, 1), "lost");
  assertEquals(gradeScore("winner", "home", null, 2, 2), "lost");
  assertEquals(gradeScore("winner", "draw", null, 2, 2), "won");
  assertEquals(gradeScore("margin", "home", -3.5, 110, 100), "won");
  assertEquals(gradeScore("margin", "home", -10, 110, 100), "tie");
  assertEquals(gradeScore("margin", "away", 3.5, 110, 100), "lost");
  assertEquals(gradeScore("total", "higher", 200.5, 110, 100), "won");
  assertEquals(gradeScore("total", "lower", 200.5, 110, 100), "lost");
  assertEquals(gradeScore("total", "higher", 210, 110, 100), "tie");
  assertEquals(gradeScore("pred", "home", null, 1, 0), "pending");
});

Deno.test("outcomes match Store.outcome", () => {
  const plain = { pledgeMinutes: 20, insured: false, multiplier: 1 };
  assertEquals(outcome(plain, [{ result: "won", price: 100 }]), { status: "won", reward: 40, insurancePaid: false });
  assertEquals(outcome(plain, [{ result: "won", price: -200 }]), { status: "won", reward: 30, insurancePaid: false });
  assertEquals(outcome(plain, [{ result: "won", price: 100 }, { result: "pending", price: 100 }]).status, "open");
  // A lost pick ends a combo straight away, unless miss-one protection is waiting on the rest.
  assertEquals(outcome(plain, [{ result: "lost", price: 100 }, { result: "pending", price: 100 }]).status, "lost");
  const insured = { ...plain, insured: true };
  assertEquals(outcome(insured, [{ result: "lost", price: 100 }, { result: "pending", price: 100 }]).status, "open");
  assertEquals(outcome(insured, [{ result: "lost", price: 100 }, { result: "won", price: 100 }]), { status: "tie", reward: 20, insurancePaid: true });
  assertEquals(outcome(insured, [{ result: "lost", price: 100 }, { result: "lost", price: 100 }]).status, "lost");
  assertEquals(outcome(plain, [{ result: "void", price: 100 }]), { status: "void", reward: 20, insurancePaid: false });
  assertEquals(outcome(plain, [{ result: "void", price: 100 }, { result: "tie", price: 100 }]).status, "tie");
  // Boosts multiply the profit, and the total caps at 120.
  assertEquals(outcome({ ...plain, multiplier: 1.5 }, [{ result: "won", price: 100 }]).reward, 50);
  assertEquals(outcome({ ...plain, pledgeMinutes: 60 }, [{ result: "won", price: 500 }]).reward, 120);
});

Deno.test("labels match Sim.pickLabel", () => {
  assertEquals(pickLabel(pick()), "Wizards to win");
  assertEquals(pickLabel(pick({ side: "away" })), "Hawks to win");
  assertEquals(pickLabel(pick({ side: "draw" })), "Draw");
  assertEquals(pickLabel(pick({ market: "margin", line: -3.5 })), "Wizards -3.5");
  assertEquals(pickLabel(pick({ market: "margin", side: "away", line: 3 })), "Hawks +3");
  assertEquals(pickLabel(pick({ market: "total", side: "higher", line: 220.5 })), "Combined score above 220.5");
});

Deno.test("ESPN summaries are read the way LiveFeed reads the scoreboard", () => {
  const summary = (name: string, state: string) => ({
    header: { competitions: [{ status: { type: { name, state } }, competitors: [{ homeAway: "home", score: "112" }, { homeAway: "away", score: "117" }] }] },
  });
  assertEquals(parseSummary(summary("STATUS_FINAL", "post")), { state: "final", home: 112, away: 117 });
  assertEquals(parseSummary(summary("STATUS_FULL_TIME", "post"))?.state, "final");
  assertEquals(parseSummary(summary("STATUS_IN_PROGRESS", "in"))?.state, "pending");
  assertEquals(parseSummary(summary("STATUS_SCHEDULED", "pre"))?.state, "pending");
  assertEquals(parseSummary(summary("STATUS_POSTPONED", "post"))?.state, "void");
  assertEquals(parseSummary(summary("STATUS_CANCELED", "post"))?.state, "void");
  assertEquals(parseSummary({}), null);
});

Deno.test("a finished challenge gets a notification worded like the app's", () => {
  const push = planChallenge(challenge(), games({ "espn-nba-401909907": final(110, 100) }));
  assertEquals(push, {
    key: "challenge:c1",
    userId: "u1",
    tab: "challenges",
    collapseId: "c1",
    title: "Challenge complete: Wizards to win",
    body: "+20 earned minutes added to tomorrow's phone time.",
  });
  const lost = planChallenge(challenge(), games({ "espn-nba-401909907": final(100, 110) }));
  assertEquals(lost?.title, "Challenge missed: Wizards to win");
  assertEquals(lost?.body, "20 committed minutes deducted from tomorrow's phone time.");
});

Deno.test("nothing is sent while a game is unfinished or unknown", () => {
  assertEquals(planChallenge(challenge(), games({})), null);
  assertEquals(planChallenge(challenge(), games({ "espn-nba-401909907": { state: "pending", home: 50, away: 40 } })), null);
  assertEquals(planChallenge(challenge({ picks: [] }), games({})), null);
});

Deno.test("a combo says so, and waits for every pick", () => {
  const combo = challenge({ picks: [pick(), pick({ eventId: "espn-nba-2" })] });
  assertEquals(planChallenge(combo, games({ "espn-nba-401909907": final(110, 100) })), null);
  const done = planChallenge(combo, games({ "espn-nba-401909907": final(110, 100), "espn-nba-2": final(99, 80) }));
  assertEquals(done?.title, "Challenge complete: 2-pick Combo Goal");
  assertEquals(done?.body, "+60 earned minutes added to tomorrow's phone time.");
});

Deno.test("returned minutes explain why", () => {
  const postponed = planChallenge(challenge(), games({ "espn-nba-401909907": { state: "void", home: 0, away: 0 } }));
  assertEquals(postponed?.title, "Challenge returned: Wizards to win");
  assertEquals(postponed?.body, "The game was postponed. 20 minutes are available again.");
  const insured = challenge({ insured: true, picks: [pick(), pick({ eventId: "espn-nba-2" })] });
  const protectedPush = planChallenge(insured, games({ "espn-nba-401909907": final(100, 110), "espn-nba-2": final(99, 80) }));
  assertEquals(protectedPush?.body, "Miss-one protection returned your minutes. 20 minutes are available again.");
  const push = planChallenge(challenge({ picks: [pick({ market: "margin", line: -10 })] }), games({ "espn-nba-401909907": final(110, 100) }));
  assertEquals(push?.body, "It finished exactly on the target. 20 minutes are available again.");
});

Deno.test("a result another device saved uses the saved reward, without needing ESPN", () => {
  const won = planChallenge(challenge({ status: "won", rewardMinutes: 55 }), games({}));
  assertEquals(won?.body, "+35 earned minutes added to tomorrow's phone time.");
  assertEquals(planChallenge(challenge({ status: "lost", rewardMinutes: 0 }), games({}))?.title, "Challenge missed: Wizards to win");
  assertEquals(planChallenge(challenge({ status: "voided", rewardMinutes: 20 }), games({}))?.body, "The game was postponed. 20 minutes are available again.");
  const paid = challenge({ status: "tied", rewardMinutes: 20, insured: true, picks: [pick({ result: "loss" }), pick({ result: "win" })] });
  assertEquals(planChallenge(paid, games({}))?.body, "Miss-one protection returned your minutes. 20 minutes are available again.");
});

Deno.test("a friend request matches the app's own notification id", () => {
  assertEquals(planRequest({ key: "k", userId: "u2", username: "sam" }), {
    key: "k",
    userId: "u2",
    title: "@sam sent you a friend request",
    body: "Open Social to accept it.",
    tab: "social",
    collapseId: "request-sam",
  });
});
