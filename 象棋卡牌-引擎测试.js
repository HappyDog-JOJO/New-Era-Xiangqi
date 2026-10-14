// 兵符 · 规则引擎测试
// 用法：node 象棋卡牌-引擎测试.js
// 从 象棋卡牌-试玩Demo.html 中抽出规则引擎并跑断言。
//
// ⚠️ 重要：本文件测的是【已冻结的旧 Demo】，不是当前规则（规则书 v0.5）。
//    Demo 已被判定质量不达标、决定重建，因此它仍停留在 v0.2.5 的规则上：
//      · 仍有「士 · 护驾」与士牌（现行规则：士是开局自带的固定棋子，无护驾）
//      · 每回合可以移动多次（现行规则：每回合全盘只能移动一次）
//      · 士/象数量上限的写法与现行不同
//    重建 Demo 时，本测试文件必须同步重写。在那之前，**不要**用它判断规则是否被正确实现。
const fs = require('fs');
const path = 'C:\\Users\\sl\\Documents\\桌游想法\\象棋卡牌-试玩Demo.html';
const html = fs.readFileSync(path, 'utf8');
const m = html.match(/<script>([\s\S]*?)<\/script>/);
if (!m) { console.error('找不到 script'); process.exit(1); }
eval(m[1]);
const E = globalThis.__ENGINE;
if (!E) { console.error('引擎未导出'); process.exit(1); }

let pass = 0, fail = 0;
function ok(name, cond, extra) {
  if (cond) { pass++; console.log('  PASS  ' + name); }
  else { fail++; console.log('  FAIL  ' + name + (extra ? '   -> ' + extra : '')); }
}
function has(list, c, r) { return list.some(x => x.c === c && x.r === r); }
function mv(list, c, r) { return list.find(x => x.c === c && x.r === r); }

function bare() {
  const st = E.newGame('full');
  st.pieces = [];
  st.hands = { r: [], b: [] };
  st.phase = 'play';
  st.turn = 'r';
  st.ap = 2;
  st.deck = [];
  st.discard = [];
  return st;
}
function put(st, owner, kind, c, r, gear) {
  // 卡牌类型要与棋子类型一致（士/象是独立兵种牌，其余棋子由兵牌 + 装备牌组成）
  const cardKind = (kind === 'advisor' || kind === 'elephant') ? kind : 'pawn';
  const p = { id: 't' + (st.uid++), owner, kind, gear: gear || null,
    card: { id: 'tc' + (st.uid++), kind: cardKind },
    gearCard: gear ? { id: 'tg' + (st.uid++), kind: 'gear', gear: gear } : null, c, r };
  st.pieces.push(p);
  return p;
}

console.log('\n=== 牌库 ===');
const full = E.buildDeck('full'), quick = E.buildDeck('quick');
ok('完整版 60 张', full.length === 60, full.length);
ok('完整版：小兵 18', full.filter(c => c.kind === 'pawn').length === 18);
ok('完整版：士 3', full.filter(c => c.kind === 'advisor').length === 3);
ok('完整版：象 3', full.filter(c => c.kind === 'elephant').length === 3);
ok('完整版：装备 18', full.filter(c => c.kind === 'gear').length === 18);
ok('完整版：锦囊 18', full.filter(c => c.kind === 'spell').length === 18);
ok('完整版：14 种锦囊', new Set(full.filter(c => c.kind === 'spell').map(c => c.spell)).size === 14);
ok('试玩版 30 张', quick.length === 30, quick.length);

console.log('\n=== 开局 ===');
const g = E.newGame('full');
ok('两个主将', g.pieces.length === 2);
ok('红帅 (5,2)', !!E.pieceAt(g, 5, 2) && E.pieceAt(g, 5, 2).owner === 'r');
ok('黑将 (5,9)', !!E.pieceAt(g, 5, 9) && E.pieceAt(g, 5, 9).owner === 'b');
ok('红手牌 4', g.hands.r.length === 4, g.hands.r.length);
ok('黑手牌 5', g.hands.b.length === 5, g.hands.b.length);
ok('牌库剩 51', g.deck.length === 51, g.deck.length);
ok('阶段 = 布阵', g.phase === 'deploy');

console.log('\n=== 布阵阶段 ===');
let placed = 0;
[[1, 1], [2, 1], [3, 1]].forEach(([c, r]) => { if (E.doSetupDeploy(g, 'r', c, r)) placed++; });
ok('红方放下 3 个', placed === 3);
ok('轮黑方布阵', g.deployTurn === 'b');
ok('黑方不能放红方半场', E.doSetupDeploy(g, 'b', 5, 3) === false);
let placedB = 0;
[[1, 10], [2, 10], [3, 10]].forEach(([c, r]) => { if (E.doSetupDeploy(g, 'b', c, r)) placedB++; });
ok('黑方放下 3 个', placedB === 3);
ok('进入对局阶段', g.phase === 'play');
ok('红方先行', g.turn === 'r');
ok('红方摸到 5 张', g.hands.r.length === 5, g.hands.r.length);
ok('AP = 2', g.ap === 2);

console.log('\n=== 小兵走法 / 河界 ===');
{
  const st = bare();
  const p4 = put(st, 'r', 'pawn', 4, 5);
  const p3 = put(st, 'r', 'pawn', 3, 5);
  const p5 = put(st, 'r', 'pawn', 5, 5);
  ok('列4 的小兵不能过河 (4,5)->(4,6)', !has(E.legalMoves(st, p4), 4, 6));
  ok('列3 的小兵可以过桥 (3,5)->(3,6)', has(E.legalMoves(st, p3), 3, 6));
  ok('列5 的小兵可以过桥 (5,5)->(5,6)', has(E.legalMoves(st, p5), 5, 6));
}
{
  const st = bare();
  const p = put(st, 'r', 'pawn', 5, 1);
  const ms = E.legalMoves(st, p);
  ok('底线小兵可走 1 格 (5,2)', has(ms, 5, 2));
  ok('底线小兵可走 2 格 (5,3)', has(ms, 5, 3));
  ok('未过河不能横走 (4,1)', !has(ms, 4, 1));
}
{
  const st = bare();
  const p = put(st, 'r', 'pawn', 5, 4);
  const ms = E.legalMoves(st, p);
  ok('非底线小兵不能走 2 格', !has(ms, 5, 6) && has(ms, 5, 5));
}
{
  const st = bare();
  const p = put(st, 'r', 'pawn', 5, 1);
  put(st, 'r', 'pawn', 5, 2);
  const ms = E.legalMoves(st, p);
  ok('前方有子时不能走 1 格', !has(ms, 5, 2));
  ok('前方有子时不能走 2 格', !has(ms, 5, 3));
}
{
  const st = bare();
  const p = put(st, 'r', 'pawn', 7, 7);   // 已过河
  const ms = E.legalMoves(st, p);
  ok('过河小兵可前/左/右', has(ms, 7, 8) && has(ms, 6, 7) && has(ms, 8, 7));
  ok('过河小兵不能后退', !has(ms, 7, 6));
}
{
  const st = bare();
  const p = put(st, 'b', 'pawn', 7, 4);   // 黑卒已过河
  const ms = E.legalMoves(st, p);
  ok('黑卒过河后可横走', has(ms, 6, 4) && has(ms, 8, 4));
  ok('黑卒向前是行号减小', has(ms, 7, 3));
}

console.log('\n=== 车 / 炮 / 马 ===');
{
  const st = bare();
  const ch = put(st, 'r', 'chariot', 4, 3, 'chariot');
  const ms = E.legalMoves(st, ch);
  ok('列4 的战车不能冲过河 (4,7)', !has(ms, 4, 7));
  ok('列4 的战车可走到河边 (4,5)', has(ms, 4, 5));
}
{
  const st = bare();
  const ch = put(st, 'r', 'chariot', 3, 3, 'chariot');
  const ms = E.legalMoves(st, ch);
  ok('列3 的战车可以过桥到 (3,7)', has(ms, 3, 7));
  ok('列3 的战车可以过桥到 (3,10)', has(ms, 3, 10));
}
{
  const st = bare();
  E.addEffect(st, { type: 'bridge_broken', col: 3, left: 3, by: 'b' });
  const ch = put(st, 'r', 'chariot', 3, 3, 'chariot');
  ok('断桥后战车不能过河', !has(E.legalMoves(st, ch), 3, 7));
  E.addEffect(st, { type: 'bridge_temp', col: 3, left: 2, by: 'r' });
  ok('浮桥恢复通行', has(E.legalMoves(st, ch), 3, 7));
}
{
  const st = bare();
  const ca = put(st, 'r', 'cannon', 5, 1, 'cannon');
  put(st, 'r', 'pawn', 5, 3);                    // 炮架（己方）
  const en = put(st, 'b', 'pawn', 5, 5);
  const ms = E.legalMoves(st, ca);
  ok('炮不能走到炮架格 (5,3)', !has(ms, 5, 3));
  ok('炮可以走到 (5,2)', has(ms, 5, 2));
  ok('炮不能越过炮架落空 (5,4)', !has(ms, 5, 4));
  const cap = mv(ms, 5, 5);
  ok('炮隔一子可吃 (5,5)', !!cap && cap.cap === en.id);
}
{
  const st = bare();
  const ca = put(st, 'r', 'cannon', 5, 1, 'cannon');
  put(st, 'b', 'pawn', 5, 3);                    // 炮架
  const t1 = put(st, 'b', 'pawn', 5, 4);         // 炮架后的第一个子 -> 可吃
  put(st, 'b', 'pawn', 5, 5);                    // 更远一个 -> 不可吃
  const ms = E.legalMoves(st, ca);
  ok('炮可吃炮架后的第一个子 (5,4)', (mv(ms, 5, 4) || {}).cap === t1.id);
  ok('炮不能吃更远的第二个子 (5,5)', !has(ms, 5, 5));
}
{
  const st = bare();
  const h = put(st, 'r', 'horse', 5, 5, 'horse');
  const ms = E.legalMoves(st, h);
  ok('骑兵可跃河 (4,7)', has(ms, 4, 7));
  ok('骑兵可跃河 (6,7)', has(ms, 6, 7));
  ok('骑兵 8 个方向', ms.length === 8, ms.length);
}
{
  const st = bare();
  const h = put(st, 'r', 'horse', 5, 5, 'horse');
  put(st, 'b', 'pawn', 5, 6);                    // 蹩马腿
  const ms = E.legalMoves(st, h);
  ok('蹩马腿：向上两路被封', !has(ms, 4, 7) && !has(ms, 6, 7));
  ok('其余方向仍可走', has(ms, 3, 4) || has(ms, 3, 6));
}

console.log('\n=== 主将九宫 ===');
{
  const st = bare();
  const k = put(st, 'r', 'king', 5, 2);
  const ms = E.legalMoves(st, k);
  ok('帅在中心有 4 个走法', ms.length === 4, ms.length);
  ok('帅不能离开九宫 (5,4)', !has(ms, 5, 4));
}
{
  const st = bare();
  const k = put(st, 'r', 'king', 4, 1);
  const ms = E.legalMoves(st, k);
  ok('帅在角上不能出九宫 (3,1)', !has(ms, 3, 1));
  ok('帅在角上可走到 (5,1)', has(ms, 5, 1));
}

console.log('\n=== 部署区 ===');
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  const cells = E.deployCells(st, 'r');
  ok('红帅起始部署区 11 格', cells.length === 11, cells.length);
  ok('不含过河格', cells.every(x => x.r <= 5));
  ok('含 (5,4) 但不含 (5,5)', has(cells, 5, 4) && !has(cells, 5, 5));
  const kp = E.pieceAt(st, 5, 2);
  kp.c = 5; kp.r = 4;
  const cells2 = E.deployCells(st, 'r');
  ok('主将前压到 (5,4) 后部署区跟着推进（含 (5,5)）', has(cells2, 5, 5));
  ok('但部署区仍不过河（不含 (5,6)）', !has(cells2, 5, 6));
}

console.log('\n=== 吃子 / 胜负 ===');
{
  const st = bare();
  const ch = put(st, 'r', 'chariot', 5, 1, 'chariot');
  const k = put(st, 'b', 'king', 5, 9);
  ok('战车可在列5 直取 (5,9)', has(E.legalMoves(st, ch), 5, 9));
  E.doMove(st, ch.id, { c: 5, r: 9, cap: k.id });
  ok('吃掉主将后判红方胜', st.winner === 'r', st.winner);
  ok('主将已从盘上移除', !E.findPiece(st, k.id));
}
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  const ch = put(st, 'b', 'chariot', 5, 9, 'chariot');
  st.turn = 'b';
  E.addEffect(st, { type: 'shield', owner: 'r', left: 1, by: 'r' });
  ok('空城计期间不能吃主将', !has(E.legalMoves(st, ch), 5, 2));
  st.effects = [];
  ok('空城计失效后可以吃', has(E.legalMoves(st, ch), 5, 2));
}
{
  const st = bare();
  const a = put(st, 'r', 'pawn', 1, 1);
  put(st, 'r', 'pawn', 1, 2);
  const ms = E.legalMoves(st, a);
  ok('前方是己方单位：不能走 1 格', !has(ms, 1, 2));
  ok('前方是己方单位：不能走 2 格', !has(ms, 1, 3));
  ok('不能横向吃己方单位', !has(ms, 2, 1));
}

console.log('\n=== 锦囊目标筛选 ===');
{
  const st = bare();
  put(st, 'r', 'pawn', 4, 4);                        // 己方单位
  const near = put(st, 'b', 'pawn', 5, 5);           // 与己方相邻（对角）
  const far = put(st, 'b', 'pawn', 9, 9);            // 不相邻
  const ek = put(st, 'b', 'king', 4, 5);             // 相邻但是主将
  const ids = E.fireTargets(st, 'r').map(p => p.id);
  ok('火攻：包含对角相邻的敌方单位', ids.indexOf(near.id) >= 0);
  ok('火攻：不包含不相邻的单位', ids.indexOf(far.id) < 0);
  ok('火攻：不包含主将', ids.indexOf(ek.id) < 0);
}
{
  const st = bare();
  const t = put(st, 'b', 'pawn', 5, 5);
  const list = E.shoveTargets(st, 'r');
  const item = list.find(x => x.piece.id === t.id);
  ok('声东击西：能找到目标', !!item);
  ok('声东击西：不能推到河对岸 (5,6)', !item.cells.some(x => x.c === 5 && x.r === 6));
  ok('声东击西：可推到同侧 (4,4)', item.cells.some(x => x.c === 4 && x.r === 4));
}
{
  const st = bare();
  put(st, 'r', 'pawn', 5, 1);
  put(st, 'r', 'pawn', 6, 1);
  put(st, 'b', 'pawn', 5, 7);
  ok('移形换位：可选中己方全部单位', E.swapTargets(st, 'r').length === 2);
}

console.log('\n=== 持续效果：统一回合计数 ===');
{
  const st = bare();
  const p = put(st, 'r', 'pawn', 5, 1);
  E.addEffect(st, { type: 'root', pieceId: p.id, left: 2, by: 'b' });
  ok('绊马索：不能移动', E.legalMoves(st, p).length === 0);
  st.effects = [];
  ok('解除后可移动', E.legalMoves(st, p).length > 0);
}
{
  const st = bare();
  const p5 = put(st, 'r', 'pawn', 5, 5);
  const p3 = put(st, 'r', 'pawn', 3, 3);
  E.addEffect(st, { type: 'flood', left: 1, by: 'r' });
  ok('水淹：行5 的小兵不能动', E.legalMoves(st, p5).length === 0);
  ok('水淹：行3 的小兵不受影响', E.legalMoves(st, p3).length > 0);
}
{
  // 计数规则：只在「打出者自己的回合开始」时减 1，对手回合不衰减
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  put(st, 'b', 'king', 5, 9);
  put(st, 'r', 'pawn', 5, 1);
  st.turn = 'r'; st.ap = 2;
  E.addEffect(st, { type: 'bridge_broken', col: 5, left: 2, by: 'r' });
  E.addEffect(st, { type: 'bridge_temp', col: 5, left: 2, by: 'r' });
  E.addEffect(st, { type: 'shield', owner: 'r', left: 1, by: 'r' });
  E.addEffect(st, { type: 'flood', left: 1, by: 'r' });
  const leftOf = (t) => { const e = st.effects.find(x => x.type === t); return e ? e.left : 0; };
  E.endTurn(st);
  ok('换手到黑方', st.turn === 'b');
  ok('黑方 AP 重置为 2', st.ap === 2);
  ok('对手回合里，红方留下的效果不衰减', leftOf('bridge_broken') === 2 && leftOf('bridge_temp') === 2);
  E.endTurn(st);
  ok('换回红方', st.turn === 'r');
  ok('空城计（1 回合）在红方回合开始时失效', !E.isShielded(st, 'r'));
  ok('水淹（1 回合）在红方回合开始时失效', !E.isFlooded(st, 5));
  ok('断桥/浮桥（2 回合）各剩 1 回合', leftOf('bridge_broken') === 1 && leftOf('bridge_temp') === 1);
  E.endTurn(st); E.endTurn(st);
  ok('再一轮后断桥与浮桥同时消失', leftOf('bridge_broken') === 0 && leftOf('bridge_temp') === 0);
}
{
  // 语义验证：绊马索 N=2 就是「影响对手接下来 2 个回合」
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  put(st, 'b', 'king', 5, 9);
  const bh = put(st, 'b', 'horse', 5, 8, 'horse');
  st.turn = 'r';
  E.addEffect(st, { type: 'root', pieceId: bh.id, left: 2, by: 'r' });
  E.endTurn(st);
  ok('黑方第 1 个回合：马被缚', E.legalMoves(st, bh).length === 0);
  E.endTurn(st); E.endTurn(st);
  ok('黑方第 2 个回合：马仍被缚', E.legalMoves(st, bh).length === 0);
  E.endTurn(st); E.endTurn(st);
  ok('黑方第 3 个回合：已挣脱', E.legalMoves(st, bh).length > 0);
}
{
  // 断桥有时限：3 回合 = 恰好拦住对手接下来的 3 个回合，第 4 个回合桥自己通
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  put(st, 'b', 'king', 5, 9);
  const rp = put(st, 'r', 'pawn', 3, 5);
  st.turn = 'r';
  E.addEffect(st, { type: 'bridge_broken', col: 3, left: 3, by: 'r' });
  ok('打出当回合：桥是断的', !has(E.legalMoves(st, rp), 3, 6));
  const blockedOnBlackTurn = [];
  for (let i = 0; i < 8; i++) {
    E.endTurn(st);
    if (st.turn === 'b') blockedOnBlackTurn.push(!has(E.legalMoves(st, rp), 3, 6));
  }
  ok('断桥 3 回合 = 对手连续 3 个回合过不去，第 4 个回合恢复',
    JSON.stringify(blockedOnBlackTurn) === JSON.stringify([true, true, true, false]),
    JSON.stringify(blockedOnBlackTurn));
}
{
  // 目标阵亡时，挂在它身上的持续效果一起清掉
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  put(st, 'b', 'king', 5, 9);
  const bh = put(st, 'b', 'horse', 5, 8, 'horse');
  E.addEffect(st, { type: 'root', pieceId: bh.id, left: 2, by: 'r' });
  E.killByFire(st, bh);
  ok('被缚单位阵亡后，效果不再残留在面板上', !E.hasEffect(st, 'root', e => e.pieceId === bh.id));
}
{
  ok('断桥 = 3 回合', E.SPELL_DUR['断桥'] === 3);
  ok('浮桥 = 2 回合', E.SPELL_DUR['浮桥'] === 2);
  ok('绊马索 = 2 回合', E.SPELL_DUR['绊马索'] === 2);
  ok('水淹 = 1 回合', E.SPELL_DUR['水淹'] === 1);
  ok('空城计 = 1 回合', E.SPELL_DUR['空城计'] === 1);
  ok('即时锦囊的持续回合数为 0', E.SPELL_DUR['探马'] === 0 && E.SPELL_DUR['增援'] === 0 && E.SPELL_DUR['火攻'] === 0);
}

console.log('\n=== 动作消耗 ===');
{
  const st = bare();
  st.deck = [{ id: 'z1', kind: 'pawn' }];
  st.hands.r = [{ id: 'h1', kind: 'pawn' }, { id: 'h2', kind: 'gear', gear: 'horse' }];
  put(st, 'r', 'king', 5, 2);
  const p = put(st, 'r', 'pawn', 5, 1);
  ok('部署扣 1 AP', E.doDeploy(st, 'r', 0, 5, 3) && st.ap === 1);
  const p2 = st.pieces.find(x => x.kind === 'pawn' && x.c === 5 && x.r === 3);
  ok('装备扣 1 AP', E.doEquip(st, 'r', 0, p2.id) && st.ap === 0);
  ok('装备后成为骑兵', p2.gear === 'horse' && E.gearKind(p2) === 'horse');
  ok('AP 用尽后不能移动', E.doMove(st, p2.id, { c: 5, r: 4, cap: null }) === false);
}

console.log('\n=== 人口上限 ===');
{
  const g2 = E.newGame('full');
  ok('默认人口上限 8', g2.popCap === 8);
  ok('主将 0 人口', E.popCost({ kind: 'king' }) === 0);
  ok('小兵 1 人口', E.popCost({ kind: 'pawn', gear: null }) === 1);
  ok('骑兵 2 人口', E.popCost({ kind: 'pawn', gear: 'horse' }) === 2);
  ok('战车 2 人口', E.popCost({ kind: 'pawn', gear: 'chariot' }) === 2);
  ok('炮兵 2 人口', E.popCost({ kind: 'pawn', gear: 'cannon' }) === 2);
  ok('开局两个主将 = 0 人口', E.popUsed(g2, 'r') === 0 && E.popUsed(g2, 'b') === 0);
  [[1, 5], [2, 5], [3, 5]].forEach(([c, r]) => E.doSetupDeploy(g2, 'r', c, r));
  ok('开局布阵 3 小兵 = 3 人口', E.popUsed(g2, 'r') === 3);
}
{
  const st = bare();
  st.popCap = 3;
  st.deck = [{ id: 'a', kind: 'pawn' }, { id: 'b', kind: 'pawn' }];
  st.hands.r = [{ id: 'h1', kind: 'pawn' }, { id: 'h2', kind: 'pawn' }];
  st.ap = 2;
  put(st, 'r', 'king', 5, 2);
  put(st, 'r', 'pawn', 5, 1);
  put(st, 'r', 'pawn', 4, 1);
  put(st, 'r', 'pawn', 6, 1);
  ok('满编 3/3 时不能部署', E.doDeploy(st, 'r', 0, 5, 3) === false);
  ok('被拦下时不扣 AP', st.ap === 2);
  const victim = st.pieces.find(p => p.kind === 'pawn');
  ok('解散扣 1 AP 并释放人口', E.doDisband(st, 'r', victim.id) === true && st.ap === 1 && E.popUsed(st, 'r') === 2);
  ok('腾出人口后可以部署', E.doDeploy(st, 'r', 0, 5, 3) === true && E.popUsed(st, 'r') === 3);
}
{
  const st = bare();
  st.popCap = 2;
  st.hands.r = [{ id: 'h1', kind: 'gear', gear: 'horse' }];
  st.ap = 2;
  put(st, 'r', 'king', 5, 2);
  const p = put(st, 'r', 'pawn', 5, 1);
  ok('1/2 人口时可以装备成骑兵', E.doEquip(st, 'r', 0, p.id) === true && E.popUsed(st, 'r') === 2);
}
{
  const st = bare();
  st.popCap = 2;
  st.hands.r = [{ id: 'h1', kind: 'gear', gear: 'horse' }];
  st.ap = 2;
  put(st, 'r', 'king', 5, 2);
  const p = put(st, 'r', 'pawn', 5, 1);
  put(st, 'r', 'pawn', 4, 1);
  ok('满编 2/2 时不能装备（装备要额外 1 人口）', E.doEquip(st, 'r', 0, p.id) === false);
  E.doDisband(st, 'r', st.pieces[2].id);
  ok('腾出人口后可以装备', E.doEquip(st, 'r', 0, p.id) === true && p.gear === 'horse');
}
{
  // 陷阱场景：满编 8 个小兵 -> 永远无法升级，必须靠解散
  const st = bare();
  st.popCap = 8;
  st.hands.r = [{ id: 'h1', kind: 'gear', gear: 'chariot' }];
  st.ap = 2;
  put(st, 'r', 'king', 5, 2);
  for (let i = 0; i < 8; i++) put(st, 'r', 'pawn', i + 1, 4);
  ok('8/8 满编时不能装备（会被卡死）', E.doEquip(st, 'r', 0, st.pieces[1].id) === false);
  E.doDisband(st, 'r', st.pieces[8].id);
  ok('解散 1 个后就能升级成战车', E.doEquip(st, 'r', 0, st.pieces[1].id) === true && E.popUsed(st, 'r') === 8);
}
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  const a = put(st, 'r', 'pawn', 5, 1);
  a.gear = 'horse';
  ok('主将 + 骑兵 = 2 人口', E.popUsed(st, 'r') === 2);
  ok('解散主将被禁止', E.doDisband(st, 'r', st.pieces[0].id) === false);
}
{
  const st = bare();
  const ch = put(st, 'r', 'chariot', 5, 1, 'chariot');
  const bc = put(st, 'b', 'chariot', 5, 5, 'chariot');
  ok('黑方战车 = 2 人口', E.popUsed(st, 'b') === 2);
  E.doMove(st, ch.id, { c: 5, r: 5, cap: bc.id });
  ok('吃子后对方人口被释放', E.popUsed(st, 'b') === 0);
}
{
  const st = bare();
  st.popCap = 8;
  put(st, 'r', 'king', 5, 2);
  for (let i = 0; i < 8; i++) put(st, 'r', 'pawn', i + 1, 4);
  ok('popLeft 在满编时为 -1', E.popLeft(st, 'r', 1) === -1);
  ok('popFree 反映剩余人口', E.popFree(st, 'r') === 0);
}

console.log('\n=== 士 ===');
{
  const st = bare();
  const a = put(st, 'r', 'advisor', 5, 2);
  const ms = E.legalMoves(st, a);
  ok('士在九宫中心有 4 个走法（四个角）', ms.length === 4, ms.length);
  ok('士不能直走 (5,3)/(5,1)', !has(ms, 5, 3) && !has(ms, 5, 1));
}
{
  const st = bare();
  const a = put(st, 'r', 'advisor', 4, 1);
  const ms = E.legalMoves(st, a);
  ok('士在角上只能回中心 (5,2)', ms.length === 1 && has(ms, 5, 2));
  ok('士不能出九宫 (3,1)', !has(ms, 3, 1));
}
{
  const st = bare();
  const a = put(st, 'b', 'advisor', 4, 10);
  const ms = E.legalMoves(st, a);
  ok('黑士同样只能在自己的九宫', ms.length === 1 && has(ms, 5, 9));
}
{
  const st = bare();
  const a = put(st, 'r', 'advisor', 5, 2);
  const en = put(st, 'b', 'pawn', 4, 1);
  ok('士可以吃闯入九宫的敌人', (mv(E.legalMoves(st, a), 4, 1) || {}).cap === en.id);
}
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  const cells = E.deployCells(st, 'r', 'advisor');
  ok('士的部署区 = 九宫内 8 个空点', cells.length === 8, cells.length);
  ok('士不能部署在九宫外 (5,4)', !has(cells, 5, 4));
}
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  ok('小兵的部署区仍是 11 格', E.deployCells(st, 'r', 'pawn').length === 11);
  ok('象的部署区与小兵相同（11 格）', E.deployCells(st, 'r', 'elephant').length === 11);
}

console.log('\n=== 象 ===');
{
  const st = bare();
  const e = put(st, 'r', 'elephant', 3, 1);
  const ms = E.legalMoves(st, e);
  ok('象走田：(1,3) 与 (5,3)', has(ms, 1, 3) && has(ms, 5, 3));
  ok('象在底线只有 2 个走法', ms.length === 2, ms.length);
}
{
  const st = bare();
  const e = put(st, 'r', 'elephant', 5, 5);
  const ms = E.legalMoves(st, e);
  ok('象永不过河 (3,7)/(7,7) 非法', !has(ms, 3, 7) && !has(ms, 7, 7));
  ok('象在己方半场内仍可走田', has(ms, 3, 3) && has(ms, 7, 3));
}
{
  const st = bare();
  const e = put(st, 'r', 'elephant', 3, 1);
  put(st, 'b', 'pawn', 2, 2);                       // 象眼
  const ms = E.legalMoves(st, e);
  ok('塞象眼：不能走到 (1,3)', !has(ms, 1, 3));
  ok('另一侧不受影响 (5,3)', has(ms, 5, 3));
}
{
  const st = bare();
  E.addEffect(st, { type: 'bridge_broken', col: 3, left: 3, by: 'b' });
  const e = put(st, 'r', 'elephant', 3, 3);
  ok('桥断了象照走（象不认桥，它本来就不过河）', has(E.legalMoves(st, e), 1, 1));
}
{
  const st = bare();
  const e = put(st, 'b', 'elephant', 5, 6);
  const ms = E.legalMoves(st, e);
  ok('黑象不过河到行 4', !has(ms, 3, 4) && !has(ms, 7, 4));
  ok('黑象可在自己半场走到行 8', has(ms, 3, 8) && has(ms, 7, 8));
}
{
  const st = bare();
  ok('士 2 人口', E.popCost({ kind: 'advisor', gear: null }) === 2);
  ok('象 2 人口', E.popCost({ kind: 'elephant', gear: null }) === 2);
  ok('士牌要 2 人口', E.cardPopCost({ kind: 'advisor' }) === 2);
  ok('象牌要 2 人口', E.cardPopCost({ kind: 'elephant' }) === 2);
  ok('小兵牌只要 1 人口', E.cardPopCost({ kind: 'pawn' }) === 1);
}

console.log('\n=== 士 · 护驾 ===');
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  const adv = put(st, 'r', 'advisor', 4, 1);
  const ch = put(st, 'b', 'chariot', 5, 9, 'chariot');
  st.turn = 'b'; st.ap = 2;
  ok('有士时，战车仍可走到主将格（会被护驾拦下）', has(E.legalMoves(st, ch), 5, 2));
  E.doMove(st, ch.id, { c: 5, r: 2, cap: E.pieceAt(st, 5, 2).id });
  ok('主将存活', !!E.pieceAt(st, 5, 2) && E.pieceAt(st, 5, 2).kind === 'king');
  ok('士代死', !E.findPiece(st, adv.id));
  ok('没有判胜负', st.winner === null);
  ok('攻击方留在原地没前进', ch.c === 5 && ch.r === 9);
  ok('护驾消耗了 1 AP', st.ap === 1);
  ok('士进了共用弃牌堆', st.discard.some(c => c.kind === 'advisor'));
}
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  put(st, 'r', 'advisor', 4, 1);
  const ch = put(st, 'b', 'chariot', 5, 9, 'chariot');
  st.turn = 'b'; st.ap = 2;
  E.doMove(st, ch.id, { c: 5, r: 2, cap: E.pieceAt(st, 5, 2).id });
  st.ap = 2;
  E.doMove(st, ch.id, { c: 5, r: 2, cap: E.pieceAt(st, 5, 2).id });
  ok('士用完后再吃主将就赢了', st.winner === 'b', st.winner);
}
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  const ch = put(st, 'b', 'chariot', 5, 9, 'chariot');
  st.turn = 'b'; st.ap = 2;
  E.doMove(st, ch.id, { c: 5, r: 2, cap: E.pieceAt(st, 5, 2).id });
  ok('九宫里没有士时主将直接被吃', st.winner === 'b');
}
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  put(st, 'r', 'advisor', 4, 1);
  const ch = put(st, 'b', 'chariot', 5, 9, 'chariot');
  st.turn = 'b'; st.ap = 2; E.addEffect(st, { type: 'shield', owner: 'r', left: 1, by: 'r' });
  ok('空城计优先于护驾：那时根本吃不到主将', !has(E.legalMoves(st, ch), 5, 2));
}
{
  const st = bare();
  put(st, 'r', 'king', 5, 2);
  const a1 = put(st, 'r', 'advisor', 4, 1);
  const a2 = put(st, 'r', 'advisor', 6, 1);
  const ch = put(st, 'b', 'chariot', 5, 9, 'chariot');
  st.turn = 'b'; st.ap = 2;
  E.doMove(st, ch.id, { c: 5, r: 2, cap: E.pieceAt(st, 5, 2).id });
  st.ap = 2;
  E.doMove(st, ch.id, { c: 5, r: 2, cap: E.pieceAt(st, 5, 2).id });
  ok('两个士可以挡两次', !!E.pieceAt(st, 5, 2) && st.winner === null && !E.findPiece(st, a1.id) && !E.findPiece(st, a2.id));
}

console.log('\n=== 象 · 堵桥 ===');
{
  const st = bare();
  put(st, 'b', 'elephant', 3, 6);                    // 黑象站在黑方桥头
  const pawn = put(st, 'r', 'pawn', 3, 5);
  ok('象堵桥：红兵不能吃掉它', !has(E.legalMoves(st, pawn), 3, 6));
}
{
  const st = bare();
  put(st, 'b', 'elephant', 3, 6);
  const ch = put(st, 'r', 'chariot', 3, 3, 'chariot');
  const ms = E.legalMoves(st, ch);
  ok('战车沿列3 过不了河（到不了 (3,6)）', !has(ms, 3, 6));
  ok('战车仍能走到己方桥头 (3,5)', has(ms, 3, 5));
}
{
  const st = bare();
  put(st, 'b', 'elephant', 3, 6);
  const ch = put(st, 'r', 'chariot', 5, 3, 'chariot');
  ok('别的桥不受影响：列5 战车可过河到 (5,8)', has(E.legalMoves(st, ch), 5, 8));
}
{
  const st = bare();
  put(st, 'r', 'elephant', 3, 5);                    // 红象站在红方桥头
  const bp = put(st, 'b', 'pawn', 3, 6);
  ok('红象堵桥：黑卒不能过河到 (3,5)', !has(E.legalMoves(st, bp), 3, 5));
}
{
  const st = bare();
  const el = put(st, 'b', 'elephant', 3, 6);
  const h = put(st, 'r', 'horse', 2, 4, 'horse');
  ok('骑兵不受阻拦：马可跃河吃掉堵桥的象', (mv(E.legalMoves(st, h), 3, 6) || {}).cap === el.id);
}
{
  const st = bare();
  const el = put(st, 'b', 'elephant', 3, 6);
  const ch = put(st, 'r', 'chariot', 5, 6, 'chariot');   // 已从别的桥过河
  ok('从侧面（同行不跨河）可以吃它', (mv(E.legalMoves(st, ch), 3, 6) || {}).cap === el.id);
}
{
  const st = bare();
  put(st, 'b', 'elephant', 5, 8);                    // 象在自家半场，但不在桥头
  const ch = put(st, 'r', 'chariot', 5, 3, 'chariot');
  ok('象不在桥头就不堵桥：红车可过河到 (5,7)', has(E.legalMoves(st, ch), 5, 7));
}
{
  const st = bare();
  put(st, 'r', 'elephant', 3, 5);                    // 己方象占着己方桥头
  const rp = put(st, 'r', 'pawn', 3, 3);
  ok('己方象占桥头只是普通占位（自己人也过不去，但不会被"堵桥"规则禁止吃子）',
    !has(E.legalMoves(st, rp), 3, 5) && E.popCost(E.pieceAt(st, 3, 5)) === 2);
}
{
  const st = bare();
  put(st, 'b', 'elephant', 3, 6);
  E.addEffect(st, { type: 'bridge_broken', col: 3, left: 3, by: 'b' });
  const pawn2 = put(st, 'r', 'pawn', 3, 5);
  ok('象堵 + 断桥 = 双重封锁', !has(E.legalMoves(st, pawn2), 3, 6));
}

console.log('\n=== 士 / 象 数量上限 ===');
{
  const st = bare();
  st.specCap = 2;
  put(st, 'r', 'king', 5, 2);
  st.hands.r = [{ id: 'a1', kind: 'advisor' }, { id: 'a2', kind: 'advisor' }, { id: 'a3', kind: 'advisor' }];
  st.ap = 6;
  ok('第 1 个士可以部署', E.doDeploy(st, 'r', 0, 4, 1) === true);
  ok('第 2 个士可以部署', E.doDeploy(st, 'r', 0, 6, 1) === true);
  ok('第 3 个士被拦下', E.doDeploy(st, 'r', 0, 5, 3) === false);
  ok('被拦下时不扣 AP', st.ap === 4, st.ap);
  ok('场上士数 = 2', E.countOnBoard(st, 'r', 'advisor') === 2);
  ok('specLeft 归零', E.specLeft(st, 'r', 'advisor') === 0);
}
{
  const st = bare();
  st.specCap = 2;
  put(st, 'r', 'king', 5, 2);
  st.hands.r = [{ id: 'e1', kind: 'elephant' }, { id: 'e2', kind: 'elephant' }, { id: 'e3', kind: 'elephant' }];
  st.ap = 8;
  E.doDeploy(st, 'r', 0, 4, 1);
  E.doDeploy(st, 'r', 0, 6, 1);
  ok('第 3 个象被拦下', E.doDeploy(st, 'r', 0, 5, 1) === false);
  ok('场上象数 = 2', E.countOnBoard(st, 'r', 'elephant') === 2);
}
{
  const st = bare();
  st.specCap = 1;
  put(st, 'r', 'king', 5, 2);
  st.hands.r = [{ id: 'a1', kind: 'advisor' }, { id: 'a2', kind: 'advisor' }];
  st.ap = 4;
  ok('上限 1：第 1 个士可放', E.doDeploy(st, 'r', 0, 4, 1) === true);
  ok('上限 1：第 2 个士被拦下', E.doDeploy(st, 'r', 0, 6, 1) === false);
}
{
  const st = bare();
  st.specCap = 1;
  put(st, 'r', 'king', 5, 2);
  st.hands.r = [{ id: 'p1', kind: 'pawn' }, { id: 'p2', kind: 'pawn' }, { id: 'p3', kind: 'pawn' }];
  st.ap = 6;
  ok('小兵完全不受这个上限影响', E.doDeploy(st, 'r', 0, 5, 1) && E.doDeploy(st, 'r', 0, 4, 1) && E.doDeploy(st, 'r', 0, 6, 1));
}
{
  const st = bare();
  st.specCap = 2;
  put(st, 'r', 'king', 5, 2);
  put(st, 'b', 'king', 5, 9);
  put(st, 'r', 'advisor', 4, 1);
  put(st, 'r', 'advisor', 6, 1);
  ok('红方已满 2 个士', E.specLeft(st, 'r', 'advisor') === 0);
  ok('不影响黑方（上限是各算各的）', E.specLeft(st, 'b', 'advisor') === 2);
  ok('红方象的名额也没被占用', E.specLeft(st, 'r', 'elephant') === 2);
}
{
  // UI 链路：满编时点牌应被拦下
  const st = E.newGameForTest('quick', 12, 2), ui = E.uiRef();
  [[1, 5], [2, 5], [3, 5]].forEach(([c, r]) => E.handleClick(null, c, r));
  [[1, 6], [2, 6], [3, 6]].forEach(([c, r]) => E.handleClick(null, c, r));
  st.turn = 'r'; st.ap = 4;
  put(st, 'r', 'advisor', 4, 1);
  put(st, 'r', 'advisor', 6, 1);
  st.hands.r = [{ id: 'a9', kind: 'advisor' }];
  E.cardClick('r', 0);
  ok('满编时点士牌不会进入待部署状态', ui.pending === null);
  ok('满编时没扣 AP', st.ap === 4);
}
{
  // 阵亡后名额释放
  const st = bare();
  st.specCap = 2;
  put(st, 'r', 'king', 5, 2);
  const a1 = put(st, 'r', 'advisor', 4, 1);
  put(st, 'r', 'advisor', 6, 1);
  st.hands.r = [{ id: 'a4', kind: 'advisor' }];
  st.ap = 4;
  ok('满编时不能放第 3 个', E.doDeploy(st, 'r', 0, 5, 3) === false);
  E.doDisband(st, 'r', a1.id);
  ok('解散一个之后名额释放', E.doDeploy(st, 'r', 0, 5, 3) === true && E.countOnBoard(st, 'r', 'advisor') === 2);
}

console.log('\n=== 棋盘渲染 ===');
function tagCheck(s) {
  var stack = [], m;
  var re = /<(\/?)([a-zA-Z][\w:-]*)([^>]*?)(\/?)>/g;
  while ((m = re.exec(s))) {
    var closing = m[1] === '/', name = m[2], self = m[4] === '/';
    if (self) continue;
    if (closing) { if (stack.pop() !== name) return '标签不匹配: ' + m[0]; }
    else stack.push(name);
  }
  return stack.length ? '未闭合: ' + stack.join(',') : null;
}
{
  const st2 = E.newGame('quick');
  const U = { selected: null, moves: [], pending: null, targetCells: [], targetPieces: [] };
  const svg = E.boardSVG(st2, U);
  ok('棋盘 SVG 标签闭合正确', tagCheck(svg) === null, tagCheck(svg));
  ok('90 个命中格', (svg.match(/class="hit"/g) || []).length === 90, (svg.match(/class="hit"/g) || []).length);
  ok('命中格在棋子之前（点得到棋子）', svg.indexOf('class="hit"') < svg.indexOf('data-pid='));
  ok('三座桥都在', (svg.match(/data-bridge=/g) || []).length === 3);
  ok('两个主将都画出来了', (svg.match(/data-pid=/g) || []).length === 2);
}
{
  const st3 = E.newGame('quick');
  st3.pieces = [];
  st3.phase = 'play';
  const p = { id: 'zz', owner: 'r', kind: 'pawn', gear: null, card: { id: 'q', kind: 'pawn' }, gearCard: null, c: 5, r: 5 };
  st3.pieces.push(p);
  const U2 = { selected: 'zz', moves: E.legalMoves(st3, p), pending: null, targetCells: [], targetPieces: [] };
  const svg2 = E.boardSVG(st3, U2);
  ok('选中棋子时高亮渲染正常', tagCheck(svg2) === null && U2.moves.length === 1 && svg2.indexOf('stroke-width="4"') > 0);
}

console.log('\n=== 交互链路（模拟点卡 + 点格，UI 层） ===');
function setupViaClicks(mode, cap) {
  const st = E.newGameForTest(mode, cap);
  [[1, 5], [2, 5], [3, 5]].forEach(([c, r]) => E.handleClick(null, c, r));
  [[1, 6], [2, 6], [3, 6]].forEach(([c, r]) => E.handleClick(null, c, r));
  return st;
}
{
  const st = E.newGameForTest('quick', 8);
  [[1, 5], [2, 5], [3, 5]].forEach(([c, r]) => E.handleClick(null, c, r));
  ok('点格子能放下红方 3 个小兵', E.popUsed(st, 'r') === 3);
  [[1, 6], [2, 6], [3, 6]].forEach(([c, r]) => E.handleClick(null, c, r));
  ok('布阵完成并进入对局', st.phase === 'play' && st.turn === 'r');
}
{
  const st = setupViaClicks('quick', 8), ui = E.uiRef();
  st.hands.r = [{ id: 'z1', kind: 'pawn' }];
  st.ap = 2;
  E.cardClick('r', 0);
  ok('点兵牌进入待部署状态', !!ui.pending && ui.pending.type === 'deploy');
  ok('待部署状态高亮了格子', ui.targetCells.length > 0);
  const [c, r] = ui.targetCells[0].split(',').map(Number);
  E.handleClick(null, c, r);
  ok('点格子真的把小兵放上去了', st.pieces.filter(p => p.owner === 'r' && p.kind === 'pawn' && p.c === c && p.r === r).length === 1);
  ok('部署扣了 1 AP', st.ap === 1);
  ok('部署后清空待选状态', ui.pending === null);
  ok('手牌少了一张', st.hands.r.length === 0);
}
{
  const st = setupViaClicks('quick', 8), ui = E.uiRef();
  const target = E.pieceAt(st, 1, 5);
  st.hands.r = [{ id: 'g1', kind: 'gear', gear: 'chariot' }];
  st.ap = 2;
  E.cardClick('r', 0);
  ok('点装备牌进入待装备状态', !!ui.pending && ui.pending.type === 'equip');
  ok('待装备状态高亮了小兵', ui.targetPieces.indexOf(target.id) >= 0);
  E.handleClick(target.id, target.c, target.r);
  ok('点小兵真的装备上了', target.gear === 'chariot');
  ok('装备后人口 3 -> 4', E.popUsed(st, 'r') === 4);
  ok('装备扣了 1 AP', st.ap === 1);
}
{
  const st = setupViaClicks('quick', 8), ui = E.uiRef();
  st.hands.r = [{ id: 'a1', kind: 'advisor' }];
  st.ap = 2;
  E.cardClick('r', 0);
  ok('点士牌进入待部署状态', !!ui.pending && ui.pending.type === 'deploy');
  ok('士的待部署格全部落在九宫内',
    ui.targetCells.length > 0 && ui.targetCells.every(k => {
      const [c, r] = k.split(',').map(Number); return E.inPalace('r', c, r);
    }));
  const [c, r] = ui.targetCells[0].split(',').map(Number);
  E.handleClick(null, c, r);
  const adv = st.pieces.find(p => p.kind === 'advisor');
  ok('点格子把士放上去了，且它在九宫内', !!adv && E.inPalace('r', adv.c, adv.r));
  ok('士占 2 人口（3 + 2 = 5）', E.popUsed(st, 'r') === 5);
}
{
  const st = setupViaClicks('quick', 8), ui = E.uiRef();
  st.turn = 'r'; st.ap = 2;
  const p = E.pieceAt(st, 3, 5);                    // 列 3 是桥，可以过河
  E.handleClick(p.id, p.c, p.r);
  ok('点自己的棋子会选中它', ui.selected === p.id);
  ok('选中后高亮了合法走法', ui.moves.length > 0, ui.moves.length);
  const m = ui.moves[0];
  E.handleClick(null, m.c, m.r);
  ok('点绿点真的移动了', p.c === m.c && p.r === m.r);
  ok('移动扣了 1 AP', st.ap === 1);
}
{
  const st = setupViaClicks('quick', 8), ui = E.uiRef();
  st.turn = 'r'; st.ap = 2;
  const p = E.pieceAt(st, 1, 5);                    // 列 1 不是桥
  E.handleClick(p.id, p.c, p.r);
  ok('河边非桥列的小兵走不动（点它无高亮）', ui.selected === p.id && ui.moves.length === 0);
}
{
  const st = setupViaClicks('quick', 3), ui = E.uiRef();
  st.turn = 'r'; st.ap = 2;
  st.hands.r = [{ id: 'p9', kind: 'pawn' }];
  E.cardClick('r', 0);
  ok('人口已满时点兵牌不会进入待部署状态', ui.pending === null);
  ok('人口已满时没扣 AP', st.ap === 2);
}
{
  const st = setupViaClicks('quick', 8), ui = E.uiRef();
  st.hands.r = [{ id: 'f1', kind: 'spell', spell: '断桥' }];
  st.ap = 2;
  E.cardClick('r', 0);
  ok('点断桥进入选列状态', !!ui.pending && ui.pending.stepKind === 'column');
  E.handleClick(null, 5, 4);                        // 点列 5 任意一格
  ok('断桥成功（列 5 断，3 回合）',
    E.bridgeStateOf(st, 5) === 'broken' && E.hasEffect(st, 'bridge_broken', e => e.col === 5 && e.left === 3));
  ok('断桥扣了 1 AP', st.ap === 1);
}
{
  const st = setupViaClicks('quick', 8), ui = E.uiRef();
  ok('布阵阶段结束后红方手牌已发好', st.hands.r.length >= 4);
}
{
  // 解散按钮对应的引擎动作
  const st = setupViaClicks('quick', 8);
  st.turn = 'r'; st.ap = 2;
  const p = E.pieceAt(st, 1, 5);
  ok('解散释放人口', E.doDisband(st, 'r', p.id) === true && E.popUsed(st, 'r') === 2);
}

console.log('\n----------------------------------------');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
