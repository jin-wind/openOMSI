#import <Foundation/Foundation.h>
#import <GameController/GameController.h>

#include "game_controller.h"
#include <string.h>

static void copy_gamepad_name(char *destination, size_t capacity, NSString *name) {
    const char *utf8 = name.length ? name.UTF8String : NULL;
    if (utf8 == NULL) {
        utf8 = "Gamepad";
    }
    size_t length = strlen(utf8);
    if (length >= capacity) {
        length = capacity - 1;
        // Do not split a UTF-8 character at the end of the fixed-size buffer.
        while (length > 0 && ((unsigned char)utf8[length] & 0xc0) == 0x80) {
            --length;
        }
    }
    memcpy(destination, utf8, length);
    destination[length] = '\0';
}

size_t openomsi_poll_gamepads(struct OpenOMSI_Gamepad *out, size_t capacity) {
    if (out == NULL || capacity == 0) {
        return 0;
    }

    @autoreleasepool {
        // Weak keys avoid retaining disconnected controllers. Pointer identity
        // distinguishes identical controller models and survives array reordering.
        static NSMapTable<GCController *, NSNumber *> *identifiers;
        static uint64_t next_identifier = 1;
        @synchronized ([GCController class]) {
            if (identifiers == nil) {
                identifiers = [[NSMapTable alloc]
                    initWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                    valueOptions:NSPointerFunctionsStrongMemory
                    capacity:4];
            }

            size_t count = 0;
            for (GCController *controller in [GCController controllers]) {
                if (count == capacity) {
                    break;
                }
                // A captured profile keeps all axes and buttons in this poll
                // consistent even if the controller changes on another queue.
                GCExtendedGamepad *gamepad = [controller capture].extendedGamepad;
                if (gamepad == nil) {
                    continue;
                }

                NSNumber *identifier = [identifiers objectForKey:controller];
                if (identifier == nil) {
                    identifier = @(next_identifier++);
                    [identifiers setObject:identifier forKey:controller];
                }

                struct OpenOMSI_Gamepad *state = &out[count++];
                memset(state, 0, sizeof(*state));
                state->id = identifier.unsignedLongLongValue;
                state->axes[0] = gamepad.leftThumbstick.xAxis.value;
                state->axes[1] = gamepad.leftThumbstick.yAxis.value;
                state->axes[2] = gamepad.rightThumbstick.xAxis.value;
                state->axes[3] = gamepad.rightThumbstick.yAxis.value;
                state->axes[4] = gamepad.leftTrigger.value;
                state->axes[5] = gamepad.rightTrigger.value;
                GCControllerButtonInput *buttons[] = {
                    gamepad.buttonA, gamepad.buttonB, gamepad.buttonX, gamepad.buttonY,
                    gamepad.leftShoulder, gamepad.rightShoulder,
                    gamepad.buttonOptions, gamepad.buttonMenu,
                    gamepad.leftThumbstickButton, gamepad.rightThumbstickButton,
                    gamepad.dpad.up, gamepad.dpad.down, gamepad.dpad.left, gamepad.dpad.right,
                };
                for (size_t bit = 0; bit < sizeof(buttons) / sizeof(buttons[0]); ++bit) {
                    // Optional inputs are nil on controllers without that button.
                    if (buttons[bit].isPressed) {
                        state->buttons |= UINT32_C(1) << bit;
                    }
                }
                copy_gamepad_name(state->name, sizeof(state->name), controller.vendorName);
            }
            return count;
        }
    }
}
