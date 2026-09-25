#pragma once

#include <QCoreApplication>
#include <QFileInfo>
#include <QStandardPaths>
#include <QString>

inline QString ffmpegExecutable()
{
    const auto configured = qEnvironmentVariable("KADRON_FFMPEG");
    if (!configured.isEmpty() && QFileInfo(configured).isExecutable())
        return configured;

#ifdef Q_OS_WIN
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/ffmpeg.exe";
#else
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/ffmpeg";
#endif
    if (QFileInfo(bundled).isExecutable())
        return bundled;

    return QStandardPaths::findExecutable("ffmpeg");
}
