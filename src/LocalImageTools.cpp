#include "LocalImageTools.h"
#include "MediaTools.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtConcurrent>
#include <QtEndian>
#include <QUuid>
#include <cmath>

namespace {

const QStringList kImageExtensions{"jpg", "jpeg", "png", "webp", "avif", "heic", "heif", "bmp", "tif", "tiff", "gif"};

QString number(double value)
{
    return QString::number(value, 'f', 6);
}

// Runs a tool to completion, polling so a cancel can stop it. Returns the
// error output on failure, an empty string on success.
QString run(const QString &program, const QStringList &arguments, const std::atomic_bool *cancelled,
            QByteArray *output = nullptr, int timeoutMs = 300000)
{
    QProcess process;
    process.start(program, arguments);
    if (!process.waitForStarted(10000))
        return QStringLiteral("Could not start %1.").arg(QFileInfo(program).baseName());
    QElapsedTimer timer;
    timer.start();
    while (!process.waitForFinished(100)) {
        if ((cancelled && cancelled->load()) || timer.elapsed() > timeoutMs) {
            process.kill();
            process.waitForFinished(2000);
            return cancelled && cancelled->load() ? QStringLiteral("Cancelled") : QStringLiteral("Timed out");
        }
    }
    if (output)
        *output = process.readAllStandardOutput();
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        const auto details = QString::fromUtf8(process.readAllStandardError()).trimmed();
        return details.isEmpty() ? QStringLiteral("FFmpeg could not process this image.") : details.right(400);
    }
    return {};
}

bool hasAlphaChannel(const QString &pixelFormat)
{
    static const QStringList alpha{"rgba", "bgra", "argb", "abgr", "ya8", "ya16", "pal8", "gbrap", "rgba64", "bgra64"};
    return alpha.contains(pixelFormat) || pixelFormat.startsWith("yuva") || pixelFormat.startsWith("gbrap")
           || pixelFormat.startsWith("rgba64") || pixelFormat.startsWith("ya16");
}

// Scale that fits the longest side into `edge` without enlarging.
QString fitLongEdge(int edge)
{
    return QStringLiteral("scale=w='if(gte(iw,ih),min(iw,%1),-1)':h='if(gte(iw,ih),-1,min(ih,%1))':flags=lanczos").arg(edge);
}

// ---- EXIF ---------------------------------------------------------------

struct Tiff {
    const uchar *data = nullptr;
    qsizetype size = 0;
    bool little = true;

    bool in(qsizetype offset, qsizetype length) const { return offset >= 0 && length >= 0 && offset + length <= size; }
    quint16 u16(qsizetype offset) const
    {
        if (!in(offset, 2)) return 0;
        return little ? qFromLittleEndian<quint16>(data + offset) : qFromBigEndian<quint16>(data + offset);
    }
    quint32 u32(qsizetype offset) const
    {
        if (!in(offset, 4)) return 0;
        return little ? qFromLittleEndian<quint32>(data + offset) : qFromBigEndian<quint32>(data + offset);
    }
};

struct Entry {
    quint16 type = 0;
    quint32 count = 0;
    qsizetype valueOffset = 0;   // where the value lives (inline or pointed to)
};

// Reads the entries of the IFD at `offset` into tag -> entry.
QHash<quint16, Entry> readIfd(const Tiff &tiff, qsizetype offset)
{
    QHash<quint16, Entry> entries;
    const quint16 count = tiff.u16(offset);
    if (count == 0 || count > 512 || !tiff.in(offset + 2, count * 12))
        return entries;
    static const int sizes[] = {0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8};
    for (int i = 0; i < count; ++i) {
        const qsizetype at = offset + 2 + i * 12;
        Entry entry;
        entry.type = tiff.u16(at + 2);
        entry.count = tiff.u32(at + 4);
        const int unit = entry.type < 13 ? sizes[entry.type] : 0;
        const qint64 bytes = qint64(unit) * entry.count;
        entry.valueOffset = bytes <= 4 ? at + 8 : tiff.u32(at + 8);
        if (unit > 0 && tiff.in(entry.valueOffset, bytes))
            entries.insert(tiff.u16(at), entry);
    }
    return entries;
}

QString asciiValue(const Tiff &tiff, const QHash<quint16, Entry> &ifd, quint16 tag)
{
    const auto entry = ifd.value(tag);
    if (entry.type != 2 || entry.count == 0)
        return {};
    return QString::fromLatin1(reinterpret_cast<const char *>(tiff.data + entry.valueOffset), entry.count)
        .section(QChar(0), 0, 0).trimmed();
}

double rationalAt(const Tiff &tiff, qsizetype offset)
{
    const quint32 denominator = tiff.u32(offset + 4);
    return denominator ? double(tiff.u32(offset)) / denominator : 0;
}

// Degrees from a GPS coordinate (three rationals) and its N/S/E/W reference.
double coordinate(const Tiff &tiff, const QHash<quint16, Entry> &gps, quint16 valueTag, quint16 refTag, bool *ok)
{
    const auto entry = gps.value(valueTag);
    if (entry.type != 5 || entry.count < 3) {
        *ok = false;
        return 0;
    }
    const double degrees = rationalAt(tiff, entry.valueOffset) + rationalAt(tiff, entry.valueOffset + 8) / 60.0
                           + rationalAt(tiff, entry.valueOffset + 16) / 3600.0;
    const auto ref = asciiValue(tiff, gps, refTag).toUpper();
    return ref == "S" || ref == "W" ? -degrees : degrees;
}

// Where the TIFF structure of the EXIF block starts, or -1.
qsizetype findTiff(const QByteArray &file)
{
    const auto isTiff = [&file](qsizetype at) {
        return at >= 0 && at + 8 <= file.size()
               && (file.mid(at, 4) == QByteArray("II*\0", 4) || file.mid(at, 4) == QByteArray("MM\0*", 4));
    };
    // JPEG APP1, HEIC and AVIF Exif items, WebP chunks written with the prefix.
    for (qsizetype at = file.indexOf(QByteArray("Exif\0\0", 6)); at >= 0; at = file.indexOf(QByteArray("Exif\0\0", 6), at + 1))
        if (isTiff(at + 6))
            return at + 6;
    // PNG eXIf and WebP EXIF chunks hold the TIFF data right after the chunk header.
    for (const auto &chunk : {QByteArray("eXIf"), QByteArray("EXIF")}) {
        const auto at = file.indexOf(chunk);
        if (at >= 0 && isTiff(at + 4)) return at + 4;
        if (at >= 0 && isTiff(at + 8)) return at + 8;
    }
    return -1;
}

} // namespace

LocalImageTools::LocalImageTools(QObject *parent)
    : QObject(parent), m_ffmpeg(ffmpegExecutable()), m_ffprobe(ffprobeExecutable())
{
}

LocalImageTools::~LocalImageTools()
{
    if (m_cancelled)
        m_cancelled->store(true);
}

bool LocalImageTools::available() const { return !m_ffmpeg.isEmpty() && !m_ffprobe.isEmpty(); }
QVariantMap LocalImageTools::infos() const { return m_infos; }
bool LocalImageTools::busy() const { return m_busy; }
int LocalImageTools::progress() const { return m_progress; }
QString LocalImageTools::stage() const { return m_stage; }
QString LocalImageTools::errorText() const { return m_errorText; }
QVariantList LocalImageTools::results() const { return m_results; }
QUrl LocalImageTools::outputFolder() const { return m_outputFolder; }
QVariantMap LocalImageTools::preview() const { return m_preview; }
bool LocalImageTools::previewBusy() const { return m_previewBusy; }

bool LocalImageTools::isImageFile(const QUrl &url)
{
    return url.isLocalFile() && kImageExtensions.contains(QFileInfo(url.toLocalFile()).suffix().toLower());
}

QString LocalImageTools::workPath(const QString &name) const
{
    return m_work->filePath(name);
}

QVariantMap LocalImageTools::parseExif(const QByteArray &file)
{
    QVariantMap result;
    const auto start = findTiff(file);
    if (start < 0)
        return result;
    Tiff tiff;
    tiff.data = reinterpret_cast<const uchar *>(file.constData()) + start;
    tiff.size = file.size() - start;
    tiff.little = file.at(start) == 'I';

    const auto ifd0 = readIfd(tiff, tiff.u32(4));
    if (ifd0.contains(0x0112))
        result.insert("orientation", int(tiff.u16(ifd0.value(0x0112).valueOffset)));
    auto make = asciiValue(tiff, ifd0, 0x010F);
    const auto model = asciiValue(tiff, ifd0, 0x0110);
    // Models often repeat the maker ("Canon EOS R6"); don't say it twice.
    const auto camera = model.startsWith(make, Qt::CaseInsensitive) || make.isEmpty() ? model : make + " " + model;
    if (!camera.trimmed().isEmpty())
        result.insert("camera", camera.trimmed());

    QString taken;
    if (ifd0.contains(0x8769)) {
        const auto exif = readIfd(tiff, tiff.u32(ifd0.value(0x8769).valueOffset));
        taken = asciiValue(tiff, exif, 0x9003);
    }
    if (taken.isEmpty())
        taken = asciiValue(tiff, ifd0, 0x0132);
    // "2024:05:17 14:03:22" -> "2024-05-17 14:03"
    if (taken.size() >= 16 && taken.at(4) == ':')
        result.insert("taken", taken.left(10).replace(':', '-') + " " + taken.mid(11, 5));

    if (ifd0.contains(0x8825)) {
        const auto gps = readIfd(tiff, tiff.u32(ifd0.value(0x8825).valueOffset));
        bool latOk = true, lonOk = true;
        const double latitude = coordinate(tiff, gps, 2, 1, &latOk);
        const double longitude = coordinate(tiff, gps, 4, 3, &lonOk);
        if (latOk && lonOk && (latitude != 0 || longitude != 0)) {
            result.insert("hasGps", true);
            result.insert("latitude", latitude);
            result.insert("longitude", longitude);
        }
    }
    return result;
}

QString LocalImageTools::outputFormat(const QString &requested, const QString &sourceExtension)
{
    static const QStringList formats{"jpg", "png", "webp", "avif"};
    if (formats.contains(requested))
        return requested;
    const auto ext = sourceExtension.toLower();
    if (ext == "jpg" || ext == "jpeg") return QStringLiteral("jpg");
    if (formats.contains(ext)) return ext;
    // Lossless sources stay lossless; phone photos (HEIC) become JPG.
    if (ext == "bmp" || ext == "tif" || ext == "tiff" || ext == "gif") return QStringLiteral("png");
    return QStringLiteral("jpg");
}

QString LocalImageTools::filterChain(const QVariantMap &job, bool flatten)
{
    QStringList parts;
    // Rotation and flips, as the user sees them (FFmpeg already applied EXIF orientation).
    const int rotate = ((job.value("rotate").toInt() % 360) + 360) % 360;
    if (rotate == 90) parts << "transpose=1";
    else if (rotate == 180) parts << "hflip" << "vflip";
    else if (rotate == 270) parts << "transpose=2";
    if (job.value("flipH").toBool()) parts << "hflip";
    if (job.value("flipV").toBool()) parts << "vflip";

    const double x = std::clamp(job.value("cropX", 0.0).toDouble(), 0.0, 1.0);
    const double y = std::clamp(job.value("cropY", 0.0).toDouble(), 0.0, 1.0);
    const double w = std::clamp(job.value("cropW", 1.0).toDouble(), 0.01, 1.0 - x);
    const double h = std::clamp(job.value("cropH", 1.0).toDouble(), 0.01, 1.0 - y);
    if (x > 0.0005 || y > 0.0005 || w < 0.9995 || h < 0.9995)
        parts << QStringLiteral("crop=w='max(1,trunc(iw*%1))':h='max(1,trunc(ih*%2))':x='trunc(iw*%3)':y='trunc(ih*%4)'")
                     .arg(number(w), number(h), number(x), number(y));

    const auto resize = job.value("resize").toString();
    if (resize == "long" && job.value("longEdge").toInt() > 0) {
        parts << fitLongEdge(job.value("longEdge").toInt());
    } else if (resize == "percent" && job.value("percent").toDouble() > 0 && job.value("percent").toDouble() != 100) {
        const auto scale = number(std::min(job.value("percent").toDouble(), 100.0) / 100.0);
        parts << QStringLiteral("scale=w='max(1,trunc(iw*%1))':h=-1:flags=lanczos").arg(scale);
    } else if (resize == "box" && job.value("boxWidth").toInt() > 0 && job.value("boxHeight").toInt() > 0) {
        parts << QStringLiteral("scale=w='min(iw,%1)':h='min(ih,%2)':force_original_aspect_ratio=decrease:flags=lanczos")
                     .arg(job.value("boxWidth").toInt())
                     .arg(job.value("boxHeight").toInt());
    }

    const auto base = parts.isEmpty() ? QStringLiteral("null") : parts.join(',');
    if (flatten)
        return "[0:v]" + base + ",format=rgba,split[fa][fb];[fa]drawbox=t=fill:c=white[fbg];[fbg][fb]overlay=format=auto[out]";
    return "[0:v]" + base + "[out]";
}

QStringList LocalImageTools::codecArguments(const QString &format, int quality)
{
    const int q = std::clamp(quality, 1, 100);
    if (format == "png")
        return {"-c:v", "png", "-compression_level", "9", "-f", "image2", "-update", "1"};
    if (format == "webp")
        return {"-c:v", "libwebp", "-quality", QString::number(q), "-compression_level", "4", "-f", "webp"};
    if (format == "avif") {
        const int crf = int(std::lround(10 + (100 - q) * 0.45));
        return {"-c:v", "libaom-av1", "-still-picture", "1", "-crf", QString::number(crf), "-b:v", "0",
                "-cpu-used", "6", "-row-mt", "1", "-pix_fmt", "yuv420p", "-f", "avif"};
    }
    const int scale = std::clamp(int(std::lround(2 + (100 - q) * 0.29)), 2, 31);
    return {"-c:v", "mjpeg", "-q:v", QString::number(scale), "-pix_fmt", q >= 90 ? "yuvj444p" : "yuvj420p",
            "-f", "image2", "-update", "1"};
}

QString LocalImageTools::uniqueOutputPath(const QString &folder, const QString &baseName, const QString &extension,
                                          const QSet<QString> &taken)
{
    const QDir dir(folder);
    const auto free = [&](const QString &name) {
        const auto path = dir.filePath(name);
        return !QFileInfo::exists(path) && !taken.contains(QDir::cleanPath(path).toLower()) ? path : QString();
    };
    if (auto path = free(baseName + "." + extension); !path.isEmpty())
        return path;
    if (auto path = free(baseName + " (edited)." + extension); !path.isEmpty())
        return path;
    for (int n = 2;; ++n)
        if (auto path = free(QStringLiteral("%1 (edited %2).%3").arg(baseName).arg(n).arg(extension)); !path.isEmpty())
            return path;
}

LocalImageTools::Encoded LocalImageTools::encode(const QString &ffmpeg, const QString &sourcePath, const QVariantMap &job,
                                                  const QString &format, bool hasAlpha, const QString &outputPath,
                                                  const std::atomic_bool *cancelled)
{
    Encoded result;
    // JPG and AVIF (as written here) have no alpha: transparent areas become white.
    const bool flatten = hasAlpha && (format == "jpg" || format == "avif");
    const auto graph = filterChain(job, flatten);
    const auto attempt = [&](int quality, const QString &path) -> QString {
        QStringList args{"-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-i", sourcePath,
                         "-filter_complex", graph, "-map", "[out]", "-frames:v", "1", "-map_metadata", "-1"};
        args << codecArguments(format, quality) << path;
        return run(ffmpeg, args, cancelled);
    };

    const int quality = std::clamp(job.value("quality", 82).toInt(), 1, 100);
    const qint64 target = qint64(job.value("targetKB").toDouble() * 1024);
    const auto trial = outputPath + ".try";
    const auto best = outputPath + ".best";
    QFile::remove(trial);
    QFile::remove(best);

    if (target <= 0 || format == "png") {
        result.error = attempt(quality, trial);
    } else {
        // The highest quality that fits the target size.
        result.error = attempt(quality, trial);
        if (result.error.isEmpty() && QFileInfo(trial).size() > target) {
            int low = 5, high = quality - 1, found = -1;
            for (int step = 0; step < 7 && low <= high && result.error.isEmpty(); ++step) {
                const int middle = (low + high) / 2;
                result.error = attempt(middle, trial);
                if (!result.error.isEmpty()) break;
                if (QFileInfo(trial).size() <= target) {
                    found = middle;
                    QFile::remove(best);
                    QFile::rename(trial, best);
                    low = middle + 1;
                } else {
                    high = middle - 1;
                }
            }
            if (result.error.isEmpty()) {
                if (found >= 0) {
                    QFile::remove(trial);
                    QFile::rename(best, trial);
                } else {
                    result.error = attempt(5, trial);
                    result.note = QStringLiteral("Can't get under %1 KB at this size; saved at the lowest quality.")
                                      .arg(qRound(target / 1024.0));
                }
            }
        }
    }
    QFile::remove(best);
    if (!result.error.isEmpty()) {
        QFile::remove(trial);
        return result;
    }
    QFile::remove(outputPath);
    if (!QFile::rename(trial, outputPath)) {
        QFile::remove(trial);
        result.error = QStringLiteral("Could not write %1.").arg(QFileInfo(outputPath).fileName());
        return result;
    }
    result.bytes = QFileInfo(outputPath).size();
    return result;
}

void LocalImageTools::inspect(const QVariantList &sources)
{
    if (!available())
        return;
    if (!m_work)
        m_work = std::make_unique<QTemporaryDir>();
    const auto readable = QImageReader::supportedImageFormats();
    for (const auto &entry : sources) {
        const auto url = entry.toUrl();
        const auto key = url.toString();
        if (!url.isLocalFile() || m_infos.contains(key) || m_inspecting.contains(key))
            continue;
        m_inspecting.insert(key);
        const auto path = url.toLocalFile();
        const auto ext = QFileInfo(path).suffix().toLower();
        // Formats Qt can't show get a PNG rendition for the cards and the editor.
        const bool native = readable.contains(ext.toLatin1()) && ext != "gif";
        const auto thumb = native ? QString() : workPath(QUuid::createUuid().toString(QUuid::WithoutBraces) + ".png");
        const auto ffmpeg = m_ffmpeg, ffprobe = m_ffprobe;

        auto *watcher = new QFutureWatcher<QVariantMap>(this);
        connect(watcher, &QFutureWatcher<QVariantMap>::finished, this, [this, watcher, key] {
            watcher->deleteLater();
            m_inspecting.remove(key);
            m_infos.insert(key, watcher->result());
            emit infosChanged();
        });
        watcher->setFuture(QtConcurrent::run([path, ext, thumb, native, url, ffmpeg, ffprobe] {
            QVariantMap info;
            const QFileInfo file(path);
            info.insert("name", file.fileName());
            info.insert("bytes", file.size());
            info.insert("format", ext == "jpeg" ? QStringLiteral("jpg") : ext);

            QFile handle(path);
            if (handle.open(QIODevice::ReadOnly))
                info.insert(parseExif(handle.read(32 * 1024 * 1024)));

            QByteArray json;
            const auto error = run(ffprobe, {"-v", "error", "-select_streams", "v:0", "-show_entries",
                                             "stream=codec_name,width,height,pix_fmt:stream_side_data=rotation", "-of", "json", path},
                                   nullptr, &json, 30000);
            const auto stream = QJsonDocument::fromJson(json).object().value("streams").toArray().first().toObject();
            int width = stream.value("width").toInt(), height = stream.value("height").toInt();
            if (!error.isEmpty() || width <= 0 || height <= 0) {
                info.insert("error", QStringLiteral("Can't read this image"));
                return info;
            }
            int rotation = 0;
            for (const auto &side : stream.value("side_data_list").toArray())
                rotation = side.toObject().value("rotation").toInt(rotation);
            const int orientation = info.value("orientation").toInt();
            // Sizes as the image is shown: EXIF orientation 5-8 or a quarter turn swap them.
            if (orientation >= 5 || std::abs(rotation) == 90 || std::abs(rotation) == 270)
                std::swap(width, height);
            info.insert("width", width);
            info.insert("height", height);
            info.insert("hasAlpha", hasAlphaChannel(stream.value("pix_fmt").toString()));

            if (native) {
                info.insert("thumb", url);
            } else {
                const auto renderError = run(ffmpeg, {"-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-i", path,
                                                      "-frames:v", "1", "-vf", fitLongEdge(1600), thumb},
                                             nullptr, nullptr, 60000);
                if (renderError.isEmpty())
                    info.insert("thumb", QUrl::fromLocalFile(thumb));
                else
                    info.insert("error", QStringLiteral("Can't preview this image"));
            }
            return info;
        }));
    }
}

void LocalImageTools::setPreview(const QVariantMap &preview, bool busy)
{
    m_preview = preview;
    m_previewBusy = busy;
    emit previewChanged();
}

void LocalImageTools::renderPreview(const QVariantMap &job)
{
    if (!available())
        return;
    const auto source = job.value("source").toUrl();
    if (!source.isLocalFile())
        return;
    if (m_previewBusy) {
        // One render at a time; the latest settings win.
        m_pendingPreview = job;
        return;
    }
    if (!m_work)
        m_work = std::make_unique<QTemporaryDir>();
    const int generation = ++m_previewGeneration;
    m_previewBusy = true;
    emit previewChanged();

    const auto path = source.toLocalFile();
    const auto format = outputFormat(job.value("format").toString(), QFileInfo(path).suffix());
    const bool hasAlpha = m_infos.value(source.toString()).toMap().value("hasAlpha").toBool();
    const auto stem = workPath(QStringLiteral("preview-%1").arg(generation));
    const auto ffmpeg = m_ffmpeg, ffprobe = m_ffprobe;
    const auto previous = m_preview;

    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcher<QVariantMap>::finished, this, [this, watcher, generation, previous] {
        watcher->deleteLater();
        auto result = watcher->result();
        if (generation == m_previewGeneration) {
            for (const auto &key : {"before", "after"})
                if (const auto path = previous.value(key).toUrl().toLocalFile(); !path.isEmpty())
                    QFile::remove(path);
        }
        setPreview(result, false);
        if (!m_pendingPreview.isEmpty()) {
            const auto next = m_pendingPreview;
            m_pendingPreview.clear();
            renderPreview(next);
        }
    });
    watcher->setFuture(QtConcurrent::run([=] {
        QVariantMap result{{"source", source}, {"key", job.value("key")}, {"format", format}};
        const auto output = stem + "." + format;
        const auto encoded = encode(ffmpeg, path, job, format, hasAlpha, output);
        if (!encoded.error.isEmpty()) {
            result.insert("error", encoded.error);
            return result;
        }
        result.insert("bytes", encoded.bytes);
        result.insert("note", encoded.note);

        QByteArray json;
        run(ffprobe, {"-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "json", output},
            nullptr, &json, 30000);
        const auto stream = QJsonDocument::fromJson(json).object().value("streams").toArray().first().toObject();
        result.insert("width", stream.value("width").toInt());
        result.insert("height", stream.value("height").toInt());

        // Display copies at up to 1600 px: the untouched pixels and the encoded result.
        const auto before = stem + "-before.png", after = stem + "-after.png";
        auto geometry = filterChain(job, false);
        geometry.replace("[out]", "," + fitLongEdge(1600) + "[out]");
        run(ffmpeg, {"-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-i", path, "-filter_complex", geometry,
                     "-map", "[out]", "-frames:v", "1", before}, nullptr, nullptr, 60000);
        run(ffmpeg, {"-hide_banner", "-nostdin", "-loglevel", "error", "-y", "-i", output, "-frames:v", "1",
                     "-vf", fitLongEdge(1600), after}, nullptr, nullptr, 60000);
        QFile::remove(output);
        if (QFileInfo::exists(before)) result.insert("before", QUrl::fromLocalFile(before));
        if (QFileInfo::exists(after)) result.insert("after", QUrl::fromLocalFile(after));
        return result;
    }));
}

bool LocalImageTools::process(const QVariantList &jobs, const QUrl &folder)
{
    if (m_busy)
        return false;
    const auto folderPath = folder.toLocalFile();
    if (!available() || jobs.isEmpty() || !QFileInfo(folderPath).isDir()) {
        m_errorText = !available() ? QStringLiteral("FFmpeg is required for images.")
                                   : QStringLiteral("Choose a folder to save the images in.");
        emit changed();
        return false;
    }

    // Everything the worker needs, resolved here on the UI thread.
    struct Work {
        QString source;
        QString output;
        QString format;
        bool hasAlpha = false;
        qint64 sourceBytes = 0;
        QVariantMap job;
    };
    QList<Work> work;
    QSet<QString> taken;
    for (const auto &entry : jobs) {
        const auto job = entry.toMap();
        const auto source = job.value("source").toUrl();
        const QFileInfo file(source.toLocalFile());
        const auto info = m_infos.value(source.toString()).toMap();
        Work item;
        item.source = file.absoluteFilePath();
        item.format = outputFormat(job.value("format").toString(), file.suffix());
        item.output = uniqueOutputPath(folderPath, file.completeBaseName(), item.format, taken);
        taken.insert(QDir::cleanPath(item.output).toLower());
        item.hasAlpha = info.value("hasAlpha").toBool();
        item.sourceBytes = file.size();
        item.job = job;
        work << item;
    }

    m_busy = true;
    m_progress = 0;
    m_errorText.clear();
    m_results.clear();
    m_outputFolder = folder;
    m_stage = QStringLiteral("Saving 1 of %1").arg(work.size());
    m_cancelled = std::make_shared<std::atomic_bool>(false);
    emit changed();

    const auto ffmpeg = m_ffmpeg;
    const auto cancelled = m_cancelled;
    QPointer<LocalImageTools> self(this);
    auto *watcher = new QFutureWatcher<QVariantList>(this);
    connect(watcher, &QFutureWatcher<QVariantList>::finished, this, [this, watcher] {
        watcher->deleteLater();
        m_results = watcher->result();
        const bool stopped = m_cancelled && m_cancelled->load();
        int saved = 0;
        qint64 before = 0, after = 0;
        for (const auto &entry : m_results) {
            const auto result = entry.toMap();
            if (result.value("error").toString().isEmpty()) {
                ++saved;
                before += result.value("sourceBytes").toLongLong();
                after += result.value("bytes").toLongLong();
            }
        }
        const int failed = m_results.size() - saved;
        m_busy = false;
        m_progress = 100;
        m_stage = stopped ? QStringLiteral("Stopped after %1 of %2").arg(saved).arg(m_results.size())
                          : QStringLiteral("Saved %1 %2").arg(saved).arg(saved == 1 ? "image" : "images");
        if (failed > 0 && !stopped)
            m_errorText = QStringLiteral("%1 %2 could not be saved.").arg(failed).arg(failed == 1 ? "image" : "images");
        emit changed();
    });
    watcher->setFuture(QtConcurrent::run([work, ffmpeg, cancelled, self] {
        QVariantList results;
        for (int i = 0; i < work.size(); ++i) {
            if (cancelled->load())
                break;
            const auto &item = work.at(i);
            QMetaObject::invokeMethod(qApp, [self, i, total = work.size()] {
                if (!self) return;
                self->m_stage = QStringLiteral("Saving %1 of %2").arg(i + 1).arg(total);
                self->m_progress = i * 100 / total;
                emit self->changed();
            }, Qt::QueuedConnection);
            const auto encoded = encode(ffmpeg, item.source, item.job, item.format, item.hasAlpha, item.output, cancelled.get());
            if (cancelled->load())
                break;
            results << QVariantMap{{"source", QUrl::fromLocalFile(item.source)},
                                   {"output", encoded.error.isEmpty() ? QUrl::fromLocalFile(item.output) : QUrl()},
                                   {"bytes", encoded.bytes},
                                   {"sourceBytes", item.sourceBytes},
                                   {"note", encoded.note},
                                   {"error", encoded.error}};
        }
        return results;
    }));
    return true;
}

void LocalImageTools::cancel()
{
    if (m_cancelled)
        m_cancelled->store(true);
}

void LocalImageTools::clearResults()
{
    if (m_busy)
        return;
    m_results.clear();
    m_stage.clear();
    m_errorText.clear();
    m_progress = 0;
    emit changed();
}
