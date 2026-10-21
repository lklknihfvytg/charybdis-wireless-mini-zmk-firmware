#include <assert.h>
#include <stdio.h>
#include "scroll_snap.h"

static int frame(struct scroll_snap_state *s, int x, int y, int now) {
    assert(scroll_snap_feed(s, true, x, false, now, 4, 200) == 0);
    return scroll_snap_feed(s, false, y, true, now, 4, 200);
}

int main(void) {
    struct scroll_snap_state s = {0};
    assert(frame(&s, 2, 16, 100) == 16 && s.axis == SCROLL_Y);
    assert(frame(&s, 100, -8, 104) == -8 && s.axis == SCROLL_Y);
    /* After a pause the same instance permits horizontal scrolling. */
    assert(frame(&s, -20, 1, 304) == -20 && s.axis == SCROLL_X);
    assert(frame(&s, 4, 30, 308) == 4 && s.axis == SCROLL_X);
    scroll_snap_reset(&s);
    /* Tiny movement is accumulated, not lost, until a decision is possible. */
    assert(frame(&s, 1, -1, 400) == 0);
    assert(frame(&s, 1, -3, 404) == -4 && s.axis == SCROLL_Y);
    scroll_snap_reset(&s);
    /* Pauses discard stale movement, and zero reports do not extend a gesture. */
    assert(frame(&s, 3, 0, 500) == 0);
    assert(frame(&s, 0, 0, 650) == 0);
    assert(frame(&s, 0, 4, 700) == 4 && s.axis == SCROLL_Y);
    scroll_snap_reset(&s);
    assert(frame(&s, -8, -8, 800) == -8 && s.axis == SCROLL_Y);
    scroll_snap_reset(&s);
    /* Pure X reports can finish without a Y event (PMW3610 emits sparse axes). */
    assert(scroll_snap_feed(&s, true, 16, true, 900, 4, 200) == 16);
    assert(s.axis == SCROLL_X);
    /* Decide after the complete XY frame, not prematurely on the X component. */
    scroll_snap_reset(&s);
    assert(frame(&s, 8, 30, 1000) == 30 && s.axis == SCROLL_Y);
    /* The unwanted component must not leak into a later gesture. */
    assert(frame(&s, 0, 1, 1004) == 1);
    assert(frame(&s, 5, 0, 1300) == 5 && s.axis == SCROLL_X);
    puts("Scroll snap: axis choice, signs, diagonal, sparse XY, pause and reset passed");
}
