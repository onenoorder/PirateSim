cmake_minimum_required(VERSION 3.20)

project(PirateSim
    VERSION 0.1.0
    DESCRIPTION "PirateSim - a pirate-themed action RPG with sailing, combat and trading"
    LANGUAGES C CXX
)

# ---- Global settings -------------------------------------------------------
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type (default Debug)" FORCE)
endif()

# ---- Dependencies ----------------------------------------------------------
find_package(PkgConfig REQUIRED)
pkg_check_modules(SDL2 REQUIRED IMPORTED_TARGET sdl2)
pkg_check_modules(SDL2_MIXER REQUIRED IMPORTED_TARGET SDL2_mixer)
pkg_check_modules(OPENGL REQUIRED IMPORTED_TARGET gl)
find_package(gtest QUIET)

# ---- Main executable -------------------------------------------------------
# NOTE: gameplay sources live in src/ and do not exist yet (greenfield story
# SDG-008 delivers the container environment only). The target below is a
# placeholder wired to the found libraries; add real sources as they land.
add_executable(piratesim
    src/main.cpp
)

target_link_libraries(piratesim PRIVATE
    PkgConfig::SDL2
    PkgConfig::SDL2_MIXER
    PkgConfig::OPENGL
)

target_include_directories(piratesim PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

# ---- Testing ---------------------------------------------------------------
enable_testing()

if(GTest_FOUND)
    # Sources mirror the source tree (test_strategy: tests live next to code).
    file(GLOB_RECURSE PIRATESIM_TEST_SOURCES CONFIGURE_DEPENDS
        tests/*.cpp
    )

    if(PIRATESIM_TEST_SOURCES)
        add_executable(piratesim_tests ${PIRATESIM_TEST_SOURCES})
        target_include_directories(piratesim_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
        target_link_libraries(piratesim_tests PRIVATE GTest::gtest_main)
        include(GoogleTest)
        gtest_discover_tests(piratesim_tests)
    else()
        message(STATUS "No tests/ sources found yet - ctest suite registered as empty.")
    endif()
else()
    message(STATUS "Google Test not found - test registration skipped (container installs gtest-devel).")
endif()

# ---- Developer conveniences ------------------------------------------------
option(PIRATESIM_ENABLE_LINTERS "Enable lint/format targets" ON)

if(PIRATESIM_ENABLE_LINTERS)
    find_program(CLANG_TIDY_EXE NAMES clang-tidy)
    find_program(CPPCHECK_EXE NAMES cppcheck)
    find_program(CLANG_FORMAT_EXE NAMES clang-format)

    if(CLANG_FORMAT_EXE)
        file(GLOB_RECURSE PIRATESIM_ALL_CPP CONFIGURE_DEPENDS src/*.cpp src/*.hpp tests/*.cpp)
        add_custom_target(format
            COMMAND ${CLANG_FORMAT_EXE} -i --style=file ${PIRATESIM_ALL_CPP}
            COMMENT "Running clang-format on all sources"
            VERBATIM
        )
    endif()

    if(CPPCHECK_EXE)
        add_custom_target(cppcheck
            COMMAND ${CPPCHECK_EXE} --enable=all --std=c++17 --suppress=missingIncludeSystem
                    ${CMAKE_CURRENT_SOURCE_DIR}/src ${CMAKE_CURRENT_SOURCE_DIR}/tests
            COMMENT "Running cppcheck static analysis"
            VERBATIM
        )
    endif()
endif()
