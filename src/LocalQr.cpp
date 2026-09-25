#include "LocalQr.h"
#include "MediaTools.h"
#include <QDir>
#include <QFileInfo>
#include <QPainter>
#include <QSaveFile>
#include <QUrlQuery>

LocalQr::LocalQr(QObject *parent)
    : QObject(parent), m_qrencode(qrencodeExecutable())
{
}

LocalQr::~LocalQr()
{
    if (m_process && m_process->state() != QProcess::NotRunning) {
        m_process->kill();
        m_process->waitForFinished(2000);
    }
}

bool LocalQr::available() const { return !m_qrencode.isEmpty(); }
bool LocalQr::busy() const { return m_process != nullptr; }
QString LocalQr::stage() const { return m_stage; }
QString LocalQr::errorText() const { return m_errorText; }
QUrl LocalQr::outputUrl() const { return m_outputUrl; }
int LocalQr::modules() const { return m_matrix.size(); }
int LocalQr::revision() const { return m_revision; }

QVector<QVector<bool>> LocalQr::parseAscii(const QByteArray &text)
{
    QList<QByteArray> lines;
    for (auto line : text.split('\n')) {
        while (line.endsWith('\r'))
            line.chop(1);
        if (!line.trimmed().isEmpty())
            lines.append(line);
    }
    // A QR code is square: one text row per module row, two characters per module.
    const int count = lines.size();
    QVector<QVector<bool>> matrix(count, QVector<bool>(count, false));
    for (int y = 0; y < count; ++y) {
        if (lines[y].size() > count * 2)
            return {};
        for (int x = 0; x < count && 2 * x < lines[y].size(); ++x)
            matrix[y][x] = lines[y].at(2 * x) == '#';
    }
    return matrix;
}

void LocalQr::update(const QString &content, const QString &level)
{
    if (m_process) {
        m_process->disconnect(this);
        m_process->kill();
        m_process->deleteLater();
        m_process = nullptr;
    }
    m_errorText.clear();
    m_outputUrl = QUrl();
    if (content.isEmpty()) {
        m_matrix.clear();
        ++m_revision;
        m_stage.clear();
        emit changed();
        return;
    }
    if (!available()) {
        fail(QStringLiteral("QR codes need qrencode on this device. Add it to PATH or set KADRON_QRENCODE."));
        return;
    }
    const auto ec = QStringList{"L", "M", "Q", "H"}.contains(level.toUpper()) ? level.toUpper() : QStringLiteral("M");
    auto *process = new QProcess(this);
    m_process = process;
    connect(process, &QProcess::started, process, [process, content] {
        process->write(content.toUtf8());
        process->closeWriteChannel();
    });
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        process->deleteLater();
        if (m_process != process)
            return;
        m_process = nullptr;
        const auto matrix = parseAscii(process->readAllStandardOutput());
        if (status != QProcess::NormalExit || code != 0 || matrix.isEmpty()) {
            const auto detail = QString::fromUtf8(process->readAllStandardError()).trimmed();
            fail(detail.isEmpty() ? QStringLiteral("This text is too long for a QR code at this error correction.") : detail.right(300));
            return;
        }
        m_matrix = matrix;
        ++m_revision;
        m_stage = QStringLiteral("Ready");
        emit changed();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || m_process != process) return;
        m_process = nullptr;
        process->deleteLater();
        fail(QStringLiteral("Could not start qrencode."));
    });
    m_stage = QStringLiteral("Encoding");
    emit changed();
    process->start(m_qrencode, {"-t", "ASCII", "-m", "0", "-l", ec, "-8"});
}

QImage LocalQr::render(int size, const QColor &foreground, const QColor &background, int margin) const
{
    const int count = m_matrix.size();
    if (count == 0 || size <= 0)
        return {};
    QImage image(size, size, QImage::Format_ARGB32);
    image.fill(background);
    const double cell = double(size) / (count + 2 * margin);
    QPainter painter(&image);
    painter.setPen(Qt::NoPen);
    painter.setBrush(foreground);
    for (int y = 0; y < count; ++y)
        for (int x = 0; x < count; ++x)
            if (m_matrix[y][x]) {
                // Snap edges to whole pixels so neighbouring modules never leave seams.
                const int left = qRound((x + margin) * cell), top = qRound((y + margin) * cell);
                const int right = qRound((x + margin + 1) * cell), bottom = qRound((y + margin + 1) * cell);
                painter.drawRect(left, top, right - left, bottom - top);
            }
    return image;
}

QString LocalQr::svg(const QColor &foreground, const QColor &background, int margin) const
{
    const int count = m_matrix.size();
    const int total = count + 2 * margin;
    QString path;
    for (int y = 0; y < count; ++y)
        for (int x = 0; x < count; ++x)
            if (m_matrix[y][x])
                path += QStringLiteral("M%1 %2h1v1h-1z").arg(x + margin).arg(y + margin);
    return QStringLiteral("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 %1 %1\" shape-rendering=\"crispEdges\">"
                          "<rect width=\"%1\" height=\"%1\" fill=\"%2\"/><path d=\"%3\" fill=\"%4\"/></svg>\n")
        .arg(total).arg(background.name(), path, foreground.name());
}

bool LocalQr::save(const QUrl &destination, int size, const QColor &foreground, const QColor &background, int margin)
{
    m_errorText.clear();
    m_outputUrl = QUrl();
    const QFileInfo output(destination.toLocalFile());
    const auto suffix = output.suffix().toLower();
    if (m_matrix.isEmpty() || !destination.isLocalFile() || !(suffix == "png" || suffix == "svg")
        || !output.dir().exists() || output.exists() || size < 64 || size > 4096) {
        fail(m_matrix.isEmpty() ? QStringLiteral("Type some text first.")
                                : QStringLiteral("Choose a new .png or .svg file. Existing files are never overwritten."));
        return false;
    }
    QSaveFile file(output.absoluteFilePath());
    bool ok = file.open(QIODevice::WriteOnly);
    if (ok && suffix == "svg")
        ok = file.write(svg(foreground, background, margin).toUtf8()) > 0;
    else if (ok)
        ok = render(size, foreground, background, margin).save(&file, "PNG");
    if (!ok || !file.commit()) {
        fail(QStringLiteral("Could not save the QR code."));
        return false;
    }
    m_outputUrl = QUrl::fromLocalFile(output.absoluteFilePath());
    m_stage = QStringLiteral("Saved");
    emit changed();
    return true;
}

void LocalQr::fail(const QString &message)
{
    m_stage = QStringLiteral("Failed");
    m_errorText = message.isEmpty() ? QStringLiteral("QR generation failed.") : message;
    emit changed();
}

void LocalQr::cancel()
{
    if (!m_process) return;
    m_process->disconnect(this);
    m_process->kill();
    m_process->deleteLater();
    m_process = nullptr;
    m_stage.clear();
    emit changed();
}

QrImageProvider::QrImageProvider(LocalQr *qr)
    : QQuickImageProvider(QQuickImageProvider::Image), m_qr(qr)
{
}

QImage QrImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    const QUrlQuery query(id.section('?', 1));
    const QColor foreground(QLatin1Char('#') + query.queryItemValue("fg"));
    const QColor background(QLatin1Char('#') + query.queryItemValue("bg"));
    int edge = qBound(64, query.queryItemValue("size").toInt(), 2048);
    if (requestedSize.isValid() && requestedSize.width() > 0)
        edge = qBound(64, requestedSize.width(), 2048);
    const auto image = m_qr ? m_qr->render(edge, foreground.isValid() ? foreground : Qt::black,
                                           background.isValid() ? background : Qt::white)
                            : QImage();
    if (size)
        *size = image.size();
    return image;
}
