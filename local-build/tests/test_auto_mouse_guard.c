#include <assert.h>
#include <stdio.h>
#include "auto_mouse_guard.h"

#define CLICK ((UINT64_C(1) << 19) | (UINT64_C(1) << 20) | (UINT64_C(1) << 21))
static void move(struct auto_mouse_guard *s, int value, int now) {
    auto_mouse_motion(s, true, value, now, true, 1000, 80, 200);
}

int main(void) {
    struct auto_mouse_guard s = {0};
    auto_mouse_key(&s, 15, true, 1000, CLICK);
    /* Even a long pause while D is held must never arm a mouse layer. */
    move(&s, 1000, 5000);
    assert(!s.active);
    auto_mouse_key(&s, 15, false, 6000, CLICK);
    move(&s, 1000, 6999);
    assert(!s.active);
    /* Motion from the blocked interval cannot carry across the cooldown. */
    move(&s, 1, 7000);
    assert(!s.active);
    /* Back-and-forth typing vibration must not accumulate as path length. */
    for (int i = 0; i < 100; i++) { move(&s, i % 2 ? -1 : 1, 7000 + i); }
    assert(!s.active);
    /* Slow drift must not add up over multiple windows. */
    for (int i = 0; i < 100; i++) { move(&s, 1, 8000 + i * 201); }
    assert(!s.active);
    move(&s, 80, 30000);
    assert(s.active);
    /* A normal key cancels immediately, before its binding is resolved. */
    auto_mouse_key(&s, 38, true, 30001, CLICK);
    assert(!s.active);
    auto_mouse_key(&s, 38, false, 30010, CLICK);
    move(&s, 40, 31010);
    move(&s, 40, 31050);
    assert(s.active);
    auto_mouse_key(&s, 19, true, 31060, CLICK);
    assert(s.active && !auto_mouse_expire(&s, 40000, 800));
    /* Mouse-up must still reach the original binding after a long drag. */
    auto_mouse_key(&s, 19, false, 40001, CLICK);
    assert(!auto_mouse_expire(&s, 40800, 800));
    assert(auto_mouse_expire(&s, 40801, 800));
    move(&s, -80, 42000);
    assert(s.active);
    auto_mouse_motion(&s, false, 100, 42001, false, 1000, 80, 200);
    assert(!s.active); /* Never take over NUM/NAV/MOUSE/SLOW/SCROLL. */
    move(&s, 80, 43000);
    auto_mouse_key(&s, 20, true, 43001, CLICK);
    auto_mouse_key(&s, 1, true, 43002, CLICK);
    assert(!s.active && s.held);
    auto_mouse_key(&s, 1, false, 43003, CLICK);
    auto_mouse_key(&s, 20, false, 43004, CLICK);
    assert(!s.held && s.last_typing == 43004);
    /* If activation is still queued, J must cancel and type normally. */
    move(&s, 80, 44004);
    assert(s.active);
    auto_mouse_key(&s, 19, true, 44005, 0);
    assert(!s.active);
    auto_mouse_key(&s, 19, false, 44006, CLICK);
    move(&s, 80, 45006);
    assert(s.active);
    move(&s, 0, 45700);
    assert(s.last_use == 45006);
    assert(auto_mouse_expire(&s, 45806, 800));
    puts("Auto mouse: typing, held HRM, cooldown, jitter, drift, click/drag, timeout and layers passed");
}
