#pragma once
#include "gesture_detector.hpp"
#include <string>
#include <vector>

struct AppConfig {
    GestureConfig gesture;
    std::string device_path;
    std::vector<EdgeAction> actions;
};

AppConfig loadConfig(const std::string& path);
