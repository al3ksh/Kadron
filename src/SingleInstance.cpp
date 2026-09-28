#include "SingleInstance.h"

#include <QCollator>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQuickWindow>
#include <QUrl>
#include <QThread>
#include <QVariant>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

static QString serverName()
{
    // The temp folder is per user, and so is the pipe name built from it.
    return QStringLiteral("kadron-%1").arg(qHash(QDir::tempPath()), 0, 16);
}

SingleInstance::Request SingleInstance::parse(const QStringList &arguments)
{
    Request request;
    for (int i = 1; i < arguments.size(); ++i) {
        const auto &argument = arguments.at(i);
        if (argument.startsWith(QLatin1String("--tool=")))
            request.tool = argument.mid(7);
        else if (!argument.startsWith(QLatin1String("--")) && !argument.startsWith(QLatin1Char('/')))
            request.files << QFileInfo(argument).absoluteFilePath();
    }
    if (request.tool.isEmpty() && !request.files.isEmpty())
        request.tool = request.files.size() == 1 && QFileInfo(request.files.first()).suffix().compare("kadr", Qt::CaseInsensitive) == 0
                           ? QStringLiteral("project")
                           : QStringLiteral("edit");
    return request;
}

SingleInstance::SingleInstance(QObject *parent)
    : QObject(parent)
    , m_lock(QDir::temp().filePath(serverName() + QStringLiteral(".lock")))
{
    m_batch.setSingleShot(true);
    m_batch.setInterval(350);
    connect(&m_batch, &QTimer::timeout, this, &SingleInstance::deliver);
}

SingleInstance::~SingleInstance() = default;

bool SingleInstance::claim()
{
    if (!m_lock.tryLock(0))
        return false;
    QLocalServer::removeServer(serverName());
    m_server = new QLocalServer(this);
    m_server->setSocketOptions(QLocalServer::UserAccessOption);
    connect(m_server, &QLocalServer::newConnection, this, [this] {
        while (auto *socket = m_server->nextPendingConnection()) {
            connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QLocalSocket::readyRead, this, [this, socket] {
                if (!socket->canReadLine())
                    return;
                const auto message = QJsonDocument::fromJson(socket->readLine()).object();
                Request request;
                request.tool = message.value("tool").toString();
                for (const auto &file : message.value("files").toArray())
                    request.files << file.toString();
                socket->write("ok\n");
                socket->flush();
                take(request, true);
            });
        }
    });
    m_server->listen(serverName());
    return true;
}

bool SingleInstance::forward(const Request &request)
{
    QJsonArray files;
    for (const auto &file : request.files)
        files << file;
    const auto message = QJsonDocument(QJsonObject { { "tool", request.tool }, { "files", files } })
                             .toJson(QJsonDocument::Compact) + '\n';
#ifdef Q_OS_WIN
    // Lets the running Kadron come to the front instead of flashing in the taskbar.
    AllowSetForegroundWindow(ASFW_ANY);
#endif
    // The first Kadron may still be starting; give it a moment to listen.
    for (int attempt = 0; attempt < 40; ++attempt) {
        QLocalSocket socket;
        socket.connectToServer(serverName());
        if (socket.waitForConnected(250)) {
            socket.write(message);
            // A pipe write can finish at once, and then this reports false; the
            // answer below is what counts. The first Kadron replies once loaded.
            socket.waitForBytesWritten(3000);
            return socket.waitForReadyRead(20000);
        }
        QThread::msleep(100);
    }
    return false;
}

void SingleInstance::take(const Request &request, bool raise)
{
    // A launch without files only asks for the window.
    if (!request.files.isEmpty())
        m_pending << request;
    m_raise = m_raise || raise;
    m_batch.start();
}

void SingleInstance::attach(QQuickWindow *window)
{
    m_window = window;
    if (!m_pending.isEmpty())
        m_batch.start();
}

void SingleInstance::deliver()
{
    if (!m_window)
        return;
    // Same tool, one batch, in the order the files arrived.
    QStringList order;
    QHash<QString, QVariantList> batches;
    for (const auto &request : std::as_const(m_pending)) {
        if (!order.contains(request.tool))
            order << request.tool;
        for (const auto &file : request.files) {
            const QVariant url = QUrl::fromLocalFile(file);
            if (!batches[request.tool].contains(url))
                batches[request.tool] << url;
        }
    }
    m_pending.clear();
    // Explorer starts them in no particular order; sort like it lists them.
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    for (auto &batch : batches)
        std::sort(batch.begin(), batch.end(), [&collator](const QVariant &a, const QVariant &b) {
            return collator.compare(a.toUrl().fileName(), b.toUrl().fileName()) < 0;
        });
    for (const auto &tool : std::as_const(order))
        QMetaObject::invokeMethod(m_window, "openWith", Q_ARG(QVariant, tool), Q_ARG(QVariant, QVariant(batches.value(tool))));
    if (std::exchange(m_raise, false)) {
        // Hidden means closed to the tray; show() keeps a maximized window maximized.
        if (!m_window->isVisible())
            m_window->show();
        else if (m_window->visibility() == QWindow::Minimized)
            m_window->showNormal();
        m_window->raise();
        m_window->requestActivate();
    }
}
