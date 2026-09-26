#include "LocalPdfTools.h"
#include "MediaTools.h"
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QPainter>
#include <QPageSize>
#include <QPdfWriter>
#include <QRegularExpression>
#include <QUuid>
#include <QtConcurrent>

LocalPdfTools::LocalPdfTools(QObject *parent)
    : QObject(parent), m_qpdf(qpdfExecutable()), m_pdftoppm(pdftoppmExecutable())
{
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        m_errorBuffer += m_process.readAllStandardError();
        if (m_errorBuffer.size() > 4096) m_errorBuffer = m_errorBuffer.right(4096);
    });
    connect(&m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        if (!m_busy) {
            QFile::remove(m_partial);
            return;
        }
        if (code == 0 && status == QProcess::NormalExit) finish();
        else fail(QString::fromUtf8(m_errorBuffer).trimmed().right(700).isEmpty()
                      ? QStringLiteral("PDF processing failed. Check the selected pages and document.")
                      : QString::fromUtf8(m_errorBuffer).trimmed().right(700));
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart && m_busy)
            fail(QStringLiteral("Could not start qpdf. Check its installation."));
    });
    connect(&m_writer, &QFutureWatcher<QString>::finished, this, [this] {
        if (!m_busy) {
            QFile::remove(m_partial);
            return;
        }
        const auto error = m_writer.result();
        if (!error.isEmpty()) fail(error);
        else finish();
    });
}

LocalPdfTools::~LocalPdfTools()
{
    m_cancelled = true;
    if (m_process.state() != QProcess::NotRunning) {
        m_process.kill();
        m_process.waitForFinished(5000);
    }
    m_writer.waitForFinished();
    if (!m_partial.isEmpty() && m_busy) QFile::remove(m_partial);
}

bool LocalPdfTools::qpdfAvailable() const { return !m_qpdf.isEmpty(); }
bool LocalPdfTools::pagesAvailable() const { return !m_pdftoppm.isEmpty() && !m_qpdf.isEmpty(); }
bool LocalPdfTools::loadingPages() const { return m_renderer != nullptr; }
QUrl LocalPdfTools::pagesDocument() const { return m_pagesDocument; }
QStringList LocalPdfTools::pageImages() const { return m_pageImages; }
QString LocalPdfTools::pagesError() const { return m_pagesError; }
QVariantMap LocalPdfTools::covers() const { return m_covers; }

void LocalPdfTools::loadCovers(const QVariantList &documents)
{
    if (m_pdftoppm.isEmpty())
        return;
    if (!m_coversDir)
        m_coversDir = std::make_unique<QTemporaryDir>();
    for (const auto &entry : documents) {
        const auto url = entry.toUrl();
        const auto key = url.toString();
        const QFileInfo file(url.toLocalFile());
        if (!url.isLocalFile() || !file.isFile() || m_covers.contains(key) || m_coversPending.contains(key))
            continue;
        m_coversPending.insert(key);
        const auto target = m_coversDir->path() + "/" + QUuid::createUuid().toString(QUuid::WithoutBraces);
        const auto pdftoppm = m_pdftoppm;
        const auto qpdf = m_qpdf;
        const auto path = file.absoluteFilePath();
        auto *watcher = new QFutureWatcher<QVariantMap>(this);
        connect(watcher, &QFutureWatcher<QVariantMap>::finished, this, [this, watcher, key] {
            watcher->deleteLater();
            m_coversPending.remove(key);
            m_covers.insert(key, watcher->result());
            emit coversChanged();
        });
        watcher->setFuture(QtConcurrent::run([pdftoppm, qpdf, path, target] {
            QVariantMap cover;
            QProcess render;
            render.start(pdftoppm, {"-png", "-singlefile", "-f", "1", "-l", "1", "-scale-to", "280", path, target});
            render.waitForFinished(30000);
            if (QFileInfo::exists(target + ".png"))
                cover.insert("image", QUrl::fromLocalFile(target + ".png"));
            else
                cover.insert("error", QString::fromUtf8(render.readAllStandardError()).contains("password", Qt::CaseInsensitive)
                                          ? QStringLiteral("Password protected") : QStringLiteral("Cannot read this PDF"));
            if (!qpdf.isEmpty()) {
                QProcess count;
                count.start(qpdf, {"--show-npages", path});
                if (count.waitForFinished(15000) && count.exitCode() == 0)
                    cover.insert("pages", QString::fromUtf8(count.readAllStandardOutput()).trimmed().toInt());
            }
            return cover;
        }));
    }
}

QString LocalPdfTools::pagesToRange(const QVariantList &pages)
{
    QList<int> sorted;
    for (const auto &page : pages)
        sorted << page.toInt();
    std::sort(sorted.begin(), sorted.end());
    sorted.erase(std::unique(sorted.begin(), sorted.end()), sorted.end());
    QStringList parts;
    for (int i = 0; i < sorted.size(); ++i) {
        const int start = sorted.at(i);
        int end = start;
        while (i + 1 < sorted.size() && sorted.at(i + 1) == end + 1)
            end = sorted.at(++i);
        parts << (end > start ? QStringLiteral("%1-%2").arg(start).arg(end) : QString::number(start));
    }
    return parts.join(", ");
}

QVariantList LocalPdfTools::rangeToPages(const QString &range, int pageCount)
{
    QList<int> pages;
    for (const auto &rawPart : range.split(',', Qt::SkipEmptyParts)) {
        const auto part = rawPart.trimmed();
        const auto bounds = part.split('-');
        bool okStart = false, okEnd = true;
        const int start = bounds.value(0).trimmed().toInt(&okStart);
        const int end = bounds.size() > 1 ? bounds.value(1).trimmed().toInt(&okEnd) : start;
        if (!okStart || !okEnd || bounds.size() > 2)
            continue;
        for (int page = qMax(1, start); page <= qMin(pageCount, end); ++page)
            if (!pages.contains(page))
                pages << page;
    }
    std::sort(pages.begin(), pages.end());
    QVariantList result;
    for (const int page : pages)
        result << page;
    return result;
}

void LocalPdfTools::clearPages()
{
    ++m_pagesGeneration;
    if (m_renderer) {
        m_renderer->disconnect(this);
        m_renderer->kill();
        m_renderer->deleteLater();
        m_renderer = nullptr;
    }
    m_pagesDocument = QUrl();
    m_pageImages.clear();
    m_pagesError.clear();
    m_pagesDir.reset();
    emit pagesChanged();
}

void LocalPdfTools::loadPages(const QUrl &document)
{
    clearPages();
    const QFileInfo file(document.toLocalFile());
    if (!document.isLocalFile() || !file.isFile() || file.suffix().compare("pdf", Qt::CaseInsensitive) != 0) {
        m_pagesError = QStringLiteral("Choose a PDF document.");
        emit pagesChanged();
        return;
    }
    if (!pagesAvailable()) {
        m_pagesError = QStringLiteral("The page editor needs poppler (pdftoppm) and qpdf on this device.");
        emit pagesChanged();
        return;
    }
    m_pagesDir = std::make_unique<QTemporaryDir>();
    m_pagesDocument = QUrl::fromLocalFile(file.absoluteFilePath());
    const auto generation = m_pagesGeneration;
    const auto directory = m_pagesDir->path();
    auto *process = new QProcess(this);
    m_renderer = process;
    connect(process, &QProcess::finished, this, [this, process, generation, directory](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (generation != m_pagesGeneration)
            return;
        m_renderer = nullptr;
        QStringList images;
        const auto entries = QDir(directory).entryInfoList({"p-*.png"}, QDir::Files);
        QMap<int, QString> ordered;
        for (const auto &entry : entries)
            ordered.insert(entry.completeBaseName().section('-', -1).toInt(), QUrl::fromLocalFile(entry.absoluteFilePath()).toString());
        for (const auto &image : std::as_const(ordered))
            images.append(image);
        if (images.isEmpty() || status != QProcess::NormalExit || code != 0) {
            const auto detail = QString::fromUtf8(process->readAllStandardError()).trimmed();
            m_pagesError = detail.contains("password", Qt::CaseInsensitive)
                ? QStringLiteral("This PDF is password protected.")
                : QStringLiteral("Could not read this PDF.");
        }
        m_pageImages = images;
        emit pagesChanged();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, generation](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || generation != m_pagesGeneration) return;
        m_renderer = nullptr;
        process->deleteLater();
        m_pagesError = QStringLiteral("Could not start pdftoppm.");
        emit pagesChanged();
    });
    process->start(m_pdftoppm, {"-png", "-scale-to", "300", file.absoluteFilePath(), directory + "/p"});
    emit pagesChanged();
}

void LocalPdfTools::renderPreview(int page)
{
    if (!m_pagesDir || m_pagesDocument.isEmpty() || page < 1 || page > m_pageImages.size())
        return;
    const auto target = m_pagesDir->path() + QStringLiteral("/preview-%1").arg(page);
    if (QFileInfo::exists(target + ".png")) {
        emit pagePreviewReady(page, QUrl::fromLocalFile(target + ".png"));
        return;
    }
    const auto generation = m_pagesGeneration;
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, page, target, generation] {
        process->deleteLater();
        if (generation == m_pagesGeneration && QFileInfo::exists(target + ".png"))
            emit pagePreviewReady(page, QUrl::fromLocalFile(target + ".png"));
    });
    process->start(m_pdftoppm, {"-png", "-singlefile", "-f", QString::number(page), "-l", QString::number(page),
                                "-scale-to", "1600", m_pagesDocument.toLocalFile(), target});
}

QStringList LocalPdfTools::composeArguments(const QString &source, const QVariantList &pages, const QString &output)
{
    QStringList order, rotations;
    for (int index = 0; index < pages.size(); ++index) {
        const auto entry = pages.at(index).toMap();
        order << QString::number(entry.value("page").toInt());
        const auto rotation = ((entry.value("rotation").toInt() % 360) + 360) % 360;
        if (rotation != 0)
            rotations << QStringLiteral("--rotate=+%1:%2").arg(rotation).arg(index + 1);
    }
    return QStringList{"--empty", "--pages", source, order.join(','), "--"} + rotations + QStringList{output};
}

bool LocalPdfTools::compose(const QVariantList &pages, const QUrl &destination)
{
    if (m_busy)
        return false;
    m_errorText.clear();
    m_outputUrl = QUrl();
    m_outputBytes = 0;
    const QFileInfo output(destination.toLocalFile());
    bool valid = !pages.isEmpty() && !m_pagesDocument.isEmpty() && destination.isLocalFile()
                 && output.suffix().compare("pdf", Qt::CaseInsensitive) == 0 && output.dir().exists() && !output.exists();
    for (const auto &entry : pages) {
        const auto page = entry.toMap().value("page").toInt();
        valid = valid && page >= 1 && page <= m_pageImages.size();
    }
    if (!valid || !qpdfAvailable()) {
        fail(!qpdfAvailable() ? QStringLiteral("Saving edited pages needs qpdf on this device.")
                              : pages.isEmpty() ? QStringLiteral("Keep at least one page.")
                                                : QStringLiteral("Choose a new PDF file. Existing files are never overwritten."));
        return false;
    }
    m_destination = output.absoluteFilePath();
    m_partial = output.absolutePath() + "/." + output.completeBaseName() + "."
        + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".part.pdf";
    m_errorBuffer.clear();
    m_cancelled = false;
    m_busy = true;
    m_stage = QStringLiteral("Saving PDF on this device");
    emit changed();
    m_process.start(m_qpdf, composeArguments(m_pagesDocument.toLocalFile(), pages, m_partial));
    return true;
}
bool LocalPdfTools::busy() const { return m_busy; }
QString LocalPdfTools::stage() const { return m_stage; }
QString LocalPdfTools::errorText() const { return m_errorText; }
QUrl LocalPdfTools::outputUrl() const { return m_outputUrl; }
qint64 LocalPdfTools::outputBytes() const { return m_outputBytes; }

bool LocalPdfTools::process(const QString &action, const QVariantList &files, const QString &pages,
                            int rotation, const QUrl &destination)
{
    if (m_busy) return false;
    m_errorText.clear();
    m_outputUrl = QUrl();
    m_outputBytes = 0;
    const QFileInfo output(destination.toLocalFile());
    const bool images = action == "images-to-pdf";
    const bool needsPages = action == "split" || action == "remove-pages" || action == "reorder";
    static const QRegularExpression pageRange("^\\d+(?:-\\d+)?(?:,\\d+(?:-\\d+)?)*$");
    QStringList paths;
    for (const auto &item : files) {
        const QUrl url = item.toUrl();
        if (!url.isLocalFile() || !QFileInfo(url.toLocalFile()).isFile()) {
            fail(QStringLiteral("Choose existing local files."));
            return false;
        }
        paths << QFileInfo(url.toLocalFile()).absoluteFilePath();
    }
    if (paths.isEmpty() || (action != "merge" && action != "images-to-pdf" && paths.size() != 1)
        || !destination.isLocalFile() || output.suffix().compare("pdf", Qt::CaseInsensitive) != 0
        || !output.dir().exists() || output.exists()
        || (!images && !qpdfAvailable())
        || (needsPages && !pageRange.match(pages.trimmed()).hasMatch())
        || (action == "rotate" && !pages.trimmed().isEmpty() && !pageRange.match(pages.trimmed()).hasMatch())
        || (action == "rotate" && !QList<int>{90, 180, 270}.contains(rotation))
        || !QStringList{"merge", "split", "rotate", "remove-pages", "reorder", "images-to-pdf"}.contains(action)) {
        fail(!images && !qpdfAvailable()
                 ? QStringLiteral("Local PDF editing needs qpdf. Add it to PATH or set KADRON_QPDF. Images to PDF works without it.")
                 : QStringLiteral("Check the files, page range, and output path. Existing files are never overwritten."));
        return false;
    }
    for (const auto &path : paths) {
        const auto ext = QFileInfo(path).suffix().toLower();
        if (images ? !QStringList{"jpg", "jpeg", "png", "webp", "bmp", "tif", "tiff"}.contains(ext) : ext != "pdf") {
            fail(QStringLiteral("Choose the correct file type for this PDF operation."));
            return false;
        }
    }
    m_destination = output.absoluteFilePath();
    m_partial = output.absolutePath() + "/." + output.completeBaseName() + "."
        + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".part.pdf";
    m_errorBuffer.clear();
    m_cancelled = false;
    m_busy = true;
    m_stage = images ? QStringLiteral("Creating PDF on this device") : QStringLiteral("Processing PDF on this device");
    emit changed();

    if (images) {
        m_writer.setFuture(QtConcurrent::run([this, paths, partial = m_partial]() -> QString {
            QPdfWriter writer(partial);
            writer.setPageSize(QPageSize(QPageSize::A4));
            writer.setResolution(150);
            QPainter painter;
            if (!painter.begin(&writer)) return QStringLiteral("Could not create the PDF file.");
            for (int index = 0; index < paths.size(); ++index) {
                if (m_cancelled) { painter.end(); return QStringLiteral("Cancelled"); }
                QImageReader reader(paths.at(index));
                reader.setAutoTransform(true);
                const auto image = reader.read();
                if (image.isNull()) { painter.end(); return QStringLiteral("Could not read image: ") + QFileInfo(paths.at(index)).fileName(); }
                if (index > 0 && !writer.newPage()) { painter.end(); return QStringLiteral("Could not add a PDF page."); }
                const QRectF page(0, 0, writer.width(), writer.height());
                const QSizeF fitted = image.size().scaled(page.size().toSize(), Qt::KeepAspectRatio);
                painter.drawImage(QRectF((page.width() - fitted.width()) / 2, (page.height() - fitted.height()) / 2,
                                         fitted.width(), fitted.height()), image);
            }
            painter.end();
            return QString();
        }));
        return true;
    }

    QStringList arguments;
    const auto range = pages.trimmed();
    if (action == "merge") {
        arguments = {"--empty", "--pages"};
        arguments += paths;
        arguments += {"--", m_partial};
    } else if (action == "rotate") {
        arguments = {paths.first(), m_partial, "--rotate=+" + QString::number(rotation)
                     + (range.isEmpty() ? QString() : ":" + range)};
    } else {
        arguments = {paths.first(), "--pages", "."};
        if (action == "remove-pages") {
            QStringList excludes;
            for (const auto &part : range.split(',')) excludes << "x" + part;
            arguments << "1-z," + excludes.join(',');
        } else {
            arguments << range;
        }
        arguments += {"--", m_partial};
    }
    m_process.start(m_qpdf, arguments);
    return true;
}

void LocalPdfTools::finish()
{
    if (!QFileInfo(m_partial).isFile() || QFileInfo::exists(m_destination)
        || !QFile::rename(m_partial, m_destination)) {
        fail(QStringLiteral("Could not save the processed PDF."));
        return;
    }
    m_outputUrl = QUrl::fromLocalFile(m_destination);
    m_outputBytes = QFileInfo(m_destination).size();
    m_busy = false;
    m_stage = QStringLiteral("Ready");
    emit changed();
}

void LocalPdfTools::fail(const QString &message)
{
    m_busy = false;
    m_stage = QStringLiteral("Failed");
    m_errorText = message;
    if (!m_writer.isRunning()) QFile::remove(m_partial);
    emit changed();
}

void LocalPdfTools::cancel()
{
    if (!m_busy) return;
    m_cancelled = true;
    if (m_process.state() != QProcess::NotRunning) m_process.kill();
    m_busy = false;
    m_stage = QStringLiteral("Cancelled");
    if (!m_writer.isRunning() && m_process.state() == QProcess::NotRunning) QFile::remove(m_partial);
    emit changed();
}
