#include "config.hpp"
#include "evdev_reader.hpp"
#include "gesture_detector.hpp"
#include <cstdio>
#include <cstdlib>
#include <csignal>
#include <thread>
#include <sys/types.h>
#include <unistd.h>

static volatile sig_atomic_t g_running = 1;
static void signal_handler(int) { g_running = 0; }

int main(int argc, char* argv[]) {
    std::string cfg_path = std::getenv("HOME")
        ? std::string(std::getenv("HOME")) + "/.config/hypr-edge-gestures/config"
        : "";
    if (argc > 1) cfg_path = argv[1];

    // Set up D-Bus environment for playerctl
    uid_t uid = getuid();
    std::string dbus_addr = "unix:path=/run/user/" + std::to_string(uid) + "/bus";
    std::string runtime_dir = "/run/user/" + std::to_string(uid);

    if (getenv("DBUS_SESSION_BUS_ADDRESS") == nullptr) {
        setenv("DBUS_SESSION_BUS_ADDRESS", dbus_addr.c_str(), 1);
    }
    if (getenv("XDG_RUNTIME_DIR") == nullptr) {
        setenv("XDG_RUNTIME_DIR", runtime_dir.c_str(), 1);
    }

    AppConfig cfg;
    try { cfg = loadConfig(cfg_path); }
    catch (const std::exception& e) {
        fprintf(stderr, "Config error: %s\n", e.what());
        return 1;
    }

    EvdevReader reader;
    std::string dev = cfg.device_path.empty() ? EvdevReader::findTouchpad() : cfg.device_path;
    if (dev.empty()) { fprintf(stderr, "No touchpad found\n"); return 1; }

    if (!reader.openDevice(dev)) return 1;
    if (cfg.gesture.device_width  == 0) cfg.gesture.device_width  = reader.getWidth();
    if (cfg.gesture.device_height == 0) cfg.gesture.device_height = reader.getHeight();

    fprintf(stderr, "[edge] device: %s (%s) %dx%d\n",
            dev.c_str(), reader.getDeviceName().c_str(),
            cfg.gesture.device_width, cfg.gesture.device_height);

    GestureDetector detector(cfg.gesture, std::move(cfg.actions));

    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    std::thread reader_thread([&]() {
        reader.run([&](const TouchEvent& ev) { detector.onTouchEvent(ev); });
    });

    while (g_running) usleep(100000);
    reader.close();
    reader_thread.detach();
    return 0;
}
