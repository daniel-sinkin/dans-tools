cmake_minimum_required(VERSION 3.20)

project(dans_dev_marker_tidy LANGUAGES C CXX)

find_package(Clang CONFIG REQUIRED)

add_library(dans_dev_marker_tidy_plugin MODULE DevelopmentMarkersCheck.cpp)

target_compile_features(dans_dev_marker_tidy_plugin PRIVATE cxx_std_20)
target_include_directories(dans_dev_marker_tidy_plugin PRIVATE
    ${LLVM_INCLUDE_DIRS}
    ${CLANG_INCLUDE_DIRS}
)
target_compile_definitions(dans_dev_marker_tidy_plugin PRIVATE ${LLVM_DEFINITIONS})
target_link_libraries(dans_dev_marker_tidy_plugin PRIVATE clangTidy)

set_target_properties(dans_dev_marker_tidy_plugin PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    PREFIX ""
)
