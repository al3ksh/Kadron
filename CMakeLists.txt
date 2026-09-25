cmake_minimum_required(VERSION 3.24)

project(Kadron VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick QuickControls2 Multimedia Network)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(kadron
    src/main.cpp
    src/EditorProject.cpp
    src/EditorProject.h
    src/ExportController.cpp
    src/ExportController.h
    src/ThumbnailStrip.cpp
    src/ThumbnailStrip.h
    src/MediaTools.h
    src/ToolsClient.cpp
    src/ToolsClient.h
)

qt_add_qml_module(kadron
    URI Kadron
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/EditorButton.qml
        qml/EditorField.qml
        qml/Timeline.qml
)

target_link_libraries(kadron PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Multimedia
    Qt6::Network
)

set_target_properties(kadron PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 6.8 REQUIRED COMPONENTS Test)
    qt_add_executable(kadron_core_tests
        tests/core_tests.cpp
        src/EditorProject.cpp
        src/EditorProject.h
        src/ExportController.cpp
        src/ExportController.h
        src/ThumbnailStrip.cpp
        src/ThumbnailStrip.h
        src/MediaTools.h
        src/ToolsClient.cpp
        src/ToolsClient.h
    )
    target_include_directories(kadron_core_tests PRIVATE src)
    target_link_libraries(kadron_core_tests PRIVATE Qt6::Core Qt6::Test Qt6::Network)
    add_test(NAME core COMMAND kadron_core_tests)

    qt_add_executable(kadron_ui_tests tests/ui_tests.cpp)
    target_link_libraries(kadron_ui_tests PRIVATE Qt6::Quick Qt6::Qml Qt6::Test)
    target_compile_definitions(kadron_ui_tests PRIVATE KADRON_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
    add_test(NAME ui COMMAND kadron_ui_tests)
    set_tests_properties(ui PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
