cmake_minimum_required(VERSION 3.16)
project(hypr-edge-gestures LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O2 -Wall")

add_executable(hypr-edge-gestures
    src/main.cpp
    src/evdev_reader.cpp
    src/gesture_detector.cpp
    src/config.cpp
)

install(TARGETS hypr-edge-gestures DESTINATION bin)
install(FILES config/config.example DESTINATION share/hypr-edge-gestures)
