cmake_minimum_required(VERSION 3.24)

project(Kadron VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick QuickControls2 Multimedia Network Concurrent)
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
    src/LocalMediaTools.cpp
    src/LocalMediaTools.h
    src/LocalDownload.cpp
    src/LocalDownload.h
    src/LocalPdfTools.cpp
    src/LocalPdfTools.h
    src/LocalQr.cpp
    src/LocalQr.h
    src/WindowChrome.cpp
    src/WindowChrome.h
    src/AppUpdater.cpp
    src/AppUpdater.h
)

qt_add_resources(kadron "kadron_assets" PREFIX "/" FILES assets/kadron-mark.png)
if(WIN32)
    target_sources(kadron PRIVATE assets/kadron.rc)
endif()
target_compile_definitions(kadron PRIVATE
    KADRON_VERSION="${PROJECT_VERSION}"
    KADRON_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
    KADRON_VERSION_MINOR=${PROJECT_VERSION_MINOR}
    KADRON_VERSION_PATCH=${PROJECT_VERSION_PATCH})

set_source_files_properties(qml/Theme.qml qml/Prefs.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# QML lives in a static module so the UI tests load exactly what the app ships.
qt_add_library(kadron_ui STATIC)
qt_add_qml_module(kadron_ui
    URI Kadron
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/EditorButton.qml
        qml/EditorField.qml
        qml/Timeline.qml
        qml/ToolsWorkspace.qml
        qml/ShareWorkspace.qml
        qml/ToolCombo.qml
        qml/ToolCheck.qml
        qml/BrandMark.qml
        qml/ToolIcon.qml
        qml/NavItem.qml
        qml/StudioProgress.qml
        qml/Theme.qml
        qml/SnapSpring.qml
        qml/SmoothSpring.qml
        qml/RevealAnimation.qml
        qml/StudioDialog.qml
        qml/DropZone.qml
        qml/RangeStrip.qml
        qml/SkeletonBlock.qml
        qml/UpdateCard.qml
        qml/Prefs.qml
        qml/VolumeControl.qml
        qml/AppearancePopup.qml
        qml/FileBoard.qml
        qml/PagePicker.qml
)
target_link_libraries(kadron_ui PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Multimedia)

target_link_libraries(kadron PRIVATE
    kadron_uiplugin
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Multimedia
    Qt6::Network
    Qt6::Concurrent
)
if(WIN32)
    target_link_libraries(kadron PRIVATE dwmapi)
endif()

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
        src/LocalMediaTools.cpp
        src/LocalMediaTools.h
        src/RemoteJobsClient.cpp
        src/RemoteJobsClient.h
        src/LocalDownload.cpp
        src/LocalDownload.h
        src/LocalPdfTools.cpp
        src/LocalPdfTools.h
        src/LocalQr.cpp
        src/LocalQr.h
        src/AppUpdater.cpp
        src/AppUpdater.h
    )
    target_include_directories(kadron_core_tests PRIVATE src)
    target_link_libraries(kadron_core_tests PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::Test Qt6::Network Qt6::Concurrent)
    add_test(NAME core COMMAND kadron_core_tests)

    qt_add_executable(kadron_ui_tests tests/ui_tests.cpp)
    target_link_libraries(kadron_ui_tests PRIVATE kadron_uiplugin Qt6::Quick Qt6::Qml Qt6::Test)
    target_compile_definitions(kadron_ui_tests PRIVATE KADRON_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
    add_test(NAME ui COMMAND kadron_ui_tests)
    set_tests_properties(ui PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
