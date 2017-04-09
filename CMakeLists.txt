cmake_minimum_required(VERSION 2.8)

project(cudashot2jpeg_project)

include_directories(shot2jpeg)
add_subdirectory(shot2jpeg)

add_executable(test_shot2jpeg_1 test_shot2jpeg_1.cpp)
target_link_libraries(test_shot2jpeg_1 shot2jpeg xcb xcb-image jpeg)

add_executable(test_shot2jpeg_2 test_shot2jpeg_2.cpp)
target_link_libraries(test_shot2jpeg_2 shot2jpeg xcb xcb-image jpeg)

add_executable(test_shot2jpeg_3 test_shot2jpeg_3.cpp)
target_link_libraries(test_shot2jpeg_3 shot2jpeg xcb xcb-image jpeg)