#include "gesture_detector.hpp"
#include <cstdlib>
#include <cstdio>
#include <cmath>
#include <chrono>

static int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

GestureDetector::GestureDetector(const GestureConfig& cfg, std::vector<EdgeAction> actions)
    : cfg_(cfg), actions_(std::move(actions)) {}

std::string GestureDetector::classifyEdge(int x, int y) const {
    if (x < cfg_.edge_margin) return "left";
    if (x > cfg_.device_width - cfg_.edge_margin) return "right";
    if (y < cfg_.edge_margin) return "top";
    if (y > cfg_.device_height - cfg_.edge_margin) return "bottom";
    return "";
}

std::string GestureDetector::classifyDirection(int dx, int dy) const {
    if (std::abs(dx) > std::abs(dy)) return dx > 0 ? "right" : "left";
    return dy > 0 ? "down" : "up";
}

void GestureDetector::beginGesture(const TouchEvent& ev) {
    std::string edge = classifyEdge(ev.x, ev.y);
    if (edge.empty()) { tracking_ = false; return; }
    tracking_ = true;
    start_x_ = ev.x;
    start_y_ = ev.y;
    start_time_ = ev.timestamp_ms;
    start_edge_ = edge;
    if (cfg_.verbose)
        fprintf(stderr, "[edge] BEGIN %s at (%d,%d)\n", edge.c_str(), ev.x, ev.y);
}

void GestureDetector::endGesture(const TouchEvent& ev) {
    if (!tracking_) return;
    tracking_ = false;

    int64_t elapsed = ev.timestamp_ms - start_time_;
    int dx = ev.x - start_x_;
    int dy = ev.y - start_y_;
    int distance = (int)std::sqrt(dx*dx + dy*dy);

    if (cfg_.max_distance > 0 && distance > cfg_.max_distance) return;

    if (cfg_.verbose)
        fprintf(stderr, "[edge] END at (%d,%d) dist=%d time=%lldms\n",
                ev.x, ev.y, distance, (long long)elapsed);

    if (cfg_.timeout_ms > 0 && elapsed > cfg_.timeout_ms) return;
    if (distance < cfg_.distance_threshold) return;

    std::string dir = classifyDirection(dx, dy);
    executeAction(start_edge_, dir);
}

void GestureDetector::executeAction(const std::string& edge, const std::string& dir) {
    int64_t now = now_ms();
    if (cfg_.cooldown_ms > 0 && now - last_trigger_time_ < cfg_.cooldown_ms) return;
    last_trigger_time_ = now;

    for (const auto& a : actions_) {
        if (a.edge == edge && a.direction == dir) {
            if (cfg_.verbose)
                fprintf(stderr, "[edge] %s:%s -> %s\n", edge.c_str(), dir.c_str(), a.command.c_str());
            if (system(a.command.c_str()) != 0)
                fprintf(stderr, "[edge] command failed\n");
            return;
        }
    }
}

void GestureDetector::onTouchEvent(const TouchEvent& ev) {
    if (ev.finger_count > 1) { tracking_ = false; return; }
    switch (ev.type) {
        case TouchEvent::BEGIN: beginGesture(ev); break;
        case TouchEvent::END:   endGesture(ev);   break;
        case TouchEvent::MOVE:  break;
    }
}
