#include "evdev_reader.hpp"
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <cstring>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <dirent.h>

EvdevReader::EvdevReader() {}
EvdevReader::~EvdevReader() { close(); }

int64_t EvdevReader::now_ms() const {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

std::string EvdevReader::findTouchpad() {
    DIR* dir = opendir("/dev/input");
    if (!dir) return "";
    std::string best;
    struct dirent* ent;
    while ((ent = readdir(dir))) {
        if (strncmp(ent->d_name, "event", 5) != 0) continue;
        std::string path = std::string("/dev/input/") + ent->d_name;
        int fd = ::open(path.c_str(), O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;

        unsigned long absbits[ABS_CNT / (8 * sizeof(unsigned long)) + 1] = {0};
        unsigned long propbits[INPUT_PROP_CNT / (8 * sizeof(unsigned long)) + 1] = {0};

        bool has_mt_x = false, has_pointer = false, has_direct = false;
        if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(absbits)), absbits) >= 0) {
            has_mt_x = (absbits[ABS_MT_POSITION_X / (8 * sizeof(unsigned long))] &
                        (1UL << (ABS_MT_POSITION_X % (8 * sizeof(unsigned long))))) != 0;
        }
        if (ioctl(fd, EVIOCGPROP(sizeof(propbits)), propbits) >= 0) {
            has_pointer = (propbits[INPUT_PROP_POINTER / (8 * sizeof(unsigned long))] &
                           (1UL << (INPUT_PROP_POINTER % (8 * sizeof(unsigned long))))) != 0;
            has_direct = (propbits[INPUT_PROP_DIRECT / (8 * sizeof(unsigned long))] &
                          (1UL << (INPUT_PROP_DIRECT % (8 * sizeof(unsigned long))))) != 0;
        }
        ::close(fd);
        if (has_mt_x && has_pointer && !has_direct) { best = path; break; }
    }
    closedir(dir);
    return best;
}

bool EvdevReader::openDevice(const std::string& path) {
    fd_ = ::open(path.c_str(), O_RDONLY);
    if (fd_ < 0) {
        fprintf(stderr, "Cannot open %s: %s\n", path.c_str(), strerror(errno));
        return false;
    }
    struct input_absinfo ai;
    if (ioctl(fd_, EVIOCGABS(ABS_X), &ai) == 0) width_  = ai.maximum;
    if (ioctl(fd_, EVIOCGABS(ABS_Y), &ai) == 0) height_ = ai.maximum;
    char devname[256] = {0};
    if (ioctl(fd_, EVIOCGNAME(sizeof(devname)), devname) >= 0) name_ = devname;
    return true;
}

void EvdevReader::close() {
    if (fd_ >= 0) { ::close(fd_); fd_ = -1; }
}

void EvdevReader::handleEvent(const struct input_event& ev, TouchCallback& cb) {
    if (ev.type == EV_KEY) {
        // Mark multi-finger
        if ((ev.code == BTN_TOOL_DOUBLETAP ||
             ev.code == BTN_TOOL_TRIPLETAP ||
             ev.code == BTN_TOOL_QUADTAP ||
             ev.code == BTN_TOOL_QUINTTAP) && ev.value == 1) {
            had_multi_finger_ = true;
            return;
        }
        if (ev.code == BTN_TOUCH) {
            if (ev.value == 1 && !touching_) {
                touching_ = true;
                had_multi_finger_ = false;
                cb({TouchEvent::BEGIN, current_x_, current_y_, now_ms(), 1});
            } else if (ev.value == 0 && touching_) {
                touching_ = false;
                if (!had_multi_finger_) {
                    cb({TouchEvent::END, current_x_, current_y_, now_ms(), 1});
                }
            }
        }
    } else if (ev.type == EV_ABS) {
        if (ev.code == ABS_X || ev.code == ABS_MT_POSITION_X) {
            current_x_ = ev.value;
        } else if (ev.code == ABS_Y || ev.code == ABS_MT_POSITION_Y) {
            current_y_ = ev.value;
        }
    }
}

void EvdevReader::run(TouchCallback cb) {
    struct input_event ev;
    while (true) {
        ssize_t n = ::read(fd_, &ev, sizeof(ev));
        if (n == sizeof(ev)) {
            handleEvent(ev, cb);
        } else if (n < 0 && errno != EINTR) {
            break;
        }
    }
}
