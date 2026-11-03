#pragma once
#include <string>
#include <functional>
#include <linux/input.h>

struct TouchEvent {
    enum Type { BEGIN, MOVE, END } type;
    int x;
    int y;
    int64_t timestamp_ms;
    int finger_count;  // 1 = single finger
};

using TouchCallback = std::function<void(const TouchEvent&)>;

class EvdevReader {
public:
    EvdevReader();
    ~EvdevReader();

    bool openDevice(const std::string& path);
    void close();
    bool isOpen() const { return fd_ >= 0; }

    int getWidth()  const { return width_; }
    int getHeight() const { return height_; }
    const std::string& getDeviceName() const { return name_; }

    void run(TouchCallback callback);
    static std::string findTouchpad();

private:
    int fd_ = -1;
    int width_  = 0;
    int height_ = 0;
    std::string name_;

    bool touching_ = false;
    bool had_multi_finger_ = false;
    int current_x_ = 0;
    int current_y_ = 0;

    int64_t now_ms() const;
    void handleEvent(const struct input_event& ev, TouchCallback& cb);
};
