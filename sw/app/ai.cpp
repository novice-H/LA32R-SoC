#include "ai.h"

namespace ai {
namespace {

const int INF  = 100000000;
const int DEAD = -50000;   // 无路可走的惩罚
const int WIN  = 10000;    // 合成 2048

// ln(empty) * 2.7 * 256，empty = 0 时给一个很低的哨兵值
const int LN_EMPTY[17] = {
    -100000, 0, 479, 759, 958, 1112, 1238, 1345, 1437,
    1519, 1592, 1657, 1718, 1773, 1824, 1872, 1916,
};

inline int iabs(int x) { return x < 0 ? -x : x; }

// 取第 line 条线的 4 个格子，顺序为“靠近移动目的端 -> 远离”。
inline void line_idx(int dir, int line, int idx[4]) {
    if (dir == UP) {
        idx[0] = line;      idx[1] = line + 4;
        idx[2] = line + 8;  idx[3] = line + 12;
    } else if (dir == RIGHT) {
        idx[0] = line * 4 + 3; idx[1] = line * 4 + 2;
        idx[2] = line * 4 + 1; idx[3] = line * 4;
    } else if (dir == DOWN) {
        idx[0] = 12 + line; idx[1] = 8 + line;
        idx[2] = 4 + line;  idx[3] = line;
    } else {
        idx[0] = line * 4;     idx[1] = line * 4 + 1;
        idx[2] = line * 4 + 2; idx[3] = line * 4 + 3;
    }
}

// 与 ovolve 的 smoothness() 一致：每块与“该方向上下一个非空格”比较。
inline int smoothness(const uint8_t b[16]) {
    int s = 0;
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            int i = y * 4 + x;
            int v = b[i];
            if (!v) continue;
            for (int k = x + 1; k < 4; k++) {
                if (b[y * 4 + k]) { s -= iabs(v - b[y * 4 + k]); break; }
            }
            for (int k = y + 1; k < 4; k++) {
                if (b[k * 4 + x]) { s -= iabs(v - b[k * 4 + x]); break; }
            }
        }
    }
    return s;
}

// 与 ovolve 的 islands() 等价：没有任何同值邻居的格子计一个“孤岛”。
inline int islands(const uint8_t b[16]) {
    int cnt = 0;
    for (int i = 0; i < 16; i++) {
        int v = b[i];
        if (!v) continue;
        int x = i & 3, y = i >> 2;
        bool conn = false;
        if (x > 0 && b[i - 1] == v) conn = true;
        if (x < 3 && b[i + 1] == v) conn = true;
        if (y > 0 && b[i - 4] == v) conn = true;
        if (y < 3 && b[i + 4] == v) conn = true;
        if (!conn) cnt++;
    }
    return cnt;
}

// 与 ovolve 的 monotonicity2() 一致：按列/行跳过空格，统计四个方向的
// “逆序惩罚”，返回 max(t0,t1) + max(t2,t3)（<= 0，越接近 0 越单调）。
inline int monotonicity2(const uint8_t b[16]) {
    int t[4] = {0, 0, 0, 0};

    for (int x = 0; x < 4; x++) {
        int cur = 0, next = 1;
        while (next < 4) {
            while (next < 4 && !b[next * 4 + x]) next++;
            if (next >= 4) next--;
            int cv = b[cur * 4 + x];
            int nv = b[next * 4 + x];
            if (cv > nv)      t[0] += nv - cv;
            else if (nv > cv) t[1] += cv - nv;
            cur = next;
            next++;
        }
    }

    for (int y = 0; y < 4; y++) {
        int cur = 0, next = 1;
        while (next < 4) {
            while (next < 4 && !b[y * 4 + next]) next++;
            if (next >= 4) next--;
            int cv = b[y * 4 + cur];
            int nv = b[y * 4 + next];
            if (cv > nv)      t[2] += nv - cv;
            else if (nv > cv) t[3] += cv - nv;
            cur = next;
            next++;
        }
    }

    int m0 = t[0] > t[1] ? t[0] : t[1];
    int m1 = t[2] > t[3] ? t[2] : t[3];
    return m0 + m1;
}

inline bool is_win(const uint8_t b[16]) {
    for (int i = 0; i < 16; i++)
        if (b[i] >= 11) return true;
    return false;
}

// ---- 机会节点候选打分的 O(1) 增量实现 ----
// 插入一个格子只会影响：新格子自身的 smoothness 贡献、左边/上边最近非空格
// 的“下一个非空”目标，以及新格子与四邻的 islands 计数。

inline int next_right(const uint8_t b[16], int i) {
    int y = i >> 2, x = i & 3;
    for (int k = x + 1; k < 4; k++)
        if (b[y * 4 + k]) return y * 4 + k;
    return -1;
}

inline int next_down(const uint8_t b[16], int i) {
    int y = i >> 2, x = i & 3;
    for (int k = y + 1; k < 4; k++)
        if (b[k * 4 + x]) return k * 4 + x;
    return -1;
}

inline int prev_left(const uint8_t b[16], int i) {
    int y = i >> 2, x = i & 3;
    for (int k = x - 1; k >= 0; k--)
        if (b[y * 4 + k]) return y * 4 + k;
    return -1;
}

inline int prev_up(const uint8_t b[16], int i) {
    int y = i >> 2, x = i & 3;
    for (int k = y - 1; k >= 0; k--)
        if (b[k * 4 + x]) return k * 4 + x;
    return -1;
}

inline bool is_island_at(const uint8_t b[16], int i) {
    int v = b[i];
    int x = i & 3, y = i >> 2;
    if (x > 0 && b[i - 1] == v) return false;
    if (x < 3 && b[i + 1] == v) return false;
    if (y > 0 && b[i - 4] == v) return false;
    if (y < 3 && b[i + 4] == v) return false;
    return true;
}

inline int smooth_delta(const uint8_t b[16], int c, int v) {
    int r = next_right(b, c), d = next_down(b, c);
    int l = prev_left(b, c),  u = prev_up(b, c);
    int old_s = 0, new_s = 0;
    if (r >= 0) new_s += iabs(v - b[r]);
    if (d >= 0) new_s += iabs(v - b[d]);
    if (l >= 0) {
        if (r >= 0) old_s += iabs(b[l] - b[r]);
        new_s += iabs(b[l] - v);
    }
    if (u >= 0) {
        if (d >= 0) old_s += iabs(b[u] - b[d]);
        new_s += iabs(b[u] - v);
    }
    return -(new_s - old_s);
}

inline int islands_delta(const uint8_t b[16], int c, int v) {
    int delta = 0;
    int x = c & 3, y = c >> 2;
    bool conn = false;
    if (x > 0 && b[c - 1] == v) conn = true;
    if (x < 3 && b[c + 1] == v) conn = true;
    if (y > 0 && b[c - 4] == v) conn = true;
    if (y < 3 && b[c + 4] == v) conn = true;
    if (!conn) delta += 1;

    if (x > 0 && b[c - 1] == v && is_island_at(b, c - 1)) delta -= 1;
    if (x < 3 && b[c + 1] == v && is_island_at(b, c + 1)) delta -= 1;
    if (y > 0 && b[c - 4] == v && is_island_at(b, c - 4)) delta -= 1;
    if (y < 3 && b[c + 4] == v && is_island_at(b, c + 4)) delta -= 1;
    return delta;
}

struct Ctx {
    uint64_t nodes;
    uint64_t budget;
    bool aborted;
};

int search_player(const uint8_t b[16], int depth, int beta, Ctx& c);

int search_chance(const uint8_t b[16], int depth, int alpha, Ctx& c) {
    if (c.aborted) return eval(b);
    if (c.nodes >= c.budget) { c.aborted = true; return eval(b); }

    int cells[16];
    int n = 0;
    for (int i = 0; i < 16; i++)
        if (!b[i]) cells[n++] = i;
    if (n == 0) return eval(b) + DEAD;

    // 机会节点候选剪枝：先按 -smoothness + islands 给每个 (空格, 2/4) 打分，
    // 只递归得分最高的候选（与 ovolve 一致）。
    // 基准分只算一次；每个候选的增量是 O(1)。
    int base_metric = -smoothness(b) + islands(b);
    int best_metric = -INF;
    uint8_t cand_cell[32];
    uint8_t cand_val[32];
    int cn = 0;
    for (int k = 0; k < n; k++) {
        for (int v = 1; v <= 2; v++) {
            int metric = base_metric - smooth_delta(b, cells[k], v)
                         + islands_delta(b, cells[k], v);
            if (metric > best_metric) { best_metric = metric; cn = 0; }
            if (metric == best_metric) {
                cand_cell[cn] = (uint8_t)cells[k];
                cand_val[cn]  = (uint8_t)v;
                cn++;
            }
        }
    }

    int best = INF;
    for (int k = 0; k < cn; k++) {
        uint8_t nb[16];
        for (int i = 0; i < 16; i++) nb[i] = b[i];
        nb[cand_cell[k]] = cand_val[k];
        c.nodes++;
        int v = search_player(nb, depth, best, c);
        if (v < best) best = v;
        if (best < alpha) break;
        if (c.aborted) break;
    }
    return best;
}

int search_player(const uint8_t b[16], int depth, int beta, Ctx& c) {
    if (c.aborted) return eval(b);
    if (c.nodes >= c.budget) { c.aborted = true; return eval(b); }
    if (depth <= 0) { c.nodes++; return eval(b); }

    int best = -INF;
    bool any = false;
    for (int dir = 0; dir < 4; dir++) {
        uint8_t nb[16];
        if (!move(b, dir, nb, nullptr)) continue;
        any = true;
        c.nodes++;
        if (is_win(nb)) return WIN - (8 - depth) * 10;
        int v = search_chance(nb, depth - 1, best, c);
        if (v > best) best = v;
        if (best > beta) break;
        if (c.aborted) break;
    }
    if (!any) return eval(b) + DEAD;
    return best;
}

}  // namespace

int move(const uint8_t in[16], int dir, uint8_t out[16], int* gain) {
    for (int i = 0; i < 16; i++) out[i] = in[i];
    int g = 0;
    bool moved = false;
    for (int line = 0; line < 4; line++) {
        int idx[4];
        line_idx(dir, line, idx);
        uint8_t v[4] = {0, 0, 0, 0};
        int n = 0;
        for (int k = 0; k < 4; k++)
            if (out[idx[k]]) v[n++] = out[idx[k]];
        uint8_t res[4] = {0, 0, 0, 0};
        int m = 0;
        for (int i = 0; i < n; i++) {
            if (i + 1 < n && v[i] == v[i + 1]) {
                res[m++] = (uint8_t)(v[i] + 1);
                g += 1 << (v[i] + 1);
                i++;
            } else {
                res[m++] = v[i];
            }
        }
        for (int k = 0; k < 4; k++) {
            if (out[idx[k]] != res[k]) moved = true;
            out[idx[k]] = res[k];
        }
    }
    if (gain) *gain = g;
    return moved ? 1 : 0;
}

int eval(const uint8_t b[16]) {
    int empty = 0, maxv = 0;
    for (int i = 0; i < 16; i++) {
        int v = b[i];
        if (!v) empty++;
        else if (v > maxv) maxv = v;
    }
    int smooth = smoothness(b);
    int mono   = monotonicity2(b);
    return smooth * 26 + mono * 256 + LN_EMPTY[empty] + maxv * 256;
}

uint32_t rng_next(uint32_t* s) {
    uint32_t x = *s;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *s = x;
    return x;
}

void spawn(uint8_t b[16], uint32_t* s) {
    int cells[16];
    int n = 0;
    for (int i = 0; i < 16; i++)
        if (!b[i]) cells[n++] = i;
    if (n == 0) return;
    int cell = cells[rng_next(s) % (uint32_t)n];
    b[cell] = (rng_next(s) % 10u == 0u) ? 2 : 1;
}

int best_move(const uint8_t b[16], int node_budget, int max_depth,
              uint64_t* nodes_used) {
    Ctx c;
    c.nodes = 0;
    c.budget = (uint64_t)node_budget;
    c.aborted = false;

    int best = -1;
    for (int d = 1; d <= max_depth; d++) {
        int local_best = -1;
        int local_score = -INF;
        int alpha = -INF;
        for (int dir = 0; dir < 4; dir++) {
            uint8_t nb[16];
            if (!move(b, dir, nb, nullptr)) continue;
            c.nodes++;
            int v;
            if (is_win(nb)) {
                v = WIN;
            } else {
                v = search_chance(nb, d - 1, alpha, c);
            }
            if (v > local_score) { local_score = v; local_best = dir; }
            if (v > alpha) alpha = v;
            if (c.aborted) break;
        }
        if (c.aborted) break;
        if (local_best >= 0) best = local_best;
        if (c.nodes >= c.budget) break;
    }

    if (best < 0) {
        uint8_t nb[16];
        for (int dir = 0; dir < 4; dir++)
            if (move(b, dir, nb, nullptr)) return dir;
    }
    if (nodes_used) *nodes_used = c.nodes;
    return best;
}

int chance_metric_naive(const uint8_t b[16], int cell, int value) {
    uint8_t nb[16];
    for (int i = 0; i < 16; i++) nb[i] = b[i];
    nb[cell] = (uint8_t)value;
    return -smoothness(nb) + islands(nb);
}

int chance_metric_inc(const uint8_t b[16], int cell, int value) {
    int base = -smoothness(b) + islands(b);
    return base - smooth_delta(b, cell, value) + islands_delta(b, cell, value);
}

}  // namespace ai
