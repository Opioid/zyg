#include "any_key.h"

// Based on
// http://www.cplusplus.com/forum/articles/7312/#msg33734

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#undef min
#undef max

char read_key() {
    DWORD  mode;
    HANDLE hstdin;

    // Set the console mode to no-echo, raw input, and no window or mouse events.
    hstdin = GetStdHandle(STD_INPUT_HANDLE);
    if (hstdin == INVALID_HANDLE_VALUE || !GetConsoleMode(hstdin, &mode) ||
        !SetConsoleMode(hstdin, 0))
        return 0;

    FlushConsoleInputBuffer(hstdin);

    // Get a single key RELEASE
    INPUT_RECORD inrec;

    DWORD count;

    do ReadConsoleInput(hstdin, &inrec, 1, &count);
    while ((inrec.EventType != KEY_EVENT) || inrec.Event.KeyEvent.bKeyDown);

    // Restore the original console mode
    SetConsoleMode(hstdin, mode);

    return inrec.Event.KeyEvent.uChar.AsciiChar;
}

#else

#include <termios.h>
#include <unistd.h>
#include <stdio.h>

char read_key() {
    static const size_t MAGIC_MAX_CHARS = 18;

    struct termios initial_settings;

    tcgetattr(STDIN_FILENO, &initial_settings);

    struct termios settings = initial_settings;

    // Set the console mode to no-echo, raw input.
    settings.c_cc[VTIME] = 1;
    settings.c_cc[VMIN]  = MAGIC_MAX_CHARS;
    settings.c_iflag &= ~(IXOFF);
    settings.c_lflag &= ~(ECHO | ICANON);
    tcsetattr(STDIN_FILENO, TCSANOW, &settings);

    unsigned char keycodes[MAGIC_MAX_CHARS];
    ssize_t const count = read(STDIN_FILENO, (void*)(keycodes), MAGIC_MAX_CHARS);

    tcsetattr(STDIN_FILENO, TCSANOW, &initial_settings);

    return (char)((count == 1) ? keycodes[0] : -(int)(keycodes[count - 1]));
}

#endif
