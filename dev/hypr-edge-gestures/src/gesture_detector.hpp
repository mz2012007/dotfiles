#pragma once
#include "evdev_reader.hpp"
#include <string>
#include <vector>

struct GestureConfig {
    int max_distance = 0;      // 0 = unlimited
    int cooldown_ms  = 0;      // 0 = no cooldown
    int edge_margin = 250;
    int distance_threshold = 200;
    int timeout_ms = 500;
    int device_width = 4101;
    int device_height = 2742;
    bool verbose = false;
};

struct EdgeAction {
    std::string edge;
    std::string direction;
    std::string command;
};

class GestureDetector {
public:
    GestureDetector(const GestureConfig& cfg, std::vector<EdgeAction> actions);

    void onTouchEvent(const TouchEvent& ev);

private:
    GestureConfig cfg_;
    std::vector<EdgeAction> actions_;

    bool tracking_ = false;
    int start_x_ = 0, start_y_ = 0;
    int64_t start_time_ = 0;
    std::string start_edge_;
    int64_t last_trigger_time_ = 0;

    void beginGesture(const TouchEvent& ev);
    void endGesture(const TouchEvent& ev);
    void executeAction(const std::string& edge, const std::string& direction);
    std::string classifyEdge(int x, int y) const;
    std::string classifyDirection(int dx, int dy) const;
};
