typedef unsigned char u8;
static const u8 L2[18] = {0,1,2,2,3,3,3,3,4,4,4,4,4,4,4,4,5,5};

static int iabs(int x){ return x < 0 ? -x : x; }

/* 定点版启发式：smoothness + monotonicity2 + empty + max */
int eval(const u8 *b){
    int smooth = 0, mono = 0, empty = 0, maxv = 0;
    int i, x, y;
    for (i = 0; i < 16; i++){
        int v = b[i];
        if (!v) { empty++; continue; }
        int lv = L2[v];
        if (lv > maxv) maxv = lv;
        if ((i & 3) != 3){ int r = b[i+1]; if (r) smooth -= iabs(lv - L2[r]); }
        if (i < 12)      { int d = b[i+4]; if (d) smooth -= iabs(lv - L2[d]); }
    }
    for (y = 0; y < 4; y++){
        int cur = 0, next = b[y*4] ? L2[b[y*4]] : 0;
        for (x = 0; x < 3; x++){
            cur = next;
            next = b[y*4+x+1] ? L2[b[y*4+x+1]] : 0;
            if (cur > next) mono -= cur - next;
            else            mono += next - cur;
        }
    }
    for (x = 0; x < 4; x++){
        int cur = 0, next = b[x] ? L2[b[x]] : 0;
        for (y = 0; y < 3; y++){
            cur = next;
            next = b[(y+1)*4+x] ? L2[b[(y+1)*4+x]] : 0;
            if (cur > next) mono -= cur - next;
            else            mono += next - cur;
        }
    }
    return smooth + mono + (empty << 2) + (maxv << 1);
}

/* 向左移动 + 合并（单行，四行循环） */
void move_left(u8 *b){
    int y;
    for (y = 0; y < 4; y++){
        u8 *r = b + y*4;
        u8 t[4]; int n = 0, i, k = 0;
        for (i = 0; i < 4; i++) if (r[i]) t[n++] = r[i];
        for (i = 0; i < n; i++){
            if (i + 1 < n && t[i] == t[i+1]){ r[k++] = (u8)(t[i] + 1); i++; }
            else r[k++] = t[i];
        }
        while (k < 4) r[k++] = 0;
    }
}

/* 一个搜索节点：move + eval */
int node(u8 *b, int dir){
    (void)dir;
    move_left(b);
    return eval(b);
}

int main(void){
    static u8 b[16] = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16};
    int s = 0, i;
    for (i = 0; i < 100000; i++) s += node(b, i & 3);
    return s & 0xff;
}
