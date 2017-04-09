cmake_minimum_required(VERSION 2.8)
find_package(CUDA)

project(libshot2jpeg_project)

cuda_add_library(shot2jpeg STATIC shot2jpeg.cu)