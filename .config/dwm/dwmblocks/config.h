#ifndef CONFIG_H
#define CONFIG_H

// String used to delimit block outputs in the status.
#define DELIMITER " "

// Maximum number of Unicode characters that a block can output.
#define MAX_BLOCK_OUTPUT_LENGTH 1200

// Control whether blocks are clickable.
#define CLICKABLE_BLOCKS 1

// Control whether a leading delimiter should be prepended to the status.
#define LEADING_DELIMITER 0

// Control whether a trailing delimiter should be appended to the status.
#define TRAILING_DELIMITER 0

// Define blocks for the status feed as X(icon, cmd, interval, signal).
#define BLOCKS(X)             \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/music.sh'", 10, 15) \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/disk.sh'", 5, 8) \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/cpubar.sh'", 5, 7) \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/cpu.sh'", 20, 0) \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/mem.sh'", 5, 10)  \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/updates.sh'", 300, 4)   \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/brightness.sh'", 30, 6)   \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/vol.sh'", 300, 5)   \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/lang.sh'", 0, 3) \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/time.sh'", 30, 1) \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/net.sh'", 300, 4)   \
    X("", "bash -c '/home/mz/dotfiles/.config/dwm/dwmblocks/scripts/battary.sh'", 300, 10)  \ 
    X("", "echo '      '", 0, 0)  \ 

#endif  // CONFIG_H
