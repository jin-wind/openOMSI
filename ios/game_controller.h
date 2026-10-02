#ifndef OPENOMSI_GAME_CONTROLLER_H
#define OPENOMSI_GAME_CONTROLLER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Keep this layout in sync with the iOS input backend in Rust.
struct OpenOMSI_Gamepad {
    uint64_t id;
    // A, B, X, Y, LB, RB, View, Menu, L-stick, R-stick, Up, Down, Left, Right.
    uint32_t buttons;
    // LX, LY, RX, RY (-1..1, positive Y is up), LT, RT (0..1).
    float axes[6];
    char name[128];
};

// Returns the number of initialized records, never greater than capacity.
// IDs remain stable for the lifetime of a connected GCController instance.
size_t openomsi_poll_gamepads(struct OpenOMSI_Gamepad *out, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif
