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

// yt-dlp goes stale quickly as sites change, so Kadron can keep its own
// self-updating copy in the user's app data. It wins over bundled and PATH copies.
inline QString managedYtDlpPath()
{
#ifdef Q_OS_WIN
    const auto name = QStringLiteral("yt-dlp.exe");
#else
    const auto name = QStringLiteral("yt-dlp");
#endif
    return QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + "/bin/" + name;
}

inline QString ytDlpExecutable()
{
    const auto configured = qEnvironmentVariable("KADRON_YTDLP");
    if (!configured.isEmpty() && QFileInfo(configured).isExecutable())
        return configured;
    if (QFileInfo(managedYtDlpPath()).isExecutable())
        return managedYtDlpPath();
#ifdef Q_OS_WIN
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/yt-dlp.exe";
#else
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/yt-dlp";
#endif
    if (QFileInfo(bundled).isExecutable())
        return bundled;
    return QStandardPaths::findExecutable("yt-dlp");
}

inline QString qpdfExecutable()
{
    const auto configured = qEnvironmentVariable("KADRON_QPDF");
    if (!configured.isEmpty() && QFileInfo(configured).isExecutable())
        return configured;
#ifdef Q_OS_WIN
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/qpdf.exe";
#else
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/qpdf";
#endif
    if (QFileInfo(bundled).isExecutable())
        return bundled;
    return QStandardPaths::findExecutable("qpdf");
}

// poppler's pdftoppm renders PDF pages for the visual editor.
inline QString pdftoppmExecutable()
{
    const auto configured = qEnvironmentVariable("KADRON_PDFTOPPM");
    if (!configured.isEmpty() && QFileInfo(configured).isExecutable())
        return configured;
#ifdef Q_OS_WIN
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/pdftoppm.exe";
#else
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/pdftoppm";
#endif
    if (QFileInfo(bundled).isExecutable())
        return bundled;
    return QStandardPaths::findExecutable("pdftoppm");
}

inline QString qrencodeExecutable()
{
    const auto configured = qEnvironmentVariable("KADRON_QRENCODE");
    if (!configured.isEmpty() && QFileInfo(configured).isExecutable())
        return configured;
#ifdef Q_OS_WIN
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/qrencode.exe";
#else
    const auto bundled = QCoreApplication::applicationDirPath() + "/bin/qrencode";
#endif
    if (QFileInfo(bundled).isExecutable())
        return bundled;
    return QStandardPaths::findExecutable("qrencode");
}
