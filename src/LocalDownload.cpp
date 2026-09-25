#include "LocalDownload.h"
#include "MediaTools.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSaveFile>

LocalDownload::LocalDownload(QObject *parent)
    : QObject(parent), m_ytdlp(ytDlpExecutable()), m_ffmpeg(ffmpegExecutable())
{
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &LocalDownload::readOutput);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        m_errorBuffer += m_process.readAllStandardError();
        if (m_errorBuffer.size() > 8192)
            m_errorBuffer = m_errorBuffer.right(8192);
    });
    connect(&m_process, &QProcess::finished, this, &LocalDownload::finishDownload);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart && m_busy)
            fail(QStringLiteral("Could not start yt-dlp. Check its installation."));
    });
    refreshYtDlpVersion();
    connect(&m_gifTools, &LocalMediaTools::changed, this, [this] {
        if (m_cancelled && !m_gifTools.busy()) {
            m_temp.reset();
            return;
        }
        if (!m_encodingGif)
            return;
        if (m_gifTools.busy()) {
            m_stage = m_gifTools.stage();
            m_progress = 80 + m_gifTools.progress() / 5;
        } else {
            m_encodingGif = false;
            if (!m_gifTools.errorText().isEmpty()) {
                fail(m_gifTools.errorText());
                return;
            }
            m_outputUrl = m_gifTools.outputUrl();
            m_outputBytes = m_gifTools.outputBytes();
            m_busy = false;
            m_progress = 100;
            m_stage = QStringLiteral("Ready");
            m_temp.reset();
        }
        emit changed();
    });
}

LocalDownload::~LocalDownload()
{
    if (m_process.state() != QProcess::NotRunning) {
        m_process.kill();
        m_process.waitForFinished(5000);
    }
    if (m_gifTools.busy()) m_gifTools.cancel();
}

bool LocalDownload::available() const { return !m_ytdlp.isEmpty() && !m_ffmpeg.isEmpty(); }
bool LocalDownload::busy() const { return m_busy; }
QString LocalDownload::stage() const { return m_stage; }
QString LocalDownload::ytDlpVersion() const { return m_ytdlpVersion; }
bool LocalDownload::updatingYtDlp() const { return m_updating; }
QString LocalDownload::updateText() const { return m_updateText; }

int LocalDownload::ytDlpAgeDays() const
{
    const auto date = versionDate(m_ytdlpVersion);
    return date.isValid() ? int(date.daysTo(QDate::currentDate())) : -1;
}

bool LocalDownload::ytDlpOutdated() const { return ytDlpAgeDays() > 90; }

QDate LocalDownload::versionDate(const QString &version)
{
    static const QRegularExpression pattern("^(\\d{4})\\.(\\d{1,2})\\.(\\d{1,2})");
    const auto match = pattern.match(version.trimmed());
    if (!match.hasMatch())
        return {};
    return QDate(match.captured(1).toInt(), match.captured(2).toInt(), match.captured(3).toInt());
}

QString LocalDownload::summarizeError(const QString &stderrText)
{
    const auto lines = stderrText.split('\n', Qt::SkipEmptyParts);
    for (auto it = lines.crbegin(); it != lines.crend(); ++it) {
        const auto line = it->trimmed();
        if (line.startsWith("ERROR:"))
            return line.mid(6).trimmed();
    }
    QStringList kept;
    for (const auto &line : lines)
        if (!line.trimmed().startsWith("WARNING:"))
            kept.append(line.trimmed());
    return kept.join('\n').right(700);
}

bool LocalDownload::probing() const { return m_probeProcess != nullptr; }
QVariantMap LocalDownload::preview() const { return m_preview; }

QString LocalDownload::safeFileName(const QString &title)
{
    static const QRegularExpression reserved(QStringLiteral("[\\\\/:*?\"<>|\\x00-\\x1f]+"));
    auto name = QString(title).replace(reserved, QStringLiteral(" ")).simplified();
    while (name.endsWith('.') || name.endsWith(' '))
        name.chop(1);
    return name.left(120).trimmed();
}

QString LocalDownload::youtubeId(const QString &url)
{
    static const QRegularExpression pattern(QStringLiteral(
        "(?:youtube\\.com/(?:[^/]+/.+/|(?:v|e(?:mbed)?|shorts)/|.*[?&]v=)|youtu\\.be/)([A-Za-z0-9_-]{11})"),
        QRegularExpression::CaseInsensitiveOption);
    const auto match = pattern.match(url);
    return match.hasMatch() ? match.captured(1) : QString();
}

QVariantMap LocalDownload::pageMetadata(const QString &html, const QUrl &base)
{
    const auto meta = [&html](const QString &key) {
        const auto escaped = QRegularExpression::escape(key);
        const QRegularExpression before(QStringLiteral("<meta[^>]*(?:property|name)=[\"']%1[\"'][^>]*content=[\"']([^\"']+)[\"']").arg(escaped),
                                        QRegularExpression::CaseInsensitiveOption);
        const QRegularExpression after(QStringLiteral("<meta[^>]*content=[\"']([^\"']+)[\"'][^>]*(?:property|name)=[\"']%1[\"']").arg(escaped),
                                       QRegularExpression::CaseInsensitiveOption);
        auto match = before.match(html);
        if (!match.hasMatch())
            match = after.match(html);
        return match.hasMatch() ? match.captured(1).trimmed() : QString();
    };
    auto image = meta("og:image");
    if (image.isEmpty())
        image = meta("twitter:image");
    auto title = meta("og:title");
    if (title.isEmpty())
        title = meta("twitter:title");
    QVariantMap result;
    if (!image.isEmpty())
        result.insert("thumbnail", base.resolved(QUrl(image.replace("&amp;", "&"))).toString());
    if (!title.isEmpty())
        result.insert("title", title.replace("&amp;", "&").replace("&quot;", "\"").replace("&#39;", "'"));
    return result;
}

void LocalDownload::fetchPageMetadata(const QString &url)
{
    QNetworkRequest request{QUrl(url)};
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    request.setTransferTimeout(6000);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Kadron"));
    auto *reply = m_network.get(request);
    connect(reply, &QNetworkReply::downloadProgress, reply, [reply](qint64 received, qint64) {
        if (received > 2 * 1024 * 1024) reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, url] {
        reply->deleteLater();
        if (m_probeUrl != url || reply->error() != QNetworkReply::NoError)
            return;
        const auto found = pageMetadata(QString::fromUtf8(reply->readAll()), reply->url());
        bool touched = false;
        for (auto it = found.cbegin(); it != found.cend(); ++it) {
            if (m_preview.value(it.key()).toString().isEmpty()) {
                m_preview.insert(it.key(), it.value());
                touched = true;
            }
        }
        if (found.contains("title") && m_preview.value("fileName").toString().isEmpty())
            m_preview.insert("fileName", safeFileName(found.value("title").toString()));
        if (touched)
            emit previewChanged();
    });
}

void LocalDownload::probe(const QString &url)
{
    const auto trimmed = url.trimmed();
    if (trimmed == m_probeUrl)
        return;
    m_probeUrl = trimmed;
    if (m_probeProcess) {
        m_probeProcess->disconnect(this);
        m_probeProcess->kill();
        m_probeProcess->deleteLater();
        m_probeProcess = nullptr;
    }
    m_preview.clear();
    const QUrl source(trimmed);
    if (m_ytdlp.isEmpty() || !source.isValid() || !QStringList{"http", "https"}.contains(source.scheme().toLower()) || source.host().isEmpty()) {
        emit previewChanged();
        return;
    }
    // Show what we can immediately; yt-dlp fills in the rest.
    m_preview = {{"url", trimmed}};
    const auto videoId = youtubeId(trimmed);
    if (!videoId.isEmpty()) {
        m_preview.insert("thumbnail", QStringLiteral("https://i.ytimg.com/vi/%1/hqdefault.jpg").arg(videoId));
        m_preview.insert("source", QStringLiteral("YouTube"));
    }
    auto *process = new QProcess(this);
    m_probeProcess = process;
    connect(process, &QProcess::finished, this, [this, process, trimmed](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (m_probeProcess != process)
            return;
        m_probeProcess = nullptr;
        const auto json = QJsonDocument::fromJson(process->readAllStandardOutput()).object();
        if (status != QProcess::NormalExit || code != 0 || json.isEmpty()) {
            // yt-dlp could not read it: keep any instant preview and fall back to page metadata.
            m_preview.insert("error", summarizeError(QString::fromUtf8(process->readAllStandardError())));
            emit previewChanged();
            fetchPageMetadata(trimmed);
            return;
        }
        m_preview.insert("title", json.value("title").toString());
        if (!json.value("thumbnail").toString().isEmpty())
            m_preview.insert("thumbnail", json.value("thumbnail").toString());
        m_preview.insert("durationMs", qRound64(json.value("duration").toDouble() * 1000.0));
        m_preview.insert("uploader", json.value("uploader").toString(json.value("channel").toString()));
        m_preview.insert("source", json.value("extractor_key").toString(json.value("extractor").toString()));
        m_preview.insert("fileName", safeFileName(json.value("title").toString()));
        emit previewChanged();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || m_probeProcess != process) return;
        m_probeProcess = nullptr;
        process->deleteLater();
        emit previewChanged();
    });
    process->start(m_ytdlp, {"--dump-single-json", "--skip-download", "--no-playlist", "--no-warnings", "--", trimmed});
    emit previewChanged();
}

void LocalDownload::refreshYtDlpVersion()
{
    m_ytdlp = ytDlpExecutable();
    if (m_ytdlp.isEmpty() || m_versionProcess)
        return;
    auto *process = new QProcess(this);
    m_versionProcess = process;
    connect(process, &QProcess::finished, this, [this, process] {
        m_ytdlpVersion = QString::fromUtf8(process->readAllStandardOutput()).trimmed().section('\n', 0, 0);
        process->deleteLater();
        emit changed();
    });
    connect(process, &QProcess::errorOccurred, this, [process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) process->deleteLater();
    });
    process->start(m_ytdlp, {"--version"});
}

void LocalDownload::updateYtDlp()
{
    if (m_updating || m_busy)
        return;
    m_updating = true;
    m_updateText = QStringLiteral("Updating yt-dlp…");
    emit changed();
    if (QFileInfo(managedYtDlpPath()).isExecutable()) {
        runSelfUpdate();
        return;
    }
    // No private copy yet: fetch the official standalone release.
#ifdef Q_OS_WIN
    const QUrl release("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe");
#elif defined(Q_OS_MACOS)
    const QUrl release("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos");
#else
    const QUrl release("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux");
#endif
    QNetworkRequest request(release);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    auto *reply = m_network.get(request);
    connect(reply, &QNetworkReply::downloadProgress, this, [this](qint64 received, qint64 total) {
        m_updateText = total > 0 ? QStringLiteral("Downloading yt-dlp… %1%").arg(received * 100 / total)
                                 : QStringLiteral("Downloading yt-dlp…");
        emit changed();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            finishUpdate(QStringLiteral("Could not download yt-dlp: %1").arg(reply->errorString()));
            return;
        }
        const auto target = managedYtDlpPath();
        QDir().mkpath(QFileInfo(target).absolutePath());
        QSaveFile file(target);
        const auto data = reply->readAll();
        if (data.size() < 1024 * 1024 || !file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit()) {
            finishUpdate(QStringLiteral("Could not save yt-dlp to %1").arg(QDir::toNativeSeparators(target)));
            return;
        }
        QFile::setPermissions(target, QFile::permissions(target) | QFileDevice::ExeOwner | QFileDevice::ExeUser);
        finishUpdate(QStringLiteral("yt-dlp installed for Kadron"));
    });
}

void LocalDownload::runSelfUpdate()
{
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::MergedChannels);
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        const auto output = QString::fromUtf8(process->readAll());
        process->deleteLater();
        if (status != QProcess::NormalExit || code != 0)
            finishUpdate(QStringLiteral("yt-dlp update failed: %1").arg(summarizeError(output)));
        else
            finishUpdate(output.contains("up to date", Qt::CaseInsensitive) ? QStringLiteral("yt-dlp is up to date")
                                                                           : QStringLiteral("yt-dlp updated"));
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) return;
        process->deleteLater();
        finishUpdate(QStringLiteral("Could not start yt-dlp to update it."));
    });
    process->start(managedYtDlpPath(), {"--update-to", "stable"});
}

void LocalDownload::finishUpdate(const QString &message)
{
    m_updating = false;
    m_updateText = message;
    m_ytdlpVersion.clear();
    emit changed();
    refreshYtDlpVersion();
}
QString LocalDownload::errorText() const { return m_errorText; }
int LocalDownload::progress() const { return m_progress; }
QUrl LocalDownload::outputUrl() const { return m_outputUrl; }
qint64 LocalDownload::outputBytes() const { return m_outputBytes; }

bool LocalDownload::download(const QString &url, const QString &preset, const QUrl &destination,
                             double gifStart, double gifDuration, int gifFps, int gifWidth, double gifTargetMB)
{
    if (m_busy)
        return false;
    m_errorText.clear();
    m_outputUrl = QUrl();
    m_outputBytes = 0;
    const QUrl source(url.trimmed());
    const QFileInfo output(destination.toLocalFile());
    const bool isGif = preset == "VIDEO_GIF_SOCIAL";
    const bool isAudio = preset.startsWith("AUDIO_");
    const QString extension = isGif ? "gif" : isAudio ? preset.section('_', 1, 1).toLower() : "mp4";
    if (!available()) {
        fail(QStringLiteral("Local downloads need yt-dlp and FFmpeg. Add them to PATH or set KADRON_YTDLP and KADRON_FFMPEG."));
        return false;
    }
    if (!QStringList{"VIDEO_MP4_BEST", "VIDEO_MP4_720P", "VIDEO_MP4_DISCORD", "VIDEO_GIF_SOCIAL",
                     "AUDIO_MP3_320", "AUDIO_MP3_192", "AUDIO_FLAC_BEST", "AUDIO_WAV_BEST",
                     "AUDIO_OPUS_96", "AUDIO_OPUS_BEST"}.contains(preset)
        || !source.isValid() || !QStringList{"http", "https"}.contains(source.scheme().toLower())
        || source.host().isEmpty() || !destination.isLocalFile()
        || output.suffix().compare(extension, Qt::CaseInsensitive) != 0
        || !output.dir().exists() || output.exists()
        || (isGif && (gifStart < 0 || gifDuration <= 0 || gifFps < 5 || gifFps > 30 || gifWidth < 120 || gifTargetMB < 0))) {
        fail(QStringLiteral("Check the URL, format, and output path. Existing files are never overwritten."));
        return false;
    }

    m_temp = std::make_unique<QTemporaryDir>(output.absolutePath() + "/.kadron-download-XXXXXX");
    if (!m_temp->isValid()) {
        fail(QStringLiteral("Could not create a temporary folder beside the output file."));
        return false;
    }
    m_destination = output.absoluteFilePath();
    m_downloaded.clear();
    m_preset = preset;
    m_gifStart = gifStart;
    m_gifDuration = gifDuration;
    m_gifFps = gifFps;
    m_gifWidth = gifWidth;
    m_gifTargetMB = gifTargetMB;
    m_outputBuffer.clear();
    m_errorBuffer.clear();
    m_progress = 0;
    m_busy = true;
    m_cancelled = false;
    m_stage = QStringLiteral("Finding source");

    QStringList arguments{"--no-playlist", "--no-overwrites", "--newline", "--no-colors",
                          "--print", "after_move:KADRON_OUTPUT:%(filepath)s",
                          "--ffmpeg-location", m_ffmpeg, "-o", m_temp->path() + "/source.%(ext)s"};
    if (isAudio) {
        arguments += {"-x", "--audio-format", extension};
        if (preset.endsWith("_320")) arguments += {"--audio-quality", "320K"};
        if (preset.endsWith("_192")) arguments += {"--audio-quality", "192K"};
        if (preset.endsWith("_96")) arguments += {"--audio-quality", "96K"};
    } else if (isGif) {
        arguments += {"-f", "bv*+ba/b"};
    } else {
        if (preset == "VIDEO_MP4_720P") arguments += {"-S", "res:720"};
        if (preset == "VIDEO_MP4_DISCORD") arguments += {"-S", "res:480"};
        arguments += {"-f", "bv*+ba/b", "--merge-output-format", "mp4", "--recode-video", "mp4"};
    }
    arguments += {"--", source.toString()};
    emit changed();
    m_process.start(m_ytdlp, arguments);
    return true;
}

void LocalDownload::readOutput()
{
    m_outputBuffer += m_process.readAllStandardOutput();
    while (true) {
        const auto newline = m_outputBuffer.indexOf('\n');
        if (newline < 0) break;
        const auto line = QString::fromUtf8(m_outputBuffer.left(newline)).trimmed();
        m_outputBuffer.remove(0, newline + 1);
        if (line.startsWith("KADRON_OUTPUT:")) {
            m_downloaded = line.mid(14).trimmed();
            m_stage = QStringLiteral("Finalizing");
        } else {
            if (line.startsWith("[download]")) m_stage = QStringLiteral("Downloading source");
            else if (line.startsWith("[Merger]") || line.startsWith("[ExtractAudio]")
                     || line.startsWith("[VideoConvertor]") || line.startsWith("[VideoRemuxer]"))
                m_stage = QStringLiteral("Encoding");
            static const QRegularExpression percent("(\\d+(?:\\.\\d+)?)%");
            const auto match = percent.match(line);
            if (match.hasMatch())
                m_progress = qBound(0, qRound(match.captured(1).toDouble() * 0.8), 80);
        }
        emit changed();
    }
    if (m_outputBuffer.size() > 8192)
        m_outputBuffer = m_outputBuffer.right(8192);
}

void LocalDownload::finishDownload(int exitCode, QProcess::ExitStatus exitStatus)
{
    if (m_cancelled) {
        m_temp.reset();
        return;
    }
    if (!m_busy)
        return;
    readOutput();
    if (exitStatus != QProcess::NormalExit || exitCode != 0) {
        auto detail = summarizeError(QString::fromUtf8(m_errorBuffer));
        if (ytDlpOutdated())
            detail += QStringLiteral(" (yt-dlp is %1 days old; update it and try again.)").arg(ytDlpAgeDays());
        fail(detail.trimmed().isEmpty() ? QStringLiteral("Download failed. Check the URL or network connection.") : detail.trimmed());
        return;
    }
    const QFileInfo file(m_downloaded);
    const auto tempRoot = QDir(m_temp->path()).canonicalPath() + '/';
    if (!file.isFile() || !file.canonicalFilePath().startsWith(tempRoot)) {
        fail(QStringLiteral("Downloaded file was not found in the temporary folder."));
        return;
    }
    if (m_preset == "VIDEO_GIF_SOCIAL") {
        m_encodingGif = true;
        m_stage = QStringLiteral("Encoding GIF");
        emit changed();
        if (!m_gifTools.createGif(QUrl::fromLocalFile(file.absoluteFilePath()), QUrl::fromLocalFile(m_destination),
                                  m_gifStart, m_gifDuration, m_gifFps, m_gifWidth, m_gifTargetMB)) {
            m_encodingGif = false;
            fail(m_gifTools.errorText());
        }
        return;
    }
    if (QFileInfo::exists(m_destination) || !QFile::rename(file.absoluteFilePath(), m_destination)) {
        fail(QStringLiteral("Could not move the download into the chosen output file."));
        return;
    }
    m_outputUrl = QUrl::fromLocalFile(m_destination);
    m_outputBytes = QFileInfo(m_destination).size();
    m_progress = 100;
    m_stage = QStringLiteral("Ready");
    m_busy = false;
    m_temp.reset();
    emit changed();
}

void LocalDownload::fail(const QString &message)
{
    m_busy = false;
    m_encodingGif = false;
    m_stage = QStringLiteral("Failed");
    m_errorText = message;
    m_temp.reset();
    emit changed();
}

void LocalDownload::cancel()
{
    if (!m_busy) return;
    m_cancelled = true;
    if (m_encodingGif) m_gifTools.cancel();
    else m_process.kill();
    m_busy = false;
    m_encodingGif = false;
    m_stage = QStringLiteral("Cancelled");
    if (m_process.state() == QProcess::NotRunning && !m_gifTools.busy()) m_temp.reset();
    emit changed();
}
