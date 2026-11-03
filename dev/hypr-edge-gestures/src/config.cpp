#include "config.hpp"
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <cstdlib>

static std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(" \t\r\n");
    return s.substr(a, b - a + 1);
}

AppConfig loadConfig(const std::string& path) {
    AppConfig cfg;
    std::ifstream f(path);
    if (!f) throw std::runtime_error("Cannot open config: " + path);

    std::string line;
    while (std::getline(f, line)) {
        line = trim(line);
        if (line.empty() || line[0] == '#') continue;

        auto eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string key = trim(line.substr(0, eq));
        std::string val = trim(line.substr(eq + 1));

        if      (key == "device")              cfg.device_path = val;
        else if (key == "edge_margin")         cfg.gesture.edge_margin = std::stoi(val);
        else if (key == "distance_threshold")  cfg.gesture.distance_threshold = std::stoi(val);
        else if (key == "timeout_ms")          cfg.gesture.timeout_ms = std::stoi(val);
        else if (key == "device_width")        cfg.gesture.device_width = std::stoi(val);
        else if (key == "device_height")       cfg.gesture.device_height = std::stoi(val);
        else if (key == "verbose")             cfg.gesture.verbose = (val == "true" || val == "1");
        else {
            // Binding: edge:direction = command
            auto colon = key.find(':');
            if (colon != std::string::npos) {
                EdgeAction a;
                a.edge      = trim(key.substr(0, colon));
                a.direction = trim(key.substr(colon + 1));
                a.command   = val;
                cfg.actions.push_back(std::move(a));
            }
        }
    }
    return cfg;
}
