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

inline QString ffprobeExecutable()
{
    const auto configured = qEnvironmentVariable("KADRON_FFPROBE");
    if (!configured.isEmpty() && QFileInfo(configured).isExecutable())
        return configured;

    const QFileInfo ffmpeg(ffmpegExecutable());
#ifdef Q_OS_WIN
    const auto sibling = ffmpeg.absolutePath() + "/ffprobe.exe";
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/ffprobe.exe";
#else
    const auto sibling = ffmpeg.absolutePath() + "/ffprobe";
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/ffprobe";
#endif
    if (QFileInfo(sibling).isExecutable())
        return sibling;
    if (QFileInfo(bundled).isExecutable())
        return bundled;
    return QStandardPaths::findExecutable("ffprobe");
}
